import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as ex;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import '../../../core/widgets/app_splash_loader.dart';
import '../../../core/utils/file_saver.dart';
import '../widgets/student_form_dialog.dart';

class AdminAlumniListView extends StatefulWidget {
  final String schoolId;
  final bool isDesktop;

  const AdminAlumniListView({
    super.key,
    required this.schoolId,
    required this.isDesktop,
  });

  @override
  State<AdminAlumniListView> createState() => _AdminAlumniListViewState();
}

class _AdminAlumniListViewState extends State<AdminAlumniListView> {
  final AdminUserService _adminUserService = AdminUserService();
  final TextEditingController _alumniSearchController = TextEditingController();
  final ValueNotifier<String> _alumniSearchNotifier = ValueNotifier<String>('');
  final ScrollController _alumniTableHorizontalScrollController = ScrollController();

  Stream<List<Student>>? _studentsStream;
  Stream<List<Map<String, dynamic>>>? _classesStream;
  List<Student>? _cachedStudents;
  List<Map<String, dynamic>>? _cachedClasses;

  int _alumniRowsPerPage = 10;
  int _alumniCurrentPage = 0;
  String _alumniSortColumn = 'nama';
  bool _alumniSortAscending = true;
  String? _selectedAlumniClassFilter;
  String? _selectedAlumniGenderFilter;
  String? _selectedAlumniReligionFilter;
  String? _selectedAlumniAngkatanFilter;

  @override
  void initState() {
    super.initState();
    _studentsStream = _adminUserService.streamStudents(widget.schoolId);
    _classesStream = _adminUserService.streamClasses(widget.schoolId);
    _alumniSearchController.addListener(() {
      _alumniSearchNotifier.value = _alumniSearchController.text;
    });
  }

  @override
  void dispose() {
    _alumniSearchController.dispose();
    _alumniSearchNotifier.dispose();
    _alumniTableHorizontalScrollController.dispose();
    super.dispose();
  }

  void _initStreams(String schoolId) {
    _studentsStream ??= _adminUserService.streamStudents(schoolId);
    _classesStream ??= _adminUserService.streamClasses(schoolId);
  }

  Future<void> _exportAlumniExcel(List<Student> alumni) async {
    try {
      final excel = ex.Excel.createExcel();
      final sheet = excel[excel.getDefaultSheet()!];

      sheet.appendRow([
        ex.TextCellValue('NISN'),
        ex.TextCellValue('NIS'),
        ex.TextCellValue('Nama Alumni'),
        ex.TextCellValue('Jenis Kelamin'),
        ex.TextCellValue('Agama'),
        ex.TextCellValue('Angkatan'),
        ex.TextCellValue('Status'),
      ]);

      for (var s in alumni) {
        sheet.appendRow([
          ex.TextCellValue(s.nis ?? '-'),
          ex.TextCellValue(s.nis),
          ex.TextCellValue(s.displayName),
          ex.TextCellValue(s.gender == 'L' ? 'Laki-laki' : 'Perempuan'),
          ex.TextCellValue(s.religion),
          ex.TextCellValue(s.angkatan),
          ex.TextCellValue(s.status == 'alumni' ? 'Alumni' : s.status),
        ]);
      }

      final fileBytes = excel.save();
      if (fileBytes != null) {
        final fileName = 'Daftar_Alumni_${DateTime.now().millisecondsSinceEpoch}.xlsx';
        await saveAndDownloadFile(
          Uint8List.fromList(fileBytes),
          fileName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Berhasil mengunduh $fileName'), backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor data alumni: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _resetPassword(String schoolId, String collectionType, String docId, String displayName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Reset password untuk $displayName?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reset')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      final tempPassword = await _adminUserService.generateTempPassword(
        schoolId: schoolId,
        collectionType: collectionType,
        docId: docId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password baru untuk $displayName: $tempPassword'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal reset password: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restoreAlumniStudent(String schoolId, Student s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Kembalikan ke Murid Aktif', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
        content: Text('Apakah Anda yakin ingin membatalkan status kelulusan murid "${s.displayName}" (NIS: ${s.nis}) dan mengembalikannya ke daftar murid aktif?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Batal', style: GoogleFonts.inter(color: const Color(0xFF64748B))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Ya, Kembalikan', style: GoogleFonts.inter(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.restoreGraduatedStudent(schoolId: schoolId, studentId: s.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Murid "${s.displayName}" berhasil dikembalikan ke status Aktif.'),
            backgroundColor: const Color(0xFF10B981),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengembalikan murid: $e'),
            backgroundColor: const Color(0xFFEF4444),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteUser(String schoolId, String collectionType, String docId, String name, String identifier) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Pengguna'),
        content: Text('Apakah Anda yakin ingin menghapus akun $name ($identifier) secara permanen dari sistem? Tindakan ini tidak dapat dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _adminUserService.permanentDeleteUser(
        schoolId: schoolId,
        collectionType: collectionType,
        docId: docId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Berhasil menghapus $name'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _buildPaginationControls({
    required int currentPage,
    required int rowsPerPage,
    required int totalItems,
    required ValueChanged<int> onPageChanged,
    required ValueChanged<int> onRowsPerPageChanged,
  }) {
    final totalPages = (totalItems / rowsPerPage).ceil();
    final start = currentPage * rowsPerPage;
    final end = (start + rowsPerPage < totalItems) ? start + rowsPerPage : totalItems;
    final size = MediaQuery.of(context).size;
    final isMobile = size.width < 600;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (!isMobile) ...[
            Text(
              'Baris per halaman:',
              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
            ),
            const SizedBox(width: 8),
          ],
          DropdownButton<int>(
            value: rowsPerPage,
            items: [10, 20, 50].map((val) {
              return DropdownMenuItem<int>(
                value: val,
                child: Text('$val', style: GoogleFonts.inter(fontSize: 12)),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                onRowsPerPageChanged(val);
              }
            },
            underline: const SizedBox(),
          ),
          SizedBox(width: isMobile ? 12 : 24),
          Text(
            totalItems == 0 ? '0-0 dari 0' : '${start + 1}-$end dari $totalItems',
            style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
          ),
          SizedBox(width: isMobile ? 8 : 16),
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 20),
            onPressed: currentPage > 0 ? () => onPageChanged(currentPage - 1) : null,
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 20),
            onPressed: currentPage < totalPages - 1 ? () => onPageChanged(currentPage + 1) : null,
          ),
        ],
      ),
    );
  }

  DataColumn _buildAlumniSortableHeader(String title, String colKey, double width) {
    final isSorted = _alumniSortColumn == colKey;
    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            setState(() {
              if (_alumniSortColumn == colKey) {
                _alumniSortAscending = !_alumniSortAscending;
              } else {
                _alumniSortColumn = colKey;
                _alumniSortAscending = true;
              }
              _alumniCurrentPage = 0;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  isSorted
                      ? (_alumniSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
                      : Icons.unfold_more_rounded,
                  size: isSorted ? 20 : 16,
                  color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  DataColumn _buildAlumniFilterAndSortHeader({
    required String title,
    required String colKey,
    required String? currentFilter,
    required List<String> options,
    required ValueChanged<String?> onSelected,
    required double width,
  }) {
    final isSorted = _alumniSortColumn == colKey;
    final hasFilter = currentFilter != null && currentFilter != options.first;

    return DataColumn(
      label: ConstrainedBox(
        constraints: BoxConstraints(minWidth: width),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () {
                setState(() {
                  if (_alumniSortColumn == colKey) {
                    _alumniSortAscending = !_alumniSortAscending;
                  } else {
                    _alumniSortColumn = colKey;
                    _alumniSortAscending = true;
                  }
                  _alumniCurrentPage = 0;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 2.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      isSorted
                          ? (_alumniSortAscending ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded)
                          : Icons.unfold_more_rounded,
                      size: isSorted ? 20 : 16,
                      color: isSorted ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                    ),
                  ],
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Filter $title',
              icon: Icon(
                Icons.filter_alt_rounded,
                size: 16,
                color: hasFilter ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
              ),
              onSelected: (val) {
                onSelected(val == options.first ? null : val);
              },
              itemBuilder: (context) => options.map((opt) {
                final isSelected = (opt == options.first && currentFilter == null) || (opt == currentFilter);
                return PopupMenuItem<String>(
                  value: opt,
                  child: Row(
                    children: [
                      Icon(
                        isSelected ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 16,
                        color: isSelected ? const Color(0xFF4F46E5) : const Color(0xFF94A3B8),
                      ),
                      const SizedBox(width: 8),
                      Text(opt, style: GoogleFonts.inter(fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildAlumniTab(widget.schoolId, widget.isDesktop);
  }

  Widget _buildAlumniTab(String schoolId, bool isDesktop) {
    _initStreams(schoolId);

    return StreamBuilder<List<Map<String, dynamic>>>(
      initialData: _cachedClasses,
      stream: _classesStream ?? _adminUserService.streamClasses(schoolId),
      builder: (context, classesSnapshot) {
        if (classesSnapshot.hasData) {
          _cachedClasses = classesSnapshot.data;
        }
        final classes = classesSnapshot.data ?? [];
        final Map<String, String> studentClassMap = {};
        for (var c in classes) {
          final className = c['name'] as String? ?? '-';
          final studentIds = c['studentIds'];
          if (studentIds is List) {
            for (var id in studentIds) {
              studentClassMap[id.toString()] = className;
            }
          }
        }

        return StreamBuilder<List<Student>>(
          initialData: _cachedStudents,
          stream: _studentsStream ?? _adminUserService.streamStudents(schoolId),
          builder: (context, snapshot) {
            if (snapshot.hasData) {
              _cachedStudents = snapshot.data;
            }
            if (snapshot.hasError && !snapshot.hasData) return Center(child: Text('Error: ${snapshot.error}'));
            if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
              return const AppContentLoader(
                title: 'Memuat Data Alumni...',
                subtitle: 'Mengambil daftar murid alumni dari database',
              );
            }

            final rawStudents = snapshot.data ?? [];
            final allAlumni = rawStudents.where((s) => s.isGraduated).toList();

            return Padding(
              padding: EdgeInsets.all(isDesktop ? 24.0 : 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header & Buttons
                  if (isDesktop) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daftar Alumni',
                              style: GoogleFonts.inter(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF0F172A),
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Kelola database murid yang telah dinyatakan lulus',
                              style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportAlumniExcel(allAlumni),
                              tooltip: 'Ekspor Alumni ke Excel',
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.school_rounded, size: 16, color: Color(0xFF4F46E5)),
                              label: Text(
                                'Ke Manajemen Murid',
                                style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: const Color(0xFF4F46E5)),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFC7D2FE)),
                                backgroundColor: const Color(0xFFEEF2FF),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ] else ...[
                    // Mobile layout header
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Daftar Alumni',
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF0F172A),
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Database murid yang telah lulus',
                          style: GoogleFonts.inter(fontSize: 12, color: const Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.download_rounded, color: Color(0xFF06B6D4)),
                              onPressed: () => _exportAlumniExcel(allAlumni),
                              tooltip: 'Ekspor ke Excel',
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Search Bar
                  Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _alumniSearchController,
                      style: GoogleFonts.inter(fontSize: 14, color: const Color(0xFF0F172A)),
                      decoration: InputDecoration(
                        hintText: 'Cari alumni berdasarkan nama atau NIS...',
                        hintStyle: GoogleFonts.inter(
                          color: const Color(0xFF94A3B8),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF4F46E5), size: 20),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onChanged: (val) {
                        _alumniSearchNotifier.value = val;
                        _alumniCurrentPage = 0;
                      },
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Content List
                  Expanded(
                    child: ValueListenableBuilder<String>(
                      valueListenable: _alumniSearchNotifier,
                      builder: (context, query, _) {
                        final filteredAlumni = allAlumni.where((s) {
                          final q = query.trim().toLowerCase();
                          final matchesQuery = q.isEmpty ||
                              s.displayName.toLowerCase().contains(q) ||
                              s.nis.toLowerCase().contains(q);
                          if (!matchesQuery) return false;

                          if (_selectedAlumniClassFilter != null && _selectedAlumniClassFilter != 'Semua Kelas') {
                            final sClass = studentClassMap[s.id] ?? '-';
                            if (sClass != _selectedAlumniClassFilter) return false;
                          }

                          if (_selectedAlumniGenderFilter != null && _selectedAlumniGenderFilter != 'Semua Gender') {
                            final genderStr = s.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                            if (genderStr != _selectedAlumniGenderFilter) return false;
                          }

                          if (_selectedAlumniReligionFilter != null && _selectedAlumniReligionFilter != 'Semua Agama') {
                            if (s.religion.trim().toLowerCase() != _selectedAlumniReligionFilter!.trim().toLowerCase()) return false;
                          }

                          if (_selectedAlumniAngkatanFilter != null && _selectedAlumniAngkatanFilter != 'Semua Angkatan') {
                            if (s.angkatan.trim() != _selectedAlumniAngkatanFilter!.trim()) return false;
                          }

                          return true;
                        }).toList();

                        // Sorting
                        filteredAlumni.sort((a, b) {
                          int cmp = 0;
                          switch (_alumniSortColumn) {
                            case 'nama':
                              cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                              break;
                            case 'nis':
                              final nA = int.tryParse(a.nis);
                              final nB = int.tryParse(b.nis);
                              if (nA != null && nB != null) {
                                cmp = nA.compareTo(nB);
                              } else {
                                cmp = a.nis.compareTo(b.nis);
                              }
                              break;
                            case 'kelas':
                              final cA = studentClassMap[a.id] ?? '';
                              final cB = studentClassMap[b.id] ?? '';
                              cmp = cA.compareTo(cB);
                              break;
                            case 'gender':
                              final gA = a.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                              final gB = b.gender == 'M' ? 'Laki-laki' : 'Perempuan';
                              cmp = gA.compareTo(gB);
                              break;
                            case 'agama':
                              cmp = a.religion.toLowerCase().compareTo(b.religion.toLowerCase());
                              break;
                            case 'angkatan':
                              cmp = a.angkatan.compareTo(b.angkatan);
                              break;
                            case 'kata_sandi':
                              cmp = (a.tempPassword ?? '').compareTo(b.tempPassword ?? '');
                              break;
                            default:
                              cmp = a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
                          }
                          return _alumniSortAscending ? cmp : -cmp;
                        });

                        final totalItems = filteredAlumni.length;
                        final totalPages = (totalItems / _alumniRowsPerPage).ceil();
                        final currentPage = (_alumniCurrentPage >= totalPages && totalPages > 0)
                            ? totalPages - 1
                            : _alumniCurrentPage;
                        final pageStart = currentPage * _alumniRowsPerPage;
                        final pageEnd = (pageStart + _alumniRowsPerPage < totalItems)
                            ? pageStart + _alumniRowsPerPage
                            : totalItems;
                        final paginatedAlumni = (pageStart < totalItems)
                            ? filteredAlumni.sublist(pageStart, pageEnd)
                            : <Student>[];

                        final hasActiveFilters = _selectedAlumniClassFilter != null ||
                            _selectedAlumniGenderFilter != null ||
                            _selectedAlumniReligionFilter != null ||
                            _selectedAlumniAngkatanFilter != null;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (hasActiveFilters)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    if (_selectedAlumniClassFilter != null)
                                      Chip(
                                        label: Text('Kelas: $_selectedAlumniClassFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniClassFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniGenderFilter != null)
                                      Chip(
                                        label: Text('Gender: $_selectedAlumniGenderFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniGenderFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniReligionFilter != null)
                                      Chip(
                                        label: Text('Agama: $_selectedAlumniReligionFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniReligionFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    if (_selectedAlumniAngkatanFilter != null)
                                      Chip(
                                        label: Text('Angkatan: $_selectedAlumniAngkatanFilter', style: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF4F46E5))),
                                        backgroundColor: const Color(0xFFEEF2FF),
                                        side: const BorderSide(color: Color(0xFFC7D2FE)),
                                        deleteIcon: const Icon(Icons.close_rounded, size: 14, color: Color(0xFF4F46E5)),
                                        onDeleted: () => setState(() { _selectedAlumniAngkatanFilter = null; _alumniCurrentPage = 0; }),
                                      ),
                                    TextButton(
                                      onPressed: () => setState(() {
                                        _selectedAlumniClassFilter = null;
                                        _selectedAlumniGenderFilter = null;
                                        _selectedAlumniReligionFilter = null;
                                        _selectedAlumniAngkatanFilter = null;
                                        _alumniCurrentPage = 0;
                                      }),
                                      child: Text('Reset Filter', style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFFEF4444))),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: filteredAlumni.isEmpty
                                  ? const Center(child: Text('Tidak ada data alumni.'))
                                  : _buildAlumniTable(schoolId, paginatedAlumni, studentClassMap, allAlumni),
                            ),
                            if (filteredAlumni.isNotEmpty)
                              _buildPaginationControls(
                                currentPage: currentPage,
                                rowsPerPage: _alumniRowsPerPage,
                                totalItems: totalItems,
                                onPageChanged: (page) => setState(() => _alumniCurrentPage = page),
                                onRowsPerPageChanged: (rows) => setState(() {
                                  _alumniRowsPerPage = rows;
                                  _alumniCurrentPage = 0;
                                }),
                              ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildAlumniTable(
    String schoolId,
    List<Student> alumni,
    Map<String, String> studentClassMap,
    List<Student> allAlumni,
  ) {
    final classSet = studentClassMap.values.where((c) => c.isNotEmpty && c != '-').toSet().toList()..sort();
    final classOptions = ['Semua Kelas', ...classSet];

    final genderOptions = ['Semua Gender', 'Laki-laki', 'Perempuan'];

    final existingReligions = allAlumni
        .map((s) => s.religion.trim())
        .where((r) => r.isNotEmpty && r != '-')
        .toSet()
        .toList()
      ..sort();
    final religionOptions = ['Semua Agama', ...existingReligions];

    final existingAngkatan = allAlumni
        .map((s) => s.angkatan.trim())
        .where((a) => a.isNotEmpty && a != '-')
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final angkatanOptions = ['Semua Angkatan', ...existingAngkatan];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      elevation: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            controller: _alumniTableHorizontalScrollController,
            thumbVisibility: true,
            trackVisibility: true,
            thickness: 8,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: _alumniTableHorizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                    columnSpacing: 14,
                    columns: [
                      _buildAlumniSortableHeader('Nama', 'nama', 200),
                      _buildAlumniSortableHeader('NIS', 'nis', 80),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Kelas',
                        colKey: 'kelas',
                        currentFilter: _selectedAlumniClassFilter,
                        options: classOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniClassFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Gender',
                        colKey: 'gender',
                        currentFilter: _selectedAlumniGenderFilter,
                        options: genderOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniGenderFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Agama',
                        colKey: 'agama',
                        currentFilter: _selectedAlumniReligionFilter,
                        options: religionOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniReligionFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 110,
                      ),
                      _buildAlumniFilterAndSortHeader(
                        title: 'Angkatan',
                        colKey: 'angkatan',
                        currentFilter: _selectedAlumniAngkatanFilter,
                        options: angkatanOptions,
                        onSelected: (val) => setState(() {
                          _selectedAlumniAngkatanFilter = val;
                          _alumniCurrentPage = 0;
                        }),
                        width: 125,
                      ),
                      _buildAlumniSortableHeader('Kata Sandi', 'kata_sandi', 110),
                      const DataColumn(
                        label: SizedBox(
                          width: 100,
                          child: Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                      const DataColumn(
                        label: SizedBox(
                          width: 180,
                          child: Text('Aksi', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                    rows: alumni.map((s) {
                      return DataRow(cells: [
                        DataCell(SizedBox(
                          width: 180,
                          child: Text(
                            s.displayName,
                            style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 80,
                          child: Text(
                            s.nis,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            studentClassMap[s.id] ?? '-',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            s.gender == 'M' ? 'Laki-laki' : 'Perempuan',
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: Text(
                            s.religion,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 125,
                          child: Text(
                            s.angkatan,
                            style: GoogleFonts.inter(fontSize: 13, color: const Color(0xFF334155)),
                            softWrap: true,
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 110,
                          child: s.tempPassword != null && s.tempPassword!.isNotEmpty
                              ? SelectableText(
                                  s.tempPassword!,
                                  style: GoogleFonts.firaCode(fontWeight: FontWeight.w800, fontSize: 15, color: const Color(0xFF0F172A), letterSpacing: 1.2),
                                )
                              : const Text('-', style: TextStyle(color: Color(0xFF94A3B8))),
                        )),
                        DataCell(SizedBox(
                          width: 100,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Alumni',
                              style: TextStyle(
                                color: Color(0xFF7C3AED),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        )),
                        DataCell(SizedBox(
                          width: 180,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.vpn_key_outlined, color: Color(0xFFF59E0B), size: 18),
                                tooltip: s.uid == null ? 'Buat Akun Login' : 'Reset Kata Sandi',
                                onPressed: () => _resetPassword(schoolId, 'students', s.id, s.displayName),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.restore_rounded, color: Color(0xFF10B981), size: 20),
                                tooltip: 'Batalkan Kelulusan (Kembalikan ke Murid Aktif)',
                                onPressed: () => _restoreAlumniStudent(schoolId, s),
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                tooltip: 'Hapus Permanen',
                                onPressed: () => _deleteUser(schoolId, 'students', s.id, s.displayName, s.nis),
                              ),
                            ],
                          ),
                        )),
                      ]);
                    }).toList(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

}
