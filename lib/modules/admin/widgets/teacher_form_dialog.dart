import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/models/teacher.dart';
import '../../../core/services/admin_user_service.dart';
import 'generate_password_dialog.dart';

class TeacherFormDialog extends StatefulWidget {
  final String schoolId;
  final Teacher? teacher; // Null for add mode, non-null for edit mode

  const TeacherFormDialog({
    super.key,
    required this.schoolId,
    this.teacher,
  });

  @override
  State<TeacherFormDialog> createState() => _TeacherFormDialogState();
}

class _TeacherFormDialogState extends State<TeacherFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nipController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedGender = 'M';
  List<String> _subjects = [];
  bool _createAuth = false;
  bool _isLoading = false;

  // New subject states
  List<Map<String, dynamic>> _schoolSubjects = [];
  bool _isLoadingSubjects = true;

  final AdminUserService _adminUserService = AdminUserService();

  @override
  void initState() {
    super.initState();
    _fetchSchoolSubjects();
    if (widget.teacher != null) {
      _nameController.text = widget.teacher!.displayName;
      _nipController.text = widget.teacher!.nip;
      _emailController.text = widget.teacher!.email ?? '';
      _selectedGender = widget.teacher!.gender;
      _subjects = List<String>.from(widget.teacher!.subjects);
      _createAuth = widget.teacher!.uid != null;
    }
  }

  Future<void> _fetchSchoolSubjects() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('subjects')
          .orderBy('name')
          .get();
      if (mounted) {
        setState(() {
          _schoolSubjects = snapshot.docs.map((doc) => {
            'id': doc.id,
            'name': doc.data()['name'],
            'code': doc.data()['code'],
          }).toList();
          _isLoadingSubjects = false;
        });
      }
    } catch (e) {
      debugPrint("Gagal mengambil data mapel: $e");
      if (mounted) {
        setState(() {
          _isLoadingSubjects = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nipController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.teacher == null) {
        // Create mode
        final result = await _adminUserService.createTeacher(
          schoolId: widget.schoolId,
          displayName: _nameController.text.trim(),
          gender: _selectedGender,
          nip: _nipController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          subjects: _subjects,
          createAuth: _createAuth,
        );

        if (mounted) {
          Navigator.of(context).pop(); // Close Form Dialog
          
          // If tempPassword is generated, show GeneratePasswordDialog
          if (result['tempPassword'] != null) {
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => GeneratePasswordDialog(
                tempPassword: result['tempPassword'],
                displayName: _nameController.text.trim(),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Guru berhasil ditambahkan!')),
            );
          }
        }
      } else {
        // Edit mode
        await _adminUserService.updateTeacher(
          schoolId: widget.schoolId,
          docId: widget.teacher!.id,
          displayName: _nameController.text.trim(),
          gender: _selectedGender,
          nip: _nipController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
          subjects: _subjects,
        );

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil guru berhasil diperbarui!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses data: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.teacher != null;
    final double screenWidth = MediaQuery.of(context).size.width;
    final double gridAspectRatio = screenWidth > 600 ? 3.2 : 2.2;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 550,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height - MediaQuery.of(context).viewInsets.bottom - 40,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF4F46E5), Color(0xFF3730A3)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEdit ? 'Ubah Data Guru' : 'Tambah Guru Baru',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.of(context).pop(),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
            // Scrollable Form Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: 'Nama Lengkap',
                          prefixIcon: const Icon(Icons.person_outline_rounded, color: Color(0xFF64748B)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? 'Nama lengkap wajib diisi' : null,
                      ),
                      const SizedBox(height: 16),

                      // NIP Field
                      TextFormField(
                        controller: _nipController,
                        decoration: InputDecoration(
                          labelText: 'NIP (Nomor Induk Pegawai)',
                          prefixIcon: const Icon(Icons.badge_outlined, color: Color(0xFF64748B)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        ),
                        validator: (value) => value == null || value.trim().isEmpty ? 'NIP wajib diisi' : null,
                      ),
                      const SizedBox(height: 18),

                      // Gender Select (Segmented custom buttons)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Jenis Kelamin:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _selectedGender = 'M'),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _selectedGender == 'M' ? const Color(0xFFEEF2FF) : Colors.white,
                                      border: Border.all(
                                        color: _selectedGender == 'M' ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                        width: _selectedGender == 'M' ? 1.5 : 1.0,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.male_rounded,
                                          color: _selectedGender == 'M' ? const Color(0xFF4F46E5) : const Color(0xFF64748B),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Laki-laki (M)',
                                          style: TextStyle(
                                            fontWeight: _selectedGender == 'M' ? FontWeight.bold : FontWeight.normal,
                                            color: _selectedGender == 'M' ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _selectedGender = 'F'),
                                  borderRadius: BorderRadius.circular(10),
                                  child: Container(
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: _selectedGender == 'F' ? const Color(0xFFFDF2F8) : Colors.white,
                                      border: Border.all(
                                        color: _selectedGender == 'F' ? const Color(0xFFEC4899) : const Color(0xFFE2E8F0),
                                        width: _selectedGender == 'F' ? 1.5 : 1.0,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    alignment: Alignment.center,
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.female_rounded,
                                          color: _selectedGender == 'F' ? const Color(0xFFEC4899) : const Color(0xFF64748B),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Perempuan (F)',
                                          style: TextStyle(
                                            fontWeight: _selectedGender == 'F' ? FontWeight.bold : FontWeight.normal,
                                            color: _selectedGender == 'F' ? const Color(0xFF9D174D) : const Color(0xFF1E293B),
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'Email (Opsional)',
                          prefixIcon: const Icon(Icons.mail_outline_rounded, color: Color(0xFF64748B)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFF4F46E5), width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                          helperText: _createAuth ? 'Jika dikosongkan, sistem akan membuat email login otomatis' : null,
                          helperStyle: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Subjects Select Grid Field
                      const Text(
                        'Pilih Mata Pelajaran:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                      ),
                      const SizedBox(height: 8),
                      if (_isLoadingSubjects)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(16.0),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      else if (_schoolSubjects.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            border: Border.all(color: const Color(0xFFFEE2E2)),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Belum ada mata pelajaran terdaftar. Harap tambahkan mata pelajaran terlebih dahulu.',
                                  style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        )
                      else
                        Container(
                          height: 180,
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(12),
                            color: const Color(0xFFF8FAFC),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: RawScrollbar(
                            thumbColor: const Color(0xFFCBD5E1),
                            radius: const Radius.circular(4),
                            thickness: 4,
                            child: GridView.builder(
                              padding: const EdgeInsets.all(12),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: gridAspectRatio,
                              ),
                              itemCount: _schoolSubjects.length,
                              itemBuilder: (context, idx) {
                                final sub = _schoolSubjects[idx];
                                final name = sub['name'] as String;
                                final code = sub['code'] as String;
                                final isSelected = _subjects.contains(name);
                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _subjects.remove(name);
                                      } else {
                                        _subjects.add(name);
                                      }
                                    });
                                  },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isSelected ? const Color(0xFFEEF2FF) : Colors.white,
                                      border: Border.all(
                                        color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFFE2E8F0),
                                        width: isSelected ? 1.5 : 1.0,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                          color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                name,
                                                style: TextStyle(
                                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                                  fontSize: 12,
                                                  color: isSelected ? const Color(0xFF312E81) : const Color(0xFF1E293B),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              Text(
                                                code,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: isSelected ? const Color(0xFF6366F1) : const Color(0xFF64748B),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),

                      // Create Auth Checkbox (Only if not already created)
                      if (!isEdit) ...[
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.white,
                          ),
                          child: CheckboxListTile(
                            title: const Text(
                              'Buat akun login otomatis',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            subtitle: const Text(
                              'Sistem akan menghasilkan kata sandi sementara untuk guru ini.',
                              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                            ),
                            value: _createAuth,
                            onChanged: (val) {
                              setState(() {
                                _createAuth = val ?? false;
                              });
                            },
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            activeColor: const Color(0xFF4F46E5),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // Actions Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                color: Color(0xFFF8FAFC),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      foregroundColor: const Color(0xFF475569),
                    ),
                    child: const Text('Batal'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4F46E5),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                          )
                        : Text(isEdit ? 'Simpan Perubahan' : 'Tambah Guru'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
