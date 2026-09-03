import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import '../widgets/class_form_dialog.dart';

class ClassDetailScreen extends StatefulWidget {
  final String schoolId;
  final String classId;
  final Map<String, dynamic>? initialData;

  const ClassDetailScreen({
    super.key,
    required this.schoolId,
    required this.classId,
    this.initialData,
  });

  @override
  State<ClassDetailScreen> createState() => _ClassDetailScreenState();
}

class _ClassDetailScreenState extends State<ClassDetailScreen> {
  final AdminUserService _service = AdminUserService();
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Helpers ──
  static const Color _dark = Color(0xFF0F172A);
  static const Color _indigo = Color(0xFF4F46E5);
  static const Color _slate = Color(0xFF64748B);
  static const Color _border = Color(0xFFE2E8F0);
  static const Color _background = Color(0xFFF8FAFC);

  String get _classId => widget.classId;

  List<String> _enrolledIds(Map<String, dynamic> classDoc) {
    final raw = classDoc['studentIds'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  // ── Actions ──
  Future<void> _editClass(Map<String, dynamic> classData) async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => ClassFormDialog(
        schoolId: widget.schoolId,
        existingClass: {...classData, 'id': _classId},
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kelas berhasil diperbarui!')),
      );
    }
  }

  Future<void> _deleteClass(String className) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Kelas', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Yakin ingin menghapus kelas "$className"? Semua data keanggotaan akan hilang.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteClass(schoolId: widget.schoolId, classId: _classId);
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menghapus: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    }
  }

  Future<void> _removeStudent(String studentId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluarkan Murid', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text('Keluarkan "$name" dari kelas ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Keluarkan', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _service.removeStudentFromClass(
      schoolId: widget.schoolId,
      classId: _classId,
      studentId: studentId,
    );
  }

  Future<void> _showAddStudentDialog(List<String> currentIds, List<Student> allStudents) async {
    final selectedIds = <String>{};
    bool isSaving = false;
    String localSearch = '';

    // Fetch assigned student IDs across all classes of the school
    final Future<Set<String>> assignedIdsFuture = FirebaseFirestore.instance
        .collection('schools')
        .doc(widget.schoolId)
        .collection('classes')
        .get()
        .then((snap) {
      final Set<String> assigned = {};
      for (var doc in snap.docs) {
        final ids = doc.data()['studentIds'];
        if (ids is List) {
          for (var id in ids) {
            assigned.add(id.toString());
          }
        }
      }
      return assigned;
    });

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) {
          return FutureBuilder<Set<String>>(
            future: assignedIdsFuture,
            builder: (context, futureSnapshot) {
              if (futureSnapshot.connectionState == ConnectionState.waiting) {
                return Dialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  backgroundColor: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(color: _indigo),
                        const SizedBox(height: 16),
                        Text(
                          'Memuat data...',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: _dark, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final allAssignedStudentIds = futureSnapshot.data ?? <String>{};
              final available = allStudents.where((s) => !allAssignedStudentIds.contains(s.id)).toList();
              final filtered = available
                  .where((s) => s.displayName.toLowerCase().contains(localSearch.toLowerCase()) ||
                      s.nis.contains(localSearch))
                  .toList();

              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                backgroundColor: Colors.white,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480, maxHeight: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Tambah Murid ke Kelas',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: _dark),
                            ),
                            if (filtered.isNotEmpty)
                              TextButton(
                                onPressed: () {
                                  setInner(() {
                                    final filteredIds = filtered.map((e) => e.id).toList();
                                    final allFilteredSelected = filteredIds.every((id) => selectedIds.contains(id));
                                    if (allFilteredSelected) {
                                      selectedIds.removeAll(filteredIds);
                                    } else {
                                      selectedIds.addAll(filteredIds);
                                    }
                                  });
                                },
                                style: TextButton.styleFrom(
                                  foregroundColor: _indigo,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  backgroundColor: _indigo.withValues(alpha: 0.1),
                                ),
                                child: Text(
                                  filtered.every((id) => selectedIds.contains(id.id))
                                      ? 'Batal Pilih Semua'
                                      : 'Pilih Semua',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          decoration: InputDecoration(
                            hintText: 'Cari nama atau NIS...',
                            prefixIcon: const Icon(Icons.search_rounded, color: _slate),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F9),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          ),
                          onChanged: (v) => setInner(() => localSearch = v),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(child: Text('Tidak ada murid tersedia.', style: TextStyle(color: _slate)))
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (_, i) {
                                    final s = filtered[i];
                                    final isSelected = selectedIds.contains(s.id);
                                    return AnimatedContainer(
                                      duration: const Duration(milliseconds: 200),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.05) : Colors.white,
                                        border: Border.all(
                                          color: isSelected ? const Color(0xFF10B981) : _border,
                                          width: isSelected ? 1.5 : 1,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: ListTile(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                        onTap: isSaving ? null : () {
                                          setInner(() {
                                            if (isSelected) {
                                              selectedIds.remove(s.id);
                                            } else {
                                              selectedIds.add(s.id);
                                            }
                                          });
                                        },
                                        leading: CircleAvatar(
                                          backgroundColor: (isSelected ? const Color(0xFF10B981) : const Color(0xFFF1F5F9)),
                                          child: Icon(
                                            isSelected ? Icons.check_rounded : Icons.person_outline_rounded,
                                            color: isSelected ? Colors.white : _slate,
                                            size: 18,
                                          ),
                                        ),
                                        title: Text(s.displayName, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: isSelected ? const Color(0xFF047857) : _dark)),
                                        subtitle: Text('NIS: ${s.nis}', style: const TextStyle(fontSize: 12, color: _slate)),
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: isSaving ? null : () => Navigator.of(ctx).pop(),
                              child: const Text('Batal'),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              onPressed: (selectedIds.isEmpty || isSaving)
                                  ? null
                                  : () async {
                                      setInner(() => isSaving = true);
                                      try {
                                        await _service.addStudentsToClass(
                                          schoolId: widget.schoolId,
                                          classId: _classId,
                                          studentIds: selectedIds.toList(),
                                        );
                                        if (ctx.mounted) Navigator.of(ctx).pop();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('${selectedIds.length} murid berhasil ditambahkan ke kelas!'),
                                              backgroundColor: const Color(0xFF10B981),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        setInner(() => isSaving = false);
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Gagal menambahkan murid: $e'),
                                              backgroundColor: const Color(0xFFEF4444),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              icon: isSaving
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.add_rounded, size: 18),
                              label: Text(isSaving
                                  ? 'Menyimpan...'
                                  : 'Tambah (${selectedIds.length} Terpilih)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _indigo,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── UI ──
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('classes')
          .doc(_classId)
          .snapshots(),
      builder: (context, classSnap) {
        if (classSnap.hasError) {
          return Scaffold(body: Center(child: Text('Error: ${classSnap.error}')));
        }
        
        // Show initial data if snapshot is loading but we have extraData from routing
        Map<String, dynamic> classDoc = {};
        if (classSnap.hasData && classSnap.data!.exists) {
          classDoc = classSnap.data!.data() as Map<String, dynamic>;
        } else if (widget.initialData != null) {
          classDoc = widget.initialData!;
        } else if (!classSnap.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final enrolledIds = _enrolledIds(classDoc);
        final currentName = classDoc['name'] as String? ?? '-';

        return Scaffold(
          backgroundColor: _background,
          body: StreamBuilder<List<Student>>(
            stream: _service.streamStudents(widget.schoolId),
            builder: (context, studentsSnap) {
              if (studentsSnap.hasError) {
                return Center(child: Text('Error: ${studentsSnap.error}'));
              }
              final allStudents = studentsSnap.data ?? [];
              final enrolledStudents = allStudents.where((s) => enrolledIds.contains(s.id)).toList();

              final filtered = _searchQuery.isEmpty
                  ? enrolledStudents
                  : enrolledStudents
                      .where((s) =>
                          s.displayName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                          s.nis.contains(_searchQuery))
                      .toList();

              return CustomScrollView(
                slivers: [
                  // ── Premium Header ──
                  SliverAppBar(
                    expandedHeight: 180.0,
                    floating: false,
                    pinned: true,
                    backgroundColor: _indigo,
                    elevation: 0,
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                      onPressed: () {
                        if (context.canPop()) {
                          context.pop();
                        } else {
                          context.go('/admin/kelas');
                        }
                      },
                    ),
                    actions: [
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, color: Colors.white),
                        tooltip: 'Edit Kelas',
                        onPressed: () => _editClass(classDoc),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_rounded, color: Color(0xFFFDA4AF)),
                        tooltip: 'Hapus Kelas',
                        onPressed: () => _deleteClass(currentName),
                      ),
                      const SizedBox(width: 8),
                    ],
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF0F172A), Color(0xFF1E1B4B), Color(0xFF312E81)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1E1B4B).withValues(alpha: 0.25),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                        child: Stack(
                          children: [
                            Positioned(
                              right: -20,
                              top: -20,
                              child: Icon(Icons.school_rounded, size: 160, color: Colors.white.withValues(alpha: 0.1)),
                            ),
                            Positioned(
                              left: 24,
                              bottom: 24,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'Detail Kelas',
                                      style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    currentName,
                                    style: GoogleFonts.inter(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      const Icon(Icons.people_alt_rounded, color: Colors.white70, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${enrolledStudents.length} Murid Terdaftar',
                                        style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  
                  // ── Action Bar ──
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 8, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: TextField(
                                controller: _searchController,
                                onChanged: (v) => setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: 'Cari murid di kelas ini...',
                                  hintStyle: const TextStyle(color: _slate, fontSize: 14),
                                  prefixIcon: const Icon(Icons.search_rounded, color: _slate),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            decoration: BoxDecoration(
                              boxShadow: [
                                BoxShadow(
                                  color: _indigo.withValues(alpha: 0.3),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ElevatedButton.icon(
                              onPressed: () => _showAddStudentDialog(enrolledIds, allStudents),
                              icon: const Icon(Icons.person_add_rounded, size: 18),
                              label: const Text('Tambah Murid'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _indigo,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Student List ──
                  if (filtered.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: _indigo.withValues(alpha: 0.05),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.people_outline_rounded, size: 64, color: _indigo.withValues(alpha: 0.4)),
                            ),
                            const SizedBox(height: 24),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Belum ada murid di kelas ini'
                                  : 'Murid tidak ditemukan',
                              style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.bold, color: _dark),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Klik tombol "Tambah Murid" untuk memasukkan murid ke kelas ini.'
                                  : 'Coba kata kunci pencarian yang lain.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: _slate, fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                      sliver: SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, i) {
                            final s = filtered[i];
                            final isMale = s.gender == 'M';
                            
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: _border),
                                boxShadow: [
                                  BoxShadow(color: Colors.black.withValues(alpha: 0.01), blurRadius: 10, offset: const Offset(0, 2)),
                                ],
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 24,
                                      backgroundColor: isMale 
                                        ? const Color(0xFFDBEAFE) // blue-100
                                        : const Color(0xFFFCE7F3), // pink-100
                                      child: Text(
                                        s.displayName.isNotEmpty ? s.displayName[0].toUpperCase() : '?',
                                        style: TextStyle(
                                          color: isMale ? const Color(0xFF1D4ED8) : const Color(0xFFBE185D),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            s.displayName,
                                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 15, color: _dark),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: _slate.withValues(alpha: 0.1),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  'NIS: ${s.nis}',
                                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _slate),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                isMale ? Icons.male_rounded : Icons.female_rounded,
                                                size: 14,
                                                color: _slate,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                isMale ? 'Laki-laki' : 'Perempuan',
                                                style: const TextStyle(fontSize: 12, color: _slate),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(10),
                                        onTap: () => _removeStudent(s.id, s.displayName),
                                        hoverColor: const Color(0xFFFEE2E2),
                                        child: Padding(
                                          padding: const EdgeInsets.all(10),
                                          child: const Icon(Icons.person_remove_rounded, color: Color(0xFFEF4444), size: 22),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                          childCount: filtered.length,
                        ),
                      ),
                    ),
                  
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
