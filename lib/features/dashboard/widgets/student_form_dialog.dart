import 'package:flutter/material.dart';
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import 'generate_password_dialog.dart';

class StudentFormDialog extends StatefulWidget {
  final String schoolId;
  final Student? student; // Null for add mode, non-null for edit mode

  const StudentFormDialog({
    super.key,
    required this.schoolId,
    this.student,
  });

  @override
  State<StudentFormDialog> createState() => _StudentFormDialogState();
}

class _StudentFormDialogState extends State<StudentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _nisController = TextEditingController();
  final _angkatanController = TextEditingController();
  final _emailController = TextEditingController();

  String _selectedGender = 'M';
  bool _createAuth = false;
  bool _isLoading = false;

  final AdminUserService _adminUserService = AdminUserService();

  @override
  void initState() {
    super.initState();
    if (widget.student != null) {
      _nameController.text = widget.student!.displayName;
      _nisController.text = widget.student!.nis;
      _angkatanController.text = widget.student!.angkatan;
      _emailController.text = widget.student!.email ?? '';
      _selectedGender = widget.student!.gender;
      _createAuth = widget.student!.uid != null;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nisController.dispose();
    _angkatanController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.student == null) {
        // Create mode
        final result = await _adminUserService.createStudent(
          schoolId: widget.schoolId,
          displayName: _nameController.text.trim(),
          gender: _selectedGender,
          nis: _nisController.text.trim(),
          angkatan: _angkatanController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
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
              const SnackBar(content: Text('Siswa berhasil ditambahkan!')),
            );
          }
        }
      } else {
        // Edit mode
        await _adminUserService.updateStudent(
          schoolId: widget.schoolId,
          docId: widget.student!.id,
          displayName: _nameController.text.trim(),
          gender: _selectedGender,
          nis: _nisController.text.trim(),
          angkatan: _angkatanController.text.trim(),
          email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        );

        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profil siswa berhasil diperbarui!')),
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
    final isEdit = widget.student != null;
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
                      isEdit ? 'Ubah Data Siswa' : 'Tambah Siswa Baru',
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

                // NIS Field
                TextFormField(
                  controller: _nisController,
                  decoration: InputDecoration(
                    labelText: 'NIS (Nomor Induk Siswa)',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'NIS wajib diisi' : null,
                ),
                const SizedBox(height: 16),

                // Angkatan Field
                TextFormField(
                  controller: _angkatanController,
                  decoration: InputDecoration(
                    labelText: 'Angkatan / Tahun Masuk',
                    prefixIcon: const Icon(Icons.calendar_today_outlined),
                    hintText: 'Misal: 2024',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty ? 'Angkatan wajib diisi' : null,
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
