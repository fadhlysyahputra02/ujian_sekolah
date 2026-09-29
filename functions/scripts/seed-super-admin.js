const admin = require('firebase-admin');

// Initialize Firebase Admin SDK
// Uses Application Default Credentials or GOOGLE_APPLICATION_CREDENTIALS environment variable
if (admin.apps.length === 0) {
  admin.initializeApp();
}

async function seedSuperAdminCLI() {
  const email = 'sadmin@sesicermat.com';
  const password = process.env.SUPER_ADMIN_PASSWORD || '11081987';
  const displayName = 'Super Admin';

  console.log(`[SEED] Initializing Super Admin account: ${email}...`);

  try {
    let userRecord;
    try {
      userRecord = await admin.auth().getUserByEmail(email);
      console.log(`[SEED] Account exists (UID: ${userRecord.uid}). Updating claims...`);
      await admin.auth().setCustomUserClaims(userRecord.uid, { role: 'super_admin' });
    } catch (error) {
      if (error.code === 'auth/user-not-found') {
        console.log(`[SEED] Account not found. Creating new user...`);
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

    // Write/Update user document in Firestore
    await admin.firestore().collection('users').doc(userRecord.uid).set({
      email,
      role: 'super_admin',
      schoolId: null,
      displayName,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`✅ [SEED] Super admin successfully seeded for UID: ${userRecord.uid}`);
    process.exit(0);
  } catch (err) {
    console.error('❌ [SEED ERROR]:', err);
    process.exit(1);
  }
}

seedSuperAdminCLI();
