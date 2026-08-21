import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/utils/file_saver.dart';

class ImportStudentsDialog extends StatefulWidget {
  final String schoolId;

  const ImportStudentsDialog({
    super.key,
    required this.schoolId,
  });

  @override
  State<ImportStudentsDialog> createState() => _ImportStudentsDialogState();
}

class _ImportStudentsDialogState extends State<ImportStudentsDialog> {
  PlatformFile? _selectedFile;
  List<Map<String, dynamic>> _parsedRows = [];
  bool _createAuth = false;
  bool _isLoading = false;
  double _progressValue = 0.0;
  String? _parseError;

  // Import results stage
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
        ex.TextCellValue('nis'),
        ex.TextCellValue('angkatan'),
        ex.TextCellValue('email'),
      ]);
      sheet.appendRow([
        ex.TextCellValue('Budi Santoso'),
        ex.TextCellValue('M'),
        ex.TextCellValue('12345'),
        ex.TextCellValue('2024'),
        ex.TextCellValue('budi@student.sekolah.sch.id'),
      ]);
      final bytes = excel.save(fileName: 'Template_Impor_Murid.xlsx');
      if (bytes != null) {
        if (!kIsWeb) {
          await saveAndDownloadFile(bytes, 'Template_Impor_Murid.xlsx');
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
    setState(() {
      _parseError = null;
      _parsedRows.clear();
      _selectedFile = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        setState(() {
          _selectedFile = file;
        });
        _parseFile(file);
      }
    } catch (e) {
      setState(() {
        _parseError = 'Gagal memilih file: $e';
      });
    }
  }

  void _parseFile(PlatformFile file) {
    try {
      final bytes = file.bytes;
      if (bytes == null) {
        throw 'Isi file kosong atau tidak dapat dibaca.';
      }

      final fileName = file.name.toLowerCase();
      List<List<dynamic>> rawGrid = [];

      if (fileName.endsWith('.csv')) {
        final csvString = utf8.decode(bytes);
        rawGrid = const CsvToListConverter().convert(csvString);
      } else if (fileName.endsWith('.xlsx')) {
        final excel = ex.Excel.decodeBytes(bytes);
        if (excel.tables.isNotEmpty) {
          final table = excel.tables.values.first;
          for (var row in table.rows) {
            rawGrid.add(row.map((cell) => cell?.value).toList());
          }
        }
      } else {
        throw 'Format file tidak didukung. Gunakan .csv atau .xlsx';
      }

      if (rawGrid.isEmpty) {
        throw 'File tidak memiliki baris data.';
      }

      final headers = rawGrid.first.map((e) => e?.toString().trim().toLowerCase() ?? '').toList();
      
      final int nameIdx = headers.indexOf('name');
      final int genderIdx = headers.indexOf('gender');
      final int nisIdx = headers.indexOf('nis');
      final int angkatanIdx = headers.indexOf('angkatan');
      final int emailIdx = headers.indexOf('email');

      if (nameIdx == -1 || genderIdx == -1 || nisIdx == -1 || angkatanIdx == -1) {
        throw 'Header file tidak valid. Kolom wajib: name, gender, nis, angkatan, dan email (opsional).';
      }

      final List<Map<String, dynamic>> rows = [];
      final Set<String> fileNisSet = {};

      for (int i = 1; i < rawGrid.length; i++) {
        final row = rawGrid[i];
        if (row.isEmpty || row.every((element) => element == null || element.toString().trim().isEmpty)) {
          continue;
        }

        final name = _getCellValue(row, nameIdx);
        final gender = _getCellValue(row, genderIdx).toUpperCase();
        final nis = _getCellValue(row, nisIdx);
        final angkatan = _getCellValue(row, angkatanIdx);
        final email = emailIdx != -1 && emailIdx < row.length ? _getCellValue(row, emailIdx) : '';

        final List<String> errors = [];
        if (name.isEmpty) errors.add('Nama kosong.');
        if (gender != 'M' && gender != 'F') errors.add('Gender harus M atau F.');
        if (nis.isEmpty) errors.add('NIS kosong.');
        if (angkatan.isEmpty) errors.add('Angkatan kosong.');
        
        if (nis.isNotEmpty) {
          if (fileNisSet.contains(nis)) {
            errors.add('NIS duplikat dalam file.');
          }
          fileNisSet.add(nis);
        }

        rows.add({
          'name': name,
          'gender': gender,
          'nis': nis,
          'angkatan': angkatan,
          'email': email,
          'errors': errors,
          'isValid': errors.isEmpty,
        });
      }

      setState(() {
        _parsedRows = rows;
      });
    } catch (e) {
      setState(() {
        _parseError = e.toString();
        _selectedFile = null;
      });
    }
  }

  String _getCellValue(List<dynamic> row, int index) {
    if (index >= row.length) return '';
    final val = row[index];
    if (val == null) return '';
    return val.toString().trim();
  }

  Future<void> _submitImport() async {
    final validRows = _parsedRows.where((r) => r['isValid'] == true).toList();
    if (validRows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tidak ada data valid untuk diimpor.'),
          backgroundColor: Color(0xFFEF4444),
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _progressValue = 0.0;
    });

    try {
      final cleanRows = validRows.map((r) => {
        'name': r['name'],
        'gender': r['gender'],
        'nis': r['nis'],
        'angkatan': r['angkatan'],
        'email': r['email'].toString().isEmpty ? null : r['email'],
      }).toList();

      final List<Map<String, dynamic>> results = [];
      final batchSize = 10;
      final totalRows = cleanRows.length;

      for (int i = 0; i < totalRows; i += batchSize) {
        final end = (i + batchSize < totalRows) ? i + batchSize : totalRows;
        final batch = cleanRows.sublist(i, end);
        final response = await _adminUserService.importStudentsBulk(
          schoolId: widget.schoolId,
          rows: batch,
          createAuth: _createAuth,
        );

        for (int j = 0; j < response.length; j++) {
          final res = response[j];
          final sourceRow = validRows[i + (res['rowIndex'] as int)];
          results.add({
            'name': sourceRow['name'],
            'nis': sourceRow['nis'],
            'email': sourceRow['email'],
            'success': res['success'] ?? false,
            'errors': List<String>.from(res['errors'] ?? []),
            'tempPassword': res['tempPassword'] as String?,
          });
        }

        if (mounted) {
          setState(() {
            _progressValue = end / totalRows;
          });
        }
      }

      if (!mounted) return;

      setState(() {
        _importResults = results;
        _showResults = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal melakukan impor: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _exportGeneratedCredentials() async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([
        ex.TextCellValue('Nama Murid'),
        ex.TextCellValue('NIS'),
        ex.TextCellValue('Email'),
        ex.TextCellValue('Status Impor'),
        ex.TextCellValue('Password Sementara (Satu kali tayang)'),
        ex.TextCellValue('Keterangan Error'),
      ]);

      for (var row in _importResults) {
        sheet.appendRow([
          ex.TextCellValue(row['name'] ?? ''),
          ex.TextCellValue(row['nis'] ?? ''),
          ex.TextCellValue(row['email'] ?? ''),
          ex.TextCellValue(row['success'] == true ? 'Sukses' : 'Gagal'),
          ex.TextCellValue(row['tempPassword'] ?? '-'),
          ex.TextCellValue(row['errors'].join(', ')),
        ]);
      }

      final fileBytes = excel.save(fileName: 'SesiCermat_Impor_Murid_Hasil.xlsx');
      if (fileBytes != null) {
        if (!kIsWeb) {
          await saveAndDownloadFile(fileBytes, 'SesiCermat_Impor_Murid_Hasil.xlsx');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Hasil impor berhasil diekspor ke Excel!')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor hasil: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: _isLoading ? 420 : 700,
        height: _isLoading ? 320 : (size.height * 0.82),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), color: Colors.white),
        child: _isLoading
            ? _buildLoadingView()
            : _showResults
                ? _buildResultsView()
                : _stage == 0
                    ? _buildGuideView()
                    : _buildParserView(),
      ),
    );
  }

  Widget _buildLoadingView() {
    final pct = (_progressValue * 100).toInt();
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFEEF2FF),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.cloud_upload_rounded, size: 48, color: Color(0xFF4F46E5)),
            ),
            const SizedBox(height: 20),
            Text(
              'Mengimpor Data...',
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Harap jangan menutup jendela ini atau me-refresh halaman.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Mengimpor...',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF64748B),
                        ),
                      ),
                      Text(
                        '$pct%',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF4F46E5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: _progressValue,
                      backgroundColor: const Color(0xFFF1F5F9),
                      color: const Color(0xFF4F46E5),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogHeader({
    required String title,
    required String subtitle,
    required Color color1,
    required Color color2,
    bool showClose = true,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 16, 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color1, color2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
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
      _CI('name', 'Nama Lengkap', 'Budi Santoso', true, Icons.person_rounded, const Color(0xFF4F46E5), 'Nama lengkap murid sesuai dokumen resmi.'),
      _CI('gender', 'Jenis Kelamin', 'M atau F', true, Icons.wc_rounded, const Color(0xFFEC4899), 'Isi M (Laki-laki) atau F (Perempuan).'),
      _CI('nis', 'NIS', '12345', true, Icons.badge_rounded, const Color(0xFF0D9488), 'Nomor Induk Siswa. Harus unik.'),
      _CI('angkatan', 'Angkatan', '2024', true, Icons.calendar_today_rounded, const Color(0xFFD97706), 'Angkatan / Tahun masuk murid.'),
      _CI('email', 'Email', 'budi@student.sekolah.sch.id', false, Icons.email_rounded, const Color(0xFF0284C7), 'Alamat email murid (opsional). Dipakai untuk login.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDialogHeader(
          title: 'Panduan Impor Murid Massal',
          subtitle: 'Format kolom wajib dalam file Excel / CSV',
          color1: const Color(0xFF06B6D4),
          color2: const Color(0xFF0891B2),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            children: [
              Text(
                'Kolom yang diperlukan',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF94A3B8),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              ...columns.map((c) => _buildColCard(c)),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lightbulb_rounded, color: Color(0xFFD97706), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Baris pertama harus berisi nama kolom (header): name, gender, nis, angkatan, email.',
                        style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF92400E)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _downloadTemplate,
                icon: const Icon(Icons.download_rounded, size: 18),
                label: Text('Unduh Template', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0D9488),
                  side: const BorderSide(color: Color(0xFF0D9488)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
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
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildColCard(_CI c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.color.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: c.color.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(c.icon, color: c.color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      c.label,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: (c.required ? const Color(0xFFEF4444) : const Color(0xFF64748B)).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        c.required ? 'Wajib' : 'Opsional',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: c.required ? const Color(0xFFEF4444) : const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  c.desc,
                  style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text('Kolom: ', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        c.key,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: c.color,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text('Contoh: ', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF94A3B8))),
                    Text(
                      c.example,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParserView() {
    final validCount = _parsedRows.where((r) => r['isValid'] == true).length;
    final invalidCount = _parsedRows.length - validCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDialogHeader(
          title: 'Pilih & Pratinjau File',
          subtitle: 'Pilih file Excel (.xlsx) atau CSV (.csv) untuk diimpor',
          color1: const Color(0xFF06B6D4),
          color2: const Color(0xFF0891B2),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  onPressed: _isLoading ? null : _pickFile,
                  icon: const Icon(Icons.cloud_upload_outlined, size: 20),
                  label: Text(
                    _selectedFile == null ? 'Pilih Berkas Excel/CSV' : 'Ganti Berkas: ${_selectedFile!.name}',
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide(color: const Color(0xFFCBD5E1), width: _selectedFile == null ? 1 : 1.5),
                    backgroundColor: _selectedFile == null ? Colors.white : const Color(0xFFECFDF5),
                    foregroundColor: _selectedFile == null ? const Color(0xFF4F46E5) : const Color(0xFF059669),
                  ),
                ),
                if (_parseError != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFFEE2E2))),
                    child: Row(children: [
                      const Icon(Icons.error_rounded, color: Color(0xFFEF4444), size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_parseError!, style: GoogleFonts.inter(color: const Color(0xFFB91C1C), fontSize: 12, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                ],
                if (_parsedRows.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _buildStatChip('Total: ${_parsedRows.length}', const Color(0xFF4F46E5)),
                      const SizedBox(width: 8),
                      _buildStatChip('Valid: $validCount', const Color(0xFF10B981)),
                      const SizedBox(width: 8),
                      _buildStatChip('Tidak valid: $invalidCount', const Color(0xFFEF4444)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.builder(
                        itemCount: _parsedRows.length,
                        itemBuilder: (context, idx) {
                          final row = _parsedRows[idx];
                          final bool isValid = row['isValid'] == true;
                          return Container(
                            color: idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: Row(
                              children: [
                                Icon(
                                  isValid ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                                  color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(row['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                      Text('NIS: ${row['nis']} | Gender: ${row['gender']} | Angkatan: ${row['angkatan']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text(
                                    isValid ? 'Siap diimpor' : (row['errors'] as List).join(', '),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isValid ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE2E8F0)), borderRadius: BorderRadius.circular(10), color: Colors.white),
                    child: CheckboxListTile(
                      title: Text('Buat akun login untuk seluruh murid valid', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('Kata sandi sementara akan dihasilkan & dapat diekspor di akhir.', style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF64748B))),
                      value: _createAuth,
                      onChanged: _isLoading ? null : (val) => setState(() => _createAuth = val ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      activeColor: const Color(0xFF06B6D4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(
                onPressed: () => setState(() => _stage = 0),
                child: Text('Kembali', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: _isLoading || _parsedRows.isEmpty || validCount == 0 ? null : _submitImport,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF06B6D4),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: _isLoading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Impor Data Valid', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResultsView() {
    final successCount = _importResults.where((r) => r['success'] == true).length;
    final failedCount = _importResults.length - successCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildDialogHeader(
          title: 'Impor Selesai',
          subtitle: '$successCount murid sukses · $failedCount gagal',
          color1: const Color(0xFF10B981),
          color2: const Color(0xFF059669),
          showClose: false,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_createAuth) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'PENTING: Unduh/Ekspor hasil sekarang untuk mendapatkan daftar password sementara. Data password ini tidak akan bisa diakses lagi setelah Anda menutup dialog ini!',
                            style: GoogleFonts.inter(color: const Color(0xFF92400E), fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ListView.builder(
                      itemCount: _importResults.length,
                      itemBuilder: (context, idx) {
                        final row = _importResults[idx];
                        final bool success = row['success'] == true;
                        return Container(
                          color: idx % 2 == 0 ? Colors.white : const Color(0xFFF8FAFC),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          child: Row(
                            children: [
                              Icon(
                                success ? Icons.check_circle_outline_rounded : Icons.error_outline_rounded,
                                color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(row['name'] ?? '', style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text('NIS: ${row['nis']}', style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B))),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  success
                                      ? (_createAuth ? 'Pass: ${row['tempPassword'] ?? '-'}' : 'Sukses')
                                      : (row['errors'] as List).join(', '),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: success ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_createAuth)
                ElevatedButton.icon(
                  onPressed: _exportGeneratedCredentials,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: Text('Ekspor Password ke Excel', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD97706),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                )
              else
                const SizedBox(),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Selesai'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CI {
  final String key;
  final String label;
  final String example;
  final bool required;
  final IconData icon;
  final Color color;
  final String desc;
  _CI(this.key, this.label, this.example, this.required, this.icon, this.color, this.desc);
}
