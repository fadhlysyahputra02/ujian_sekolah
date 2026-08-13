import 'dart:convert';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as ex;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
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
  String? _parseError;

  // Import results stage
  bool _showResults = false;
  List<Map<String, dynamic>> _importResults = [];

  final AdminUserService _adminUserService = AdminUserService();

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
        // Parse CSV
        final csvString = utf8.decode(bytes);
        rawGrid = const CsvToListConverter().convert(csvString);
      } else if (fileName.endsWith('.xlsx')) {
        // Parse Excel
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

      // Read Header Row to find columns: name, gender, nis, angkatan, email
      final headers = rawGrid.first.map((e) => e?.toString().trim().toLowerCase() ?? '').toList();
      
      final int nameIdx = headers.indexOf('name');
      final int genderIdx = headers.indexOf('gender');
      final int nisIdx = headers.indexOf('nis');
      final int angkatanIdx = headers.indexOf('angkatan');
      final int emailIdx = headers.indexOf('email');

      if (nameIdx == -1 || genderIdx == -1 || nisIdx == -1 || angkatanIdx == -1) {
        throw 'Header file tidak valid. Pastikan terdapat kolom: name, gender, nis, angkatan, dan email (opsional).';
      }

      final List<Map<String, dynamic>> rows = [];
      final Set<String> fileNisSet = {};

      for (int i = 1; i < rawGrid.length; i++) {
        final row = rawGrid[i];
        if (row.isEmpty || row.every((element) => element == null || element.toString().trim().isEmpty)) {
          continue; // Skip empty rows
        }

        final name = _getCellValue(row, nameIdx);
        final gender = _getCellValue(row, genderIdx).toUpperCase();
        final nis = _getCellValue(row, nisIdx);
        final angkatan = _getCellValue(row, angkatanIdx);
        final email = emailIdx != -1 && emailIdx < row.length ? _getCellValue(row, emailIdx) : '';

        // Real-time client-side validation
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
    // Handle SharedString or specific types in excel library
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
    });

    try {
      final cleanRows = validRows.map((r) => {
        'name': r['name'],
        'gender': r['gender'],
        'nis': r['nis'],
        'angkatan': r['angkatan'],
        'email': r['email'].toString().isEmpty ? null : r['email'],
      }).toList();

      final response = await _adminUserService.importStudentsBulk(
        schoolId: widget.schoolId,
        rows: cleanRows,
        createAuth: _createAuth,
      );

      if (!mounted) return;

      // Map results back to view
      final List<Map<String, dynamic>> results = [];
      for (int i = 0; i < response.length; i++) {
        final res = response[i];
        final sourceRow = validRows[res['rowIndex'] as int];
        results.add({
          'name': sourceRow['name'],
          'nis': sourceRow['nis'],
          'email': sourceRow['email'],
          'success': res['success'] ?? false,
          'errors': List<String>.from(res['errors'] ?? []),
          'tempPassword': res['tempPassword'] as String?,
        });
      }

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
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _exportGeneratedCredentials() async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      // Add Headers
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

      final fileBytes = excel.save();
      if (fileBytes != null) {
        await saveAndDownloadFile(fileBytes, 'SesiCermat_Impor_Murid_Hasil.xlsx');
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
    final validCount = _parsedRows.where((r) => r['isValid'] == true).length;
    final invalidCount = _parsedRows.length - validCount;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 700,
        height: size.height * 0.8,
        padding: const EdgeInsets.all(28.0),
        child: _showResults ? _buildResultsView() : _buildParserView(validCount, invalidCount),
      ),
    );
  }

  Widget _buildParserView(int validCount, int invalidCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Impor Murid Massal (Excel/CSV)',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
            ),
          ],
        ),
        const Divider(),
        const SizedBox(height: 12),
        const Text(
          'Format header kolom wajib: name, gender, nis, angkatan, email (opsional). Gender wajib diisi M (Laki-laki) atau F (Perempuan).',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
        ),
        const SizedBox(height: 16),

        // File Selector Button
        OutlinedButton.icon(
          onPressed: _isLoading ? null : _pickFile,
          icon: const Icon(Icons.file_upload_outlined),
          label: Text(_selectedFile == null ? 'Pilih Berkas Excel/CSV' : 'Ganti Berkas: ${_selectedFile!.name}'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),

        if (_parseError != null) ...[
          const SizedBox(height: 12),
          Text(
            _parseError!,
            style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],

        if (_parsedRows.isNotEmpty) ...[
          const SizedBox(height: 16),
          // Statistics Summary
          Row(
            children: [
              _buildStatChip('Total: ${_parsedRows.length}', const Color(0xFF4F46E5)),
              const SizedBox(width: 8),
              _buildStatChip('Valid: $validCount', const Color(0xFF10B981)),
              const SizedBox(width: 8),
              _buildStatChip('Gagal Validasi: $invalidCount', const Color(0xFFEF4444)),
            ],
          ),
          const SizedBox(height: 12),
          // Preview table
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
                              Text(
                                row['name'] ?? '',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text('NIS: ${row['nis']} | Angkatan: ${row['angkatan']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
          CheckboxListTile(
            title: const Text('Buat akun Auth untuk seluruh murid valid'),
            subtitle: const Text('Kata sandi sementara akan dihasilkan & dapat diekspor di akhir.'),
            value: _createAuth,
            onChanged: _isLoading ? null : (val) => setState(() => _createAuth = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ] else
          const Spacer(),

        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Batal'),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isLoading || _parsedRows.isEmpty || validCount == 0 ? null : _submitImport,
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
                  : const Text('Impor Data Valid'),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildResultsView() {
    final successCount = _importResults.where((r) => r['success'] == true).length;
    final failedCount = _importResults.length - successCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 28),
            SizedBox(width: 12),
            Text(
              'Impor Selesai Diproses',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const Divider(),
        const SizedBox(height: 12),
        Text(
          'Hasil pemrosesan: $successCount siswa sukses diimpor, $failedCount siswa gagal.',
          style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 16),
        if (_createAuth) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFBBF24)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'PENTING: Unduh/Ekspor hasil sekarang untuk mendapatkan daftar password sementara siswa. Data password ini tidak akan bisa diakses lagi setelah Anda menutup dialog ini!',
                    style: TextStyle(color: Color(0xFFB45309), fontSize: 12, fontWeight: FontWeight.bold),
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
                            Text(
                              row['name'] ?? '',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            Text('NIS: ${row['nis']}', style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            if (_createAuth)
              ElevatedButton.icon(
                onPressed: _exportGeneratedCredentials,
                icon: const Icon(Icons.download_rounded),
                label: const Text('Ekspor Password Ke Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Selesai'),
            ),
          ],
        )
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
