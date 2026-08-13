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
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(28.0),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isEdit ? 'Ubah Data Guru' : 'Tambah Guru Baru',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const Divider(),
                const SizedBox(height: 16),
                
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nama Lengkap',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Nama lengkap wajib diisi' : null,
                ),
                const SizedBox(height: 16),

                // NIP Field
                TextFormField(
                  controller: _nipController,
                  decoration: InputDecoration(
                    labelText: 'NIP (Nomor Induk Pegawai)',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'NIP wajib diisi' : null,
                ),
                const SizedBox(height: 16),

                // Gender Select
                Row(
                  children: [
                    const Text('Jenis Kelamin: ', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 16),
                    ChoiceChip(
                      label: const Text('Laki-laki (M)'),
                      selected: _selectedGender == 'M',
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedGender = 'M');
                      },
                    ),
                    const SizedBox(width: 12),
                    ChoiceChip(
                      label: const Text('Perempuan (F)'),
                      selected: _selectedGender == 'F',
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedGender = 'F');
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email (Opsional)',
                    prefixIcon: const Icon(Icons.mail_outline_rounded),
                    helperText: _createAuth ? 'Jika dikosongkan, sistem akan membuat email login otomatis' : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                // Subjects Select Tagging Field
                const Text('Pilih Mata Pelajaran:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                if (_isLoadingSubjects)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ))
                else if (_schoolSubjects.isEmpty)
                  const Text(
                    'Belum ada mata pelajaran terdaftar. Harap tambahkan mata pelajaran di Tab Mata Pelajaran terlebih dahulu.',
                    style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _schoolSubjects.map((sub) {
                      final name = sub['name'] as String;
                      final isSelected = _subjects.contains(name);
                      return FilterChip(
                        label: Text("$name (${sub['code']})"),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _subjects.add(name);
                            } else {
                              _subjects.remove(name);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 16),

                // Create Auth Checkbox (Only if not already created)
                if (!isEdit) ...[
                  CheckboxListTile(
                    title: const Text('Buat akun Auth sekarang'),
                    subtitle: const Text('Generate password sementara & izinkan login'),
                    value: _createAuth,
                    onChanged: (val) {
                      setState(() {
                        _createAuth = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                ],

                // Action Buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text('Batal'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text(isEdit ? 'Simpan' : 'Tambah'),
                    ),
                  ],
                )
              ],
            ),
          ),
        ),
      ),
    );
  }
}
