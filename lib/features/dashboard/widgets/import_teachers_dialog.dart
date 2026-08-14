import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/utils/file_saver.dart';

class ImportTeachersDialog extends StatefulWidget {
  final String schoolId;

  const ImportTeachersDialog({
    super.key,
    required this.schoolId,
  });

  @override
  State<ImportTeachersDialog> createState() => _ImportTeachersDialogState();
}

class _ImportTeachersDialogState extends State<ImportTeachersDialog> {
  PlatformFile? _selectedFile;
  List<Map<String, dynamic>> _parsedRows = [];
  bool _createAuth = false;
  bool _isLoading = false;
  String? _parseError;

  bool _showResults = false;
  List<Map<String, dynamic>> _importResults = [];

  // 0 = guide, 1 = import
  int _stage = 0;

  final AdminUserService _adminUserService = AdminUserService();

  Future<void> _downloadTemplate() async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      sheet.appendRow([
        ex.TextCellValue('name'),
        ex.TextCellValue('gender'),
        ex.TextCellValue('nip'),
        ex.TextCellValue('email'),
      ]);
      sheet.appendRow([
        ex.TextCellValue('Budi Santoso'),
        ex.TextCellValue('M'),
        ex.TextCellValue('198801012015011001'),
        ex.TextCellValue('budi@example.com'),
      ]);
      final bytes = excel.save(fileName: 'Template_Impor_Guru.xlsx');
      if (bytes != null) {
        if (!kIsWeb) {
          await saveAndDownloadFile(bytes, 'Template_Impor_Guru.xlsx');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Template berhasil diunduh!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengunduh template: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _pickFile() async {
    setState(() { _parseError = null; _parsedRows.clear(); _selectedFile = null; });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['csv', 'xlsx'], withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() => _selectedFile = file);
        _parseFile(file);
      }
    } catch (e) {
      setState(() => _parseError = 'Gagal memilih file: $e');
    }
  }

  void _parseFile(PlatformFile file) {
    try {
      final bytes = file.bytes;
      if (bytes == null) throw 'Isi file kosong atau tidak dapat dibaca.';
      final fileName = file.name.toLowerCase();
      List<List<dynamic>> rawGrid = [];
      if (fileName.endsWith('.csv')) {
        rawGrid = const CsvToListConverter().convert(utf8.decode(bytes));
      } else if (fileName.endsWith('.xlsx')) {
        final excel = ex.Excel.decodeBytes(bytes);
        if (excel.tables.isNotEmpty) {
          for (var row in excel.tables.values.first.rows) {
            rawGrid.add(row.map((cell) => cell?.value).toList());
          }
        }
      } else {
        throw 'Format file tidak didukung. Gunakan .csv atau .xlsx';
      }
      if (rawGrid.isEmpty) throw 'File tidak memiliki baris data.';
      final headers = rawGrid.first.map((e) => e?.toString().trim().toLowerCase() ?? '').toList();
      final int nameIdx = headers.indexOf('name');
      final int genderIdx = headers.indexOf('gender');
      final int nipIdx = headers.indexOf('nip');
      final int emailIdx = headers.indexOf('email');
      if (nameIdx == -1 || genderIdx == -1 || nipIdx == -1) {
        throw 'Header file tidak valid. Kolom wajib: name, gender, nip, dan email (opsional).';
      }
      final List<Map<String, dynamic>> rows = [];
      final Set<String> fileNipSet = {};
      for (int i = 1; i < rawGrid.length; i++) {
        final row = rawGrid[i];
        if (row.isEmpty || row.every((e) => e == null || e.toString().trim().isEmpty)) continue;
        final name = _cellVal(row, nameIdx);
        final gender = _cellVal(row, genderIdx).toUpperCase();
        final nip = _cellVal(row, nipIdx);
        final email = emailIdx != -1 && emailIdx < row.length ? _cellVal(row, emailIdx) : '';
        final List<String> errors = [];
        if (name.isEmpty) errors.add('Nama kosong.');
        if (gender != 'M' && gender != 'F') errors.add('Gender harus M atau F.');
        if (nip.isEmpty) errors.add('NIP kosong.');
        if (nip.isNotEmpty) {
          if (fileNipSet.contains(nip)) errors.add('NIP duplikat dalam file.');
          fileNipSet.add(nip);
        }
        rows.add({'name': name, 'gender': gender, 'nip': nip, 'email': email, 'errors': errors, 'isValid': errors.isEmpty});
      }
      setState(() => _parsedRows = rows);
    } catch (e) {
      setState(() { _parseError = e.toString(); _selectedFile = null; });
    }
  }

  String _cellVal(List<dynamic> row, int idx) {
    if (idx >= row.length) return '';
    return row[idx]?.toString().trim() ?? '';
  }

  Future<void> _submitImport() async {
    final validRows = _parsedRows.where((r) => r['isValid'] == true).toList();
    if (validRows.isEmpty) return;
    setState(() => _isLoading = true);
    try {
      final cleanRows = validRows.map((r) => {
        'name': r['name'], 'gender': r['gender'], 'nip': r['nip'],
        'email': r['email'].toString().isEmpty ? null : r['email'],
      }).toList();
      final response = await _adminUserService.importTeachersBulk(
        schoolId: widget.schoolId, rows: cleanRows, createAuth: _createAuth,
      );
      if (!mounted) return;
      final List<Map<String, dynamic>> results = [];
      for (int i = 0; i < response.length; i++) {
        final res = response[i];
        final sourceRow = validRows[res['rowIndex'] as int];
        results.add({
          'name': sourceRow['name'], 'nip': sourceRow['nip'], 'email': sourceRow['email'],
          'success': res['success'] ?? false, 'errors': List<String>.from(res['errors'] ?? []),
          'tempPassword': res['tempPassword'] as String?,
        });
      }
      setState(() { _importResults = results; _showResults = true; });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal melakukan impor: $e'), backgroundColor: const Color(0xFFEF4444)),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportResults() async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];
      sheet.appendRow([
        ex.TextCellValue('Nama Guru'), ex.TextCellValue('NIP'), ex.TextCellValue('Email'),
        ex.TextCellValue('Status'), ex.TextCellValue('Password Sementara'), ex.TextCellValue('Error'),
      ]);
      for (var row in _importResults) {
        sheet.appendRow([
          ex.TextCellValue(row['name'] ?? ''), ex.TextCellValue(row['nip'] ?? ''),
          ex.TextCellValue(row['email'] ?? ''), ex.TextCellValue(row['success'] == true ? 'Sukses' : 'Gagal'),
          ex.TextCellValue(row['tempPassword'] ?? '-'), ex.TextCellValue((row['errors'] as List).join(', ')),
        ]);
      }
      final bytes = excel.save(fileName: 'SesiCermat_Impor_Guru_Hasil.xlsx');
      if (bytes != null && !kIsWeb) {
        await saveAndDownloadFile(bytes, 'SesiCermat_Impor_Guru_Hasil.xlsx');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal ekspor: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700, height: size.height * 0.82,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20)),
        child: _showResults ? _buildResultsView() : _stage == 0 ? _buildGuideView() : _buildParserView(),
      ),
    );
  }

  Widget _buildDialogHeader({required String title, required String subtitle, required Color color1, required Color color2, bool showClose = true}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
      decoration: BoxDecoration(gradient: LinearGradient(colors: [color1, color2], begin: Alignment.topLeft, end: Alignment.bottomRight)),
      child: Row(
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800, color: Colors.white)),
              const SizedBox(height: 2),
              Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
            ]),
          ),
          if (showClose)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
        ],
      ),
    );
  }

  Widget _buildGuideView() {
    final columns = [
      _CI('name', 'Nama Lengkap', 'Budi Santoso', true, Icons.person_rounded, const Color(0xFF4F46E5), 'Nama lengkap guru sesuai dokumen resmi.'),
      _CI('gender', 'Jenis Kelamin', 'M atau F', true, Icons.wc_rounded, const Color(0xFFEC4899), 'Isi M (Laki-laki) atau F (Perempuan).'),
      _CI('nip', 'NIP', '198801012015011001', true, Icons.badge_rounded, const Color(0xFF0D9488), 'Nomor Induk Pegawai. Harus unik.'),
      _CI('email', 'Email', 'budi@sekolah.sch.id', false, Icons.email_rounded, const Color(0xFF0284C7), 'Alamat email guru (opsional). Dipakai untuk akun login.'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildDialogHeader(
        title: 'Panduan Impor Guru Massal',
        subtitle: 'Format kolom wajib dalam file Excel / CSV',
        color1: const Color(0xFF4F46E5), color2: const Color(0xFF6366F1),
      ),
      Expanded(
        child: ListView(padding: const EdgeInsets.fromLTRB(24, 20, 24, 0), children: [
          Text('Kolom yang diperlukan', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF94A3B8), letterSpacing: 0.5)),
          const SizedBox(height: 12),
          ...columns.map((c) => _buildColCard(c)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFFDE68A))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.lightbulb_rounded, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(
                'Baris pertama harus berisi nama kolom (header): name, gender, nip, email.\nKolom mata pelajaran tidak perlu dicantumkan — dapat diatur setelah impor melalui fitur Edit Guru.',
                style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)),
              )),
            ]),
          ),
          const SizedBox(height: 20),
        ]),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
        child: Row(children: [
          OutlinedButton.icon(
            onPressed: _downloadTemplate,
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text('Unduh Template', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFF0D9488), side: const BorderSide(color: Color(0xFF0D9488)), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: () => setState(() => _stage = 1),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: Text('Pilih File & Impor', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildColCard(_CI c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.color.withValues(alpha: 0.15)),
        boxShadow: [BoxShadow(color: c.color.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: c.color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)), child: Icon(c.icon, color: c.color, size: 18)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(c.label, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 13, color: const Color(0xFF0F172A))),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: (c.required ? const Color(0xFFEF4444) : const Color(0xFF64748B)).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(c.required ? 'Wajib' : 'Opsional', style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w700, color: c.required ? const Color(0xFFEF4444) : const Color(0xFF64748B))),
            ),
          ]),
          const SizedBox(height: 2),
          Text(c.desc, style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
          const SizedBox(height: 4),
          Row(children: [
            Text('Kolom: ', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: c.color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(4)),
              child: Text(c.key, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.color, fontFamily: 'monospace'))),
            const SizedBox(width: 10),
            Text('Contoh: ', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
            Text(c.example, style: GoogleFonts.inter(fontSize: 11, fontStyle: FontStyle.italic, color: const Color(0xFF475569))),
          ]),
        ])),
      ]),
    );
  }

  Widget _buildParserView() {
    final validCount = _parsedRows.where((r) => r['isValid'] == true).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildDialogHeader(
        title: 'Pilih & Pratinjau File',
        subtitle: 'Pilih file Excel (.xlsx) atau CSV (.csv) untuk diimpor',
        color1: const Color(0xFF4F46E5), color2: const Color(0xFF6366F1),
      ),
      Expanded(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _pickFile,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(_selectedFile == null ? 'Pilih Berkas Excel / CSV' : 'Ganti Berkas: ${_selectedFile!.name}', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        ),
        if (_parseError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFFEE2E2), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFCA5A5))),
            child: Row(children: [
              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(_parseError!, style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 13, fontWeight: FontWeight.w500))),
            ]),
          ),
        ],
        if (_parsedRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            _buildStatChip('Total: ${_parsedRows.length}', const Color(0xFF4F46E5)),
            const SizedBox(width: 8),
            _buildStatChip('Valid: $validCount', const Color(0xFF10B981)),
            const SizedBox(width: 8),
            _buildStatChip('Tidak valid: ${_parsedRows.length - validCount}', const Color(0xFFEF4444)),
          ]),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                itemCount: _parsedRows.length,
                itemBuilder: (context, idx) {
                  final row = _parsedRows[idx];
                  final bool isValid = row['isValid'] == true;
                  return Container(
                    color: idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(children: [
                      Icon(isValid ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 20),
                      const SizedBox(width: 12),
                      Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(row['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                        Text('NIP: ${row['nip']} | Gender: ${row['gender']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                      ])),
                      Expanded(flex: 2, child: Text(isValid ? 'Siap diimpor' : (row['errors'] as List).join(', '),
                        style: TextStyle(fontSize: 12, color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.w500))),
                    ]),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: Text('Buat akun login untuk seluruh guru valid', style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('Kata sandi sementara akan dihasilkan & dapat diekspor di akhir.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
            value: _createAuth,
            onChanged: _isLoading ? null : (val) => setState(() => _createAuth = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            activeColor: const Color(0xFF4F46E5),
          ),
        ] else const Spacer(),
      ]))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            onPressed: _isLoading ? null : () => setState(() { _stage = 0; _parsedRows.clear(); _selectedFile = null; _parseError = null; }),
            child: Text('Kembali', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isLoading || _parsedRows.isEmpty || _parsedRows.where((r) => r['isValid'] == true).isEmpty ? null : _submitImport,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text('Impor Data Valid', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildResultsView() {
    final successCount = _importResults.where((r) => r['success'] == true).length;
    final failedCount = _importResults.length - successCount;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildDialogHeader(
        title: 'Impor Selesai', subtitle: '$successCount guru sukses · $failedCount gagal',
        color1: const Color(0xFF10B981), color2: const Color(0xFF059669), showClose: false,
      ),
      Expanded(child: Padding(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (_createAuth) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: const Color(0xFFF59E0B).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFFBBF24))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text('PENTING: Unduh hasil sekarang! Password sementara tidak dapat diakses lagi setelah dialog ini ditutup.', style: GoogleFonts.inter(color: const Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.bold))),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        Expanded(
          child: Container(
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              itemCount: _importResults.length,
              itemBuilder: (context, idx) {
                final row = _importResults[idx];
                final bool success = row['success'] == true;
                return Container(
                  color: idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(children: [
                    Icon(success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded, color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 20),
                    const SizedBox(width: 12),
                    Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(row['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                      Text('NIP: ${row['nip']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                    ])),
                    Expanded(flex: 2, child: Text(
                      success ? (_createAuth ? 'Pass: ${row['tempPassword'] ?? '-'}' : 'Sukses') : (row['errors'] as List).join(', '),
                      style: TextStyle(fontSize: 12, color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444), fontWeight: FontWeight.bold),
                    )),
                  ]),
                );
              },
            ),
          ),
        ),
      ]))),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          if (_createAuth)
            ElevatedButton.icon(
              onPressed: _exportResults,
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text('Ekspor Password ke Excel', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFD97706), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            )
          else const SizedBox(),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4F46E5), foregroundColor: Colors.white, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
            child: Text('Selesai', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _CI {
  final String key, label, example, desc;
  final bool required;
  final IconData icon;
  final Color color;
  const _CI(this.key, this.label, this.example, this.required, this.icon, this.color, this.desc);
}
