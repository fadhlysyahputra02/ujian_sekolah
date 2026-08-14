import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { FieldValue } from 'firebase-admin/firestore';

admin.initializeApp();

/**
 * Helper to verify school admin privileges.
 */
function verifySchoolAdmin(request: functions.https.CallableRequest, schoolId: string) {
  if (!request.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Pengguna harus login terlebih dahulu.'
    );
  }
  const token = request.auth.token;
  const isSuper = token.role === 'super_admin';
  const isSchoolAdmin = token.role === 'school_admin' && token.schoolId === schoolId;
  if (!isSuper && !isSchoolAdmin) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Hanya Super Admin atau Admin Sekolah terkait yang dapat melakukan operasi ini.'
    );
  }
}

/**
 * Helper to write audit logs.
 */
async function writeAuditLog(db: admin.firestore.Firestore, schoolId: string, actorUid: string, action: string, message: string) {
  await db.collection('schools').doc(schoolId).collection('auditLogs').add({
    action,
    actorUid,
    timestamp: FieldValue.serverTimestamp(),
    payloadSummary: message
  });
}

/**
 * Seed Super Admin account sadmin@sesicermat.com / 11081987.
 * Can be called anonymously to initialize the project database.
 */
export const seedSuperAdmin = functions.https.onCall(async (request) => {
  const email = 'sadmin@sesicermat.com';
  const password = '11081987';
  const displayName = 'Super Admin';

  try {
    let userRecord: admin.auth.UserRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
      // Set claims if user already exists
      await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'super_admin' });
    } catch (error: any) {
      if (error.code === 'auth/user-not-found') {
        userRecord = await admin.auth().createUser({
          email,
          password,
          displayName,
          emailVerified: true,
        });
        await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'super_admin' });
      } else {
        throw error;
      }
    }

    // Write to users collection
    await admin.firestore().collection('users').doc(userRecord.uid).set({
      email,
      role: 'super_admin',
      schoolId: null,
      displayName,
      createdAt: FieldValue.serverTimestamp(),
    }, { merge: true });

    return { success: true, message: 'Super admin successfully seeded.' };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Error seeding super admin');
  }
});

/**
 * Creates a new school and registers its initial school_admin.
 * Must be called by a Super Admin.
 */
export const createSchool = functions.https.onCall(async (request) => {
  // Check auth and role
  if (!request.auth || request.auth.token.role !== 'super_admin') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'The function must be called by an authenticated super admin.'
    );
  }

  const { name, code, adminEmail, adminPassword, adminName } = request.data || {};

  if (!name || !code || !adminEmail || !adminPassword || !adminName) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'The function must be called with all required school and admin details.'
    );
  }

  try {
    const db = admin.firestore();

    // 1. Create a school document with an auto-generated ID
    const schoolRef = db.collection('schools').doc();
    const schoolId = schoolRef.id;

    // 2. Create the school admin user in Firebase Auth
    const userRecord = await admin.auth().createUser({
      email: adminEmail,
      password: adminPassword,
      displayName: adminName,
      emailVerified: true,
    });

    // 3. Set Custom Claims (role & schoolId)
    await admin.auth().setCustomUserClaims(userRecord.uid, {
      role: 'school_admin',
      schoolId: schoolId,
    });

    // 4. Save School document in Firestore
    await schoolRef.set({
      name,
      code,
      disabled: false,
      adminEmail,
      createdAt: FieldValue.serverTimestamp(),
      meta: {
        teacherCount: 0,
        studentCount: 0,
      },
    });

    // 5. Save User document in Firestore
    await db.collection('users').doc(userRecord.uid).set({
      email: adminEmail,
      role: 'school_admin',
      schoolId: schoolId,
      displayName: adminName,
      createdAt: FieldValue.serverTimestamp(),
    });

    return { success: true, schoolId, adminUid: userRecord.uid };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Error creating school');
  }
});

/**
 * Toggles the school status (enabled/disabled).
 * Must be called by a Super Admin.
 */
export const toggleSchoolStatus = functions.https.onCall(async (request) => {
  // Check auth and role
  if (!request.auth || request.auth.token.role !== 'super_admin') {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'The function must be called by an authenticated super admin.'
    );
  }

  const { schoolId, disabled } = request.data || {};

  if (!schoolId || typeof disabled !== 'boolean') {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'The function must be called with schoolId and disabled status (boolean).'
    );
  }

  try {
    const db = admin.firestore();

    // Update the school's disabled state
    await db.collection('schools').doc(schoolId).update({
      disabled,
      updatedAt: FieldValue.serverTimestamp(),
    });

    return { success: true, message: `School status successfully updated to ${disabled ? 'Disabled' : 'Enabled'}.` };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Error updating school status');
  }
});

/**
 * Creates a new teacher.
 */
export const createTeacher = functions.https.onCall(async (request) => {
  const { schoolId, displayName, gender, nip, email, subjects, createAuth } = request.data || {};

  if (!schoolId || !displayName || !gender || !nip || !Array.isArray(subjects)) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Parameter yang diperlukan tidak lengkap.'
    );
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  let uid: string | null = null;
  let tempPassword = '';

  try {
    const loginEmail = email ? email.trim() : (createAuth ? `t_${nip}_${schoolId}@sesicermat.com` : null);

    // 1. Create Firebase Auth user if requested
    if (createAuth && loginEmail) {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
      for (let i = 0; i < 10; i++) {
        tempPassword += chars.charAt(Math.floor(Math.random() * chars.length));
      }

      const userRecord = await admin.auth().createUser({
        email: loginEmail,
        password: tempPassword,
        displayName,
      });

      await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'teacher', schoolId });
      uid = userRecord.uid;
    }

    // 2. Transaction for NIP uniqueness check and document writes
    const result = await db.runTransaction(async (transaction) => {
      const teachersRef = db.collection('schools').doc(schoolId).collection('teachers');
      const q = teachersRef.where('nip', '==', nip).where('archived', '==', false);
      const querySnap = await transaction.get(q);

      if (!querySnap.empty) {
        throw new functions.https.HttpsError(
          'already-exists',
          `Guru dengan NIP ${nip} sudah terdaftar di sekolah ini.`
        );
      }

      const newDocRef = teachersRef.doc();
      transaction.set(newDocRef, {
        uid,
        displayName,
        email: loginEmail,
        gender,
        nip,
        subjects,
        schoolId,
        disabled: false,
        archived: false,
        tempPassword: createAuth ? tempPassword : null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        deletedAt: null
      });

      if (uid && loginEmail) {
        const globalUserRef = db.collection('users').doc(uid);
        transaction.set(globalUserRef, {
          uid,
          email: loginEmail,
          role: 'teacher',
          schoolId,
          profileRef: newDocRef.path,
          createdAt: FieldValue.serverTimestamp()
        });
      }

      const schoolRef = db.collection('schools').doc(schoolId);
      transaction.update(schoolRef, {
        'meta.teacherCount': FieldValue.increment(1)
      });

      return { teacherId: newDocRef.id };
    });

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'CREATE_TEACHER', `Membuat guru NIP: ${nip}`);

    return {
      success: true,
      teacherId: result.teacherId,
      tempPassword: createAuth ? tempPassword : undefined
    };
  } catch (err: any) {
    if (uid) {
      await admin.auth().deleteUser(uid).catch(console.error);
    }
    throw new functions.https.HttpsError('internal', err.message || 'Gagal membuat guru.');
  }
});

/**
 * Creates a new student.
 */
export const createStudent = functions.https.onCall(async (request) => {
  const { schoolId, displayName, gender, nis, angkatan, email, createAuth } = request.data || {};

  if (!schoolId || !displayName || !gender || !nis || !angkatan) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Parameter yang diperlukan tidak lengkap.'
    );
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  let uid: string | null = null;
  let tempPassword = '';

  try {
    const loginEmail = email ? email.trim() : (createAuth ? `s_${nis}_${schoolId}@sesicermat.com` : null);

    if (createAuth && loginEmail) {
      const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
      for (let i = 0; i < 10; i++) {
        tempPassword += chars.charAt(Math.floor(Math.random() * chars.length));
      }

      const userRecord = await admin.auth().createUser({
        email: loginEmail,
        password: tempPassword,
        displayName,
      });

      await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'student', schoolId });
      uid = userRecord.uid;
    }

    const result = await db.runTransaction(async (transaction) => {
      const studentsRef = db.collection('schools').doc(schoolId).collection('students');
      const q = studentsRef.where('nis', '==', nis).where('archived', '==', false);
      const querySnap = await transaction.get(q);

      if (!querySnap.empty) {
        throw new functions.https.HttpsError(
          'already-exists',
          `Murid dengan NIS ${nis} sudah terdaftar di sekolah ini.`
        );
      }

      const newDocRef = studentsRef.doc();
      transaction.set(newDocRef, {
        uid,
        displayName,
        nis,
        gender,
        angkatan,
        email: loginEmail,
        schoolId,
        disabled: false,
        archived: false,
        tempPassword: createAuth ? tempPassword : null,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        deletedAt: null
      });

      if (uid && loginEmail) {
        const globalUserRef = db.collection('users').doc(uid);
        transaction.set(globalUserRef, {
          uid,
          email: loginEmail,
          role: 'student',
          schoolId,
          profileRef: newDocRef.path,
          createdAt: FieldValue.serverTimestamp()
        });
      }

      const schoolRef = db.collection('schools').doc(schoolId);
      transaction.update(schoolRef, {
        'meta.studentCount': FieldValue.increment(1)
      });

      return { studentId: newDocRef.id };
    });

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'CREATE_STUDENT', `Membuat murid NIS: ${nis}`);

    return {
      success: true,
      studentId: result.studentId,
      tempPassword: createAuth ? tempPassword : undefined
    };
  } catch (err: any) {
    if (uid) {
      await admin.auth().deleteUser(uid).catch(console.error);
    }
    throw new functions.https.HttpsError('internal', err.message || 'Gagal membuat murid.');
  }
});

/**
 * Updates an existing teacher.
 */
export const updateTeacher = functions.https.onCall(async (request) => {
  const { schoolId, docId, displayName, gender, nip, email, subjects } = request.data || {};

  if (!schoolId || !docId || !displayName || !gender || !nip || !Array.isArray(subjects)) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  try {
    await db.runTransaction(async (transaction) => {
      const docRef = db.collection('schools').doc(schoolId).collection('teachers').doc(docId);
      const docSnap = await transaction.get(docRef);
      if (!docSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Guru tidak ditemukan.');
      }

      const currentData = docSnap.data();
      if (currentData?.nip !== nip) {
        const q = db.collection('schools').doc(schoolId).collection('teachers')
          .where('nip', '==', nip).where('archived', '==', false);
        const querySnap = await transaction.get(q);
        if (!querySnap.empty) {
          throw new functions.https.HttpsError('already-exists', `Guru dengan NIP ${nip} sudah terdaftar.`);
        }
      }

      transaction.update(docRef, {
        displayName,
        gender,
        nip,
        email: email || null,
        subjects,
        updatedAt: FieldValue.serverTimestamp()
      });

      const uid = currentData?.uid;
      if (uid) {
        const globalUserRef = db.collection('users').doc(uid);
        transaction.update(globalUserRef, {
          email: email || null
        });
      }
    });

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'UPDATE_TEACHER', `Mengupdate guru NIP: ${nip}`);

    return { success: true };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal mengupdate guru.');
  }
});

/**
 * Updates an existing student.
 */
export const updateStudent = functions.https.onCall(async (request) => {
  const { schoolId, docId, displayName, gender, nis, angkatan, email } = request.data || {};

  if (!schoolId || !docId || !displayName || !gender || !nis || !angkatan) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  try {
    await db.runTransaction(async (transaction) => {
      const docRef = db.collection('schools').doc(schoolId).collection('students').doc(docId);
      const docSnap = await transaction.get(docRef);
      if (!docSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Murid tidak ditemukan.');
      }

      const currentData = docSnap.data();
      if (currentData?.nis !== nis) {
        const q = db.collection('schools').doc(schoolId).collection('students')
          .where('nis', '==', nis).where('archived', '==', false);
        const querySnap = await transaction.get(q);
        if (!querySnap.empty) {
          throw new functions.https.HttpsError('already-exists', `Murid dengan NIS ${nis} sudah terdaftar.`);
        }
      }

      transaction.update(docRef, {
        displayName,
        gender,
        nis,
        angkatan,
        email: email || null,
        updatedAt: FieldValue.serverTimestamp()
      });

      const uid = currentData?.uid;
      if (uid) {
        const globalUserRef = db.collection('users').doc(uid);
        transaction.update(globalUserRef, {
          email: email || null
        });
      }
    });

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'UPDATE_STUDENT', `Mengupdate murid NIS: ${nis}`);

    return { success: true };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal mengupdate murid.');
  }
});

/**
 * Generates a new temporary password and updates or creates a Firebase Auth account.
 */
export const generateTempPassword = functions.https.onCall(async (request) => {
  const { schoolId, collectionType, docId } = request.data || {};

  if (!schoolId || !collectionType || !docId) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  const docRef = db.collection('schools').doc(schoolId).collection(collectionType).doc(docId);
  const docSnap = await docRef.get();
  if (!docSnap.exists) {
    throw new functions.https.HttpsError('not-found', 'Profil pengguna tidak ditemukan.');
  }

  const currentData = docSnap.data();
  let uid = currentData?.uid;
  const email = currentData?.email;
  const displayName = currentData?.displayName;
  const identifier = collectionType === 'teachers' ? currentData?.nip : currentData?.nis;

  if (!email) {
    throw new functions.https.HttpsError(
      'failed-precondition',
      'Pengguna ini tidak memiliki email. Tambahkan email terlebih dahulu untuk membuat akun login.'
    );
  }

  const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
  let tempPassword = '';
  for (let i = 0; i < 10; i++) {
    tempPassword += chars.charAt(Math.floor(Math.random() * chars.length));
  }

  try {
    if (!uid) {
      // 1. Create a new Firebase Auth user
      const userRecord = await admin.auth().createUser({
        email,
        password: tempPassword,
        displayName,
      });

      const role = collectionType === 'teachers' ? 'teacher' : 'student';
      await admin.auth().setCustomUserClaims(userRecord.uid, { role, schoolId });
      uid = userRecord.uid;

      // 2. Update documents in transaction
      await db.runTransaction(async (transaction) => {
        transaction.update(docRef, {
          uid,
          tempPassword,
          updatedAt: FieldValue.serverTimestamp()
        });

        const globalUserRef = db.collection('users').doc(uid);
        transaction.set(globalUserRef, {
          uid,
          email,
          role,
          schoolId,
          profileRef: docRef.path,
          createdAt: FieldValue.serverTimestamp()
        });
      });
    } else {
      // 3. Just update the password on the existing Auth user
      await admin.auth().updateUser(uid, {
        password: tempPassword
      });
      // Update tempPassword in Firestore doc
      await docRef.update({
        tempPassword,
        updatedAt: FieldValue.serverTimestamp()
      });
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'GENERATE_PASSWORD', `Membuat kata sandi sementara untuk ID: ${identifier}`);

    return { success: true, tempPassword };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal menghasilkan kata sandi sementara.');
  }
});

/**
 * Soft deletes a user and copies their document to the archives.
 */
export const softDeleteUser = functions.https.onCall(async (request) => {
  const { schoolId, collectionType, docId, reason } = request.data || {};

  if (!schoolId || !collectionType || !docId) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  try {
    await db.runTransaction(async (transaction) => {
      const docRef = db.collection('schools').doc(schoolId).collection(collectionType).doc(docId);
      const docSnap = await transaction.get(docRef);
      if (!docSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Pengguna tidak ditemukan.');
      }

      const currentData = docSnap.data();
      if (currentData?.archived) {
        return; // Already archived
      }

      transaction.update(docRef, {
        disabled: true,
        archived: true,
        updatedAt: FieldValue.serverTimestamp(),
        deletedAt: FieldValue.serverTimestamp()
      });

      const archiveRef = db.collection('archives').doc(schoolId).collection('users').doc(docId);
      transaction.set(archiveRef, {
        ...currentData,
        disabled: true,
        archived: true,
        deletedAt: FieldValue.serverTimestamp(),
        collectionType,
        reason: reason || null
      });

      const schoolRef = db.collection('schools').doc(schoolId);
      if (collectionType === 'teachers') {
        transaction.update(schoolRef, {
          'meta.teacherCount': FieldValue.increment(-1)
        });
      } else {
        transaction.update(schoolRef, {
          'meta.studentCount': FieldValue.increment(-1)
        });
      }
    });

    const docSnap = await db.collection('schools').doc(schoolId).collection(collectionType).doc(docId).get();
    const uid = docSnap.data()?.uid;
    const identifier = collectionType === 'teachers' ? docSnap.data()?.nip : docSnap.data()?.nis;

    if (uid) {
      await admin.auth().updateUser(uid, { disabled: true }).catch(console.error);
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'SOFT_DELETE', `Mengarsipkan pengguna ID: ${identifier}`);

    return { success: true };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal mengarsipkan pengguna.');
  }
});

/**
 * Restores a soft-deleted user.
 */
export const restoreUser = functions.https.onCall(async (request) => {
  const { schoolId, collectionType, docId } = request.data || {};

  if (!schoolId || !collectionType || !docId) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();

  try {
    await db.runTransaction(async (transaction) => {
      const docRef = db.collection('schools').doc(schoolId).collection(collectionType).doc(docId);
      const docSnap = await transaction.get(docRef);
      if (!docSnap.exists) {
        throw new functions.https.HttpsError('not-found', 'Pengguna tidak ditemukan.');
      }

      const currentData = docSnap.data();
      if (!currentData?.archived) {
        return; // Already active
      }

      transaction.update(docRef, {
        disabled: false,
        archived: false,
        updatedAt: FieldValue.serverTimestamp(),
        deletedAt: null
      });

      const archiveRef = db.collection('archives').doc(schoolId).collection('users').doc(docId);
      transaction.delete(archiveRef);

      const schoolRef = db.collection('schools').doc(schoolId);
      if (collectionType === 'teachers') {
        transaction.update(schoolRef, {
          'meta.teacherCount': FieldValue.increment(1)
        });
      } else {
        transaction.update(schoolRef, {
          'meta.studentCount': FieldValue.increment(1)
        });
      }
    });

    const docSnap = await db.collection('schools').doc(schoolId).collection(collectionType).doc(docId).get();
    const uid = docSnap.data()?.uid;
    const identifier = collectionType === 'teachers' ? docSnap.data()?.nip : docSnap.data()?.nis;

    if (uid) {
      await admin.auth().updateUser(uid, { disabled: false }).catch(console.error);
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'RESTORE', `Memulihkan pengguna ID: ${identifier}`);

    return { success: true };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal memulihkan pengguna.');
  }
});

/**
 * Permanently deletes a user (Super Admin only).
 */
export const permanentDeleteUser = functions.https.onCall(async (request) => {
  const { schoolId, collectionType, docId } = request.data || {};

  if (!schoolId || !collectionType || !docId) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);

  const db = admin.firestore();

  try {
    const docRef = db.collection('schools').doc(schoolId).collection(collectionType).doc(docId);
    const snap = await docRef.get();
    if (!snap.exists) {
      throw new functions.https.HttpsError('not-found', 'Pengguna tidak ditemukan.');
    }
    const data = snap.data();
    const uid = data?.uid;
    const identifier = collectionType === 'teachers' ? data?.nip : data?.nis;

    await db.runTransaction(async (transaction) => {
      const docSnap = await transaction.get(docRef);
      if (docSnap.exists) {
        const docData = docSnap.data();
        if (!docData?.archived) {
          const schoolRef = db.collection('schools').doc(schoolId);
          if (collectionType === 'teachers') {
            transaction.update(schoolRef, {
              'meta.teacherCount': FieldValue.increment(-1)
            });
          } else {
            transaction.update(schoolRef, {
              'meta.studentCount': FieldValue.increment(-1)
            });
          }
        }
      }

      transaction.delete(docRef);

      const archiveRef = db.collection('archives').doc(schoolId).collection('users').doc(docId);
      transaction.delete(archiveRef);

      if (uid) {
        const globalUserRef = db.collection('users').doc(uid);
        transaction.delete(globalUserRef);
      }
    });

    if (uid) {
      await admin.auth().deleteUser(uid).catch(console.error);
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'PERMANENT_DELETE', `Menghapus permanen pengguna ID: ${identifier}`);

    return { success: true };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal menghapus permanen.');
  }
});

/**
 * Bulk imports students.
 */
export const importStudentsBulk = functions.https.onCall(async (request) => {
  const { schoolId, rows, createAuth } = request.data || {};

  if (!schoolId || !Array.isArray(rows)) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();
  const results: Array<{ rowIndex: number; success: boolean; errors: string[]; tempPassword?: string }> = [];

  try {
    // Read existing students to detect duplicates
    const studentsRef = db.collection('schools').doc(schoolId).collection('students');
    const existingSnap = await studentsRef.where('archived', '==', false).get();
    const existingNisSet = new Set(existingSnap.docs.map(doc => doc.data().nis.toString().trim()));

    const processedNis = new Set<string>();

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const { name, gender, nis, angkatan, email } = row;
      const errors: string[] = [];

      const cleanName = name?.toString().trim();
      const cleanGender = gender?.toString().trim().toUpperCase();
      const cleanNis = nis?.toString().trim();
      const cleanAngkatan = angkatan?.toString().trim();
      const cleanEmail = email?.toString().trim();

      if (!cleanName) errors.push('Nama wajib diisi.');
      if (!cleanGender || (cleanGender !== 'M' && cleanGender !== 'F')) errors.push('Gender harus M atau F.');
      if (!cleanNis) errors.push('NIS wajib diisi.');
      if (!cleanAngkatan) errors.push('Angkatan wajib diisi.');
      if (createAuth && !cleanEmail) errors.push('Email wajib diisi untuk membuat akun Auth.');

      if (cleanNis) {
        if (existingNisSet.has(cleanNis)) {
          errors.push(`NIS ${cleanNis} sudah terdaftar di sekolah.`);
        }
        if (processedNis.has(cleanNis)) {
          errors.push(`NIS ${cleanNis} duplikat dalam file impor.`);
        }
        processedNis.add(cleanNis);
      }

      if (errors.length > 0) {
        results.push({ rowIndex: i, success: false, errors });
        continue;
      }

      try {
        let uid: string | null = null;
        let tempPassword = '';

        if (createAuth && cleanEmail) {
          const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
          for (let j = 0; j < 10; j++) {
            tempPassword += chars.charAt(Math.floor(Math.random() * chars.length));
          }

          const userRecord = await admin.auth().createUser({
            email: cleanEmail,
            password: tempPassword,
            displayName: cleanName,
          });

          await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'student', schoolId });
          uid = userRecord.uid;
        }

        const newDocRef = studentsRef.doc();
        await newDocRef.set({
          uid,
          displayName: cleanName,
          nis: cleanNis,
          gender: cleanGender,
          angkatan: cleanAngkatan,
          email: cleanEmail || null,
          schoolId,
          disabled: false,
          archived: false,
          tempPassword: createAuth ? tempPassword : null,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          deletedAt: null
        });

        if (uid && cleanEmail) {
          await db.collection('users').doc(uid).set({
            uid,
            email: cleanEmail,
            role: 'student',
            schoolId,
            profileRef: newDocRef.path,
            createdAt: FieldValue.serverTimestamp()
          });
        }

        await db.collection('schools').doc(schoolId).update({
          'meta.studentCount': FieldValue.increment(1)
        });

        results.push({
          rowIndex: i,
          success: true,
          errors: [],
          tempPassword: createAuth ? tempPassword : undefined
        });
      } catch (err: any) {
        results.push({
          rowIndex: i,
          success: false,
          errors: [err.message || 'Error internal saat mengimpor baris ini.']
        });
      }
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'IMPORT_STUDENTS', `Mengimpor ${rows.length} data murid.`);

    return { results };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal memproses impor massal.');
  }
});

/**
 * Resolves user email by temporary password (for auto-routing login).
 */
export const resolveEmailByPassword = functions.https.onCall(async (request) => {
  const { schoolId, password } = request.data || {};

  if (!schoolId || !password) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  const db = admin.firestore();

  try {
    // 1. Search in teachers NIP/TempPassword
    const teachersQuery = await db.collection('schools')
        .doc(schoolId)
        .collection('teachers')
        .where('tempPassword', '==', password)
        .where('archived', '==', false)
        .get();

    if (!teachersQuery.empty) {
      const teacherData = teachersQuery.docs[0].data();
      return { success: true, email: teacherData.email };
    }

    // 2. Search in students NIS/TempPassword
    const studentsQuery = await db.collection('schools')
        .doc(schoolId)
        .collection('students')
        .where('tempPassword', '==', password)
        .where('archived', '==', false)
        .get();

    if (!studentsQuery.empty) {
      const studentData = studentsQuery.docs[0].data();
      return { success: true, email: studentData.email };
    }

    return { success: false };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal memverifikasi password.');
  }
});

/**
 * Bulk import teachers from Excel / CSV.
 */
export const importTeachersBulk = functions.https.onCall(async (request) => {
  const { schoolId, rows, createAuth } = request.data || {};

  if (!schoolId || !Array.isArray(rows)) {
    throw new functions.https.HttpsError('invalid-argument', 'Parameter tidak lengkap.');
  }

  verifySchoolAdmin(request, schoolId);
  const db = admin.firestore();
  const results: Array<{ rowIndex: number; success: boolean; errors: string[]; tempPassword?: string }> = [];

  try {
    const teachersRef = db.collection('schools').doc(schoolId).collection('teachers');
    const existingSnap = await teachersRef.where('archived', '==', false).get();
    const existingNipSet = new Set(existingSnap.docs.map(doc => doc.data().nip.toString().trim()));

    const processedNip = new Set<string>();

    for (let i = 0; i < rows.length; i++) {
      const row = rows[i];
      const { name, gender, nip, email } = row;
      const errors: string[] = [];

      const cleanName = name?.toString().trim();
      const cleanGender = gender?.toString().trim().toUpperCase();
      const cleanNip = nip?.toString().trim();
      const cleanEmail = email?.toString().trim();

      if (!cleanName) errors.push('Nama wajib diisi.');
      if (!cleanGender || (cleanGender !== 'M' && cleanGender !== 'F')) errors.push('Gender harus M atau F.');
      if (!cleanNip) errors.push('NIP wajib diisi.');

      if (cleanNip) {
        if (existingNipSet.has(cleanNip)) {
          errors.push(`NIP ${cleanNip} sudah terdaftar di sekolah.`);
        }
        if (processedNip.has(cleanNip)) {
          errors.push(`NIP ${cleanNip} duplikat dalam file impor.`);
        }
        processedNip.add(cleanNip);
      }

      if (errors.length > 0) {
        results.push({ rowIndex: i, success: false, errors });
        continue;
      }

      try {
        let uid: string | null = null;
        let tempPassword = '';
        const loginEmail = cleanEmail || (createAuth ? `t_${cleanNip}_${schoolId}@sesicermat.com` : null);

        if (createAuth && loginEmail) {
          const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
          for (let j = 0; j < 10; j++) {
            tempPassword += chars.charAt(Math.floor(Math.random() * chars.length));
          }

          const userRecord = await admin.auth().createUser({
            email: loginEmail,
            password: tempPassword,
            displayName: cleanName,
          });

          await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'teacher', schoolId });
          uid = userRecord.uid;
        }

        const newDocRef = teachersRef.doc();
        await newDocRef.set({
          uid,
          displayName: cleanName,
          nip: cleanNip,
          gender: cleanGender,
          email: loginEmail,
          subjects: [], // No subjects by default
          schoolId,
          disabled: false,
          archived: false,
          tempPassword: createAuth ? tempPassword : null,
          createdAt: FieldValue.serverTimestamp(),
          updatedAt: FieldValue.serverTimestamp(),
          deletedAt: null
        });

        if (uid && loginEmail) {
          await db.collection('users').doc(uid).set({
            uid,
            email: loginEmail,
            role: 'teacher',
            schoolId,
            profileRef: newDocRef.path,
            createdAt: FieldValue.serverTimestamp()
          });
        }

        await db.collection('schools').doc(schoolId).update({
          'meta.teacherCount': FieldValue.increment(1)
        });

        results.push({
          rowIndex: i,
          success: true,
          errors: [],
          tempPassword: createAuth ? tempPassword : undefined
        });
      } catch (err: any) {
        results.push({
          rowIndex: i,
          success: false,
          errors: [err.message || 'Error internal saat mengimpor baris ini.']
        });
      }
    }

    const actorUid = request.auth?.uid || 'system';
    await writeAuditLog(db, schoolId, actorUid, 'IMPORT_TEACHERS', `Mengimpor ${rows.length} data guru.`);

    return { results };
  } catch (err: any) {
    throw new functions.https.HttpsError('internal', err.message || 'Gagal memproses impor massal.');
  }
});

