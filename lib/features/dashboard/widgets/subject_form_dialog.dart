import 'package:flutter/material.dart';
import '../../../core/services/admin_user_service.dart';

class SubjectFormDialog extends StatefulWidget {
  final String schoolId;
  final Map<String, dynamic>? subject; // Null for add mode, non-null for edit mode

  const SubjectFormDialog({
    super.key,
    required this.schoolId,
    this.subject,
  });

  @override
  State<SubjectFormDialog> createState() => _SubjectFormDialogState();
}

class _SubjectFormDialogState extends State<SubjectFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _codeController = TextEditingController();
  bool _isLoading = false;

  final AdminUserService _adminUserService = AdminUserService();

  @override
  void initState() {
    super.initState();
    if (widget.subject != null) {
      _nameController.text = widget.subject!['name'] ?? '';
      _codeController.text = widget.subject!['code'] ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (widget.subject == null) {
        // Create mode
        await _adminUserService.addSubject(
          schoolId: widget.schoolId,
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
        );
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mata pelajaran berhasil ditambahkan!')),
          );
        }
      } else {
        // Edit mode
        await _adminUserService.updateSubject(
          schoolId: widget.schoolId,
          docId: widget.subject!['id'],
          name: _nameController.text.trim(),
          code: _codeController.text.trim(),
        );
        if (mounted) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mata pelajaran berhasil diperbarui!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan: $e'),
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
    final isEdit = widget.subject != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(28.0),
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
                    isEdit ? 'Ubah Mata Pelajaran' : 'Tambah Mata Pelajaran',
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
                  labelText: 'Nama Mata Pelajaran',
                  prefixIcon: const Icon(Icons.book_rounded),
                  hintText: 'Misal: Matematika, Fisika',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Nama mata pelajaran wajib diisi' : null,
              ),
              const SizedBox(height: 16),

              // Code Field
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Kode Singkatan / Abbrev',
                  prefixIcon: const Icon(Icons.abc_rounded),
                  hintText: 'Misal: MTK, FIS, KMA',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                validator: (value) => value == null || value.trim().isEmpty ? 'Kode mata pelajaran wajib diisi' : null,
              ),
              const SizedBox(height: 24),

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
    );
  }
}
