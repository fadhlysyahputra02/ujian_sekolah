import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppReleaseManagerDialog extends StatefulWidget {
  const AppReleaseManagerDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (context) => const AppReleaseManagerDialog(),
    );
  }

  @override
  State<AppReleaseManagerDialog> createState() =>
      _AppReleaseManagerDialogState();
}

class _AppReleaseManagerDialogState extends State<AppReleaseManagerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _versionController = TextEditingController();
  final _buildNumberController = TextEditingController();
  final _apkUrlController = TextEditingController();
  final _releaseNotesController = TextEditingController();
  bool _forceUpdate = false;
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('system_config')
          .doc('app_version')
          .get();

      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        _versionController.text = data['latest_version']?.toString() ?? '1.1.38';
        _buildNumberController.text =
            (data['latest_build_number'] ?? 1).toString();
        _apkUrlController.text = data['apk_url']?.toString() ?? '';
        _releaseNotesController.text = data['release_notes']?.toString() ?? '';
        _forceUpdate = data['force_update'] ?? false;
      } else {
        _versionController.text = '1.1.38';
        _buildNumberController.text = '1';
        _apkUrlController.text = '';
        _releaseNotesController.text =
            '- Perbaikan bug & peningkatan kestabilan sistem ujian.';
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memuat konfigurasi update: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final buildNum = int.tryParse(_buildNumberController.text.trim()) ?? 1;

      await FirebaseFirestore.instance
          .collection('system_config')
          .doc('app_version')
          .set({
        'latest_version': _versionController.text.trim(),
        'latest_build_number': buildNum,
        'apk_url': _apkUrlController.text.trim(),
        'release_notes': _releaseNotesController.text.trim(),
        'force_update': _forceUpdate,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Rilis v${_versionController.text.trim()} berhasil diterbitkan! Pengguna akan menerima notifikasi update.',
                    style: GoogleFonts.inter(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF059669),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan rilis: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _versionController.dispose();
    _buildNumberController.dispose();
    _apkUrlController.dispose();
    _releaseNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E1B4B).withValues(alpha: 0.2),
                blurRadius: 36,
                offset: const Offset(0, 16),
              ),
            ],
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Gradient
              Container(
                padding: const EdgeInsets.fromLTRB(22, 20, 16, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1E1B4B), Color(0xFF3730A3)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2)),
                      ),
                      child: const Icon(
                        Icons.cloud_upload_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Kelola Rilis & Update APK',
                            style: GoogleFonts.inter(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Terbitkan update aplikasi untuk seluruh pengguna',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: const Color(0xFFC7D2FE),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 20),
                    ),
                  ],
                ),
              ),

              // Form Content
              Flexible(
                child: _isLoading
                    ? const SizedBox(
                        height: 200,
                        child: Center(
                          child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  Color(0xFF4F46E5))),
                        ),
                      )
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(22),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextFormField(
                                      controller: _versionController,
                                      style: GoogleFonts.inter(fontSize: 13.5),
                                      decoration: InputDecoration(
                                        labelText: 'Versi Terbaru',
                                        hintText: '1.1.38',
                                        prefixIcon: const Icon(
                                            Icons.tag_rounded,
                                            size: 18),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 12),
                                      ),
                                      validator: (val) =>
                                          val == null || val.isEmpty
                                              ? 'Wajib diisi'
                                              : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _buildNumberController,
                                      keyboardType: TextInputType.number,
                                      style: GoogleFonts.inter(fontSize: 13.5),
                                      decoration: InputDecoration(
                                        labelText: 'Build Number',
                                        hintText: '2',
                                        prefixIcon: const Icon(
                                            Icons.numbers_rounded,
                                            size: 18),
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12, vertical: 12),
                                      ),
                                      validator: (val) {
                                        if (val == null || val.isEmpty) {
                                          return 'Wajib diisi';
                                        }
                                        if (int.tryParse(val) == null) {
                                          return 'Harus angka';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _apkUrlController,
                                style: GoogleFonts.inter(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'URL File APK (Direct Download)',
                                  hintText:
                                      'https://domain.com/downloads/app-v1.1.38.apk',
                                  prefixIcon: const Icon(
                                      Icons.link_rounded,
                                      size: 18),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 12),
                                ),
                                validator: (val) =>
                                    val == null || val.isEmpty
                                        ? 'Wajib diisi'
                                        : null,
                              ),
                              const SizedBox(height: 14),
                              TextFormField(
                                controller: _releaseNotesController,
                                maxLines: 4,
                                style: GoogleFonts.inter(fontSize: 13),
                                decoration: InputDecoration(
                                  labelText: 'Catatan Rilis (Changelog)',
                                  hintText:
                                      '- Perbaikan bug pada modul ujian...\n- Tampilan UI baru yang lebih responsif...',
                                  alignLabelWithHint: true,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.all(12),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                      color: const Color(0xFFE2E8F0)),
                                ),
                                child: SwitchListTile(
                                  value: _forceUpdate,
                                  onChanged: (val) =>
                                      setState(() => _forceUpdate = val),
                                  title: Text(
                                    'Paksa Update (Force Update)',
                                    style: GoogleFonts.inter(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF0F172A),
                                    ),
                                  ),
                                  subtitle: Text(
                                    'Pengguna tidak dapat menutup modal jika diaktifkan.',
                                    style: GoogleFonts.inter(
                                      fontSize: 11.5,
                                      color: const Color(0xFF64748B),
                                    ),
                                  ),
                                  contentPadding: EdgeInsets.zero,
                                  activeTrackColor: const Color(0xFF4F46E5),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),

              // Bottom Actions
              Container(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 18),
                decoration: const BoxDecoration(
                  color: Color(0xFFF8FAFC),
                  border: Border(
                    top: BorderSide(color: Color(0xFFE2E8F0)),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed:
                          _isSaving ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      child: Text(
                        'Batal',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed:
                          _isSaving || _isLoading ? null : _saveConfig,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4F46E5),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Row(
                              children: [
                                const Icon(Icons.send_rounded,
                                    size: 16, color: Colors.white),
                                const SizedBox(width: 8),
                                Text(
                                  'Terbitkan Rilis',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

