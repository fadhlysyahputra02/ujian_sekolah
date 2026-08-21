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
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: 500,
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
                    isEdit ? 'Ubah Data Siswa' : 'Tambah Siswa Baru',
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

            // Scrollable Body
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

                      // NIS Field
                      TextFormField(
                        controller: _nisController,
                        decoration: InputDecoration(
                          labelText: 'NIS (Nomor Induk Siswa)',
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
                        validator: (value) => value == null || value.trim().isEmpty ? 'NIS wajib diisi' : null,
                      ),
                      const SizedBox(height: 16),

                      // Angkatan Field
                      TextFormField(
                        controller: _angkatanController,
                        decoration: InputDecoration(
                          labelText: 'Angkatan / Tahun Masuk',
                          prefixIcon: const Icon(Icons.calendar_today_outlined, color: Color(0xFF64748B)),
                          hintText: 'Misal: 2024',
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
                        validator: (value) => value == null || value.trim().isEmpty ? 'Angkatan wajib diisi' : null,
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
                              'Buat akun Auth sekarang',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                            ),
                            subtitle: const Text(
                              'Generate password sementara & izinkan login',
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
                        : Text(isEdit ? 'Simpan' : 'Tambah'),
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
