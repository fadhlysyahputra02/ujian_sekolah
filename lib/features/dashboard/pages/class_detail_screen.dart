import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/student.dart';
import '../../../core/services/admin_user_service.dart';
import '../widgets/class_form_dialog.dart';

class ClassDetailScreen extends StatefulWidget {
  final String schoolId;
  final Map<String, dynamic> classData;

  const ClassDetailScreen({
    super.key,
    required this.schoolId,
    required this.classData,
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

  String get _classId => widget.classData['id'] as String;
  String get _className => widget.classData['name'] as String? ?? '-';

  List<String> _enrolledIds(Map<String, dynamic> classDoc) {
    final raw = classDoc['studentIds'];
    if (raw is List) return raw.cast<String>();
    return [];
  }

  // ── Actions ──
  Future<void> _editClass() async {
    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => ClassFormDialog(
        schoolId: widget.schoolId,
        existingClass: {...widget.classData, 'id': _classId},
      ),
    );
    if (updated == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kelas berhasil diperbarui!')),
      );
      Navigator.of(context).pop(true); // refresh parent
    }
  }

  Future<void> _deleteClass() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Kelas'),
        content: Text('Yakin ingin menghapus kelas "$_className"? Semua data keanggotaan akan hilang.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteClass(schoolId: widget.schoolId, classId: _classId);
      if (mounted) Navigator.of(context).pop(true);
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
        title: const Text('Keluarkan Murid'),
        content: Text('Keluarkan "$name" dari kelas ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Keluarkan'),
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
                  constraints: const BoxConstraints(maxWidth: 480, maxHeight: 580),
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
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: _dark),
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
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                            prefixIcon: const Icon(Icons.search_rounded),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _border)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                          ),
                          onChanged: (v) => setInner(() => localSearch = v),
                        ),
                        const SizedBox(height: 12),
                        Expanded(
                          child: filtered.isEmpty
                              ? const Center(child: Text('Tidak ada murid ditemukan.', style: TextStyle(color: _slate)))
                              : ListView.separated(
                                  itemCount: filtered.length,
                                  separatorBuilder: (_, __) => const Divider(height: 1, color: _border),
                                  itemBuilder: (_, i) {
                                    final s = filtered[i];
                                    final isSelected = selectedIds.contains(s.id);
                                    return ListTile(
                                      dense: true,
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
                                        backgroundColor: (isSelected ? const Color(0xFF10B981) : const Color(0xFF4F46E5)).withValues(alpha: 0.1),
                                        child: Icon(
                                          isSelected ? Icons.check_rounded : Icons.person_rounded,
                                          color: isSelected ? const Color(0xFF10B981) : _indigo,
                                          size: 16,
                                        ),
                                      ),
                                      title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: _dark)),
                                      subtitle: Text('NIS: ${s.nis}', style: const TextStyle(fontSize: 12, color: _slate)),
                                      trailing: Checkbox(
                                        value: isSelected,
                                        activeColor: const Color(0xFF10B981),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                                        onChanged: isSaving ? null : (val) {
                                          setInner(() {
                                            if (val == true) {
                                              selectedIds.add(s.id);
                                            } else {
                                              selectedIds.remove(s.id);
                                            }
                                          });
                                        },
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
                            const SizedBox(width: 8),
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
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
        if (!classSnap.hasData || !classSnap.data!.exists) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final classDoc = classSnap.data!.data() as Map<String, dynamic>;
        final enrolledIds = _enrolledIds(classDoc);
        final currentName = classDoc['name'] as String? ?? _className;

        return Scaffold(
          backgroundColor: const Color(0xFFF8FAFC),
          appBar: AppBar(
            backgroundColor: const Color(0xFF0F172A),
            foregroundColor: Colors.white,
            elevation: 0,
            title: Text(currentName, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white)),
            actions: [
              IconButton(
                icon: const Icon(Icons.edit_rounded),
                tooltip: 'Edit Kelas',
                onPressed: _editClass,
              ),
              IconButton(
                icon: const Icon(Icons.delete_rounded, color: Color(0xFFF87171)),
                tooltip: 'Hapus Kelas',
                onPressed: _deleteClass,
              ),
            ],
          ),
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

              return Column(
                children: [
                  // ── Stats Banner ──
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                    color: const Color(0xFF0F172A),
                    child: _statChip(Icons.people_rounded, '${enrolledStudents.length}', 'Murid Terdaftar'),
                  ),
                  // ── Search + Add ──
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (v) => setState(() => _searchQuery = v),
                            decoration: InputDecoration(
                              hintText: 'Cari murid di kelas ini...',
                              prefixIcon: const Icon(Icons.search_rounded),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                  borderSide: const BorderSide(color: _border)),
                              contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showAddStudentDialog(enrolledIds, allStudents),
                          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                          label: const Text('Tambah Murid'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _indigo,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Student List ──
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 56, color: Colors.grey[300]),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isEmpty
                                      ? 'Belum ada murid di kelas ini.\nTekan "Tambah Murid" untuk mulai.'
                                      : 'Murid tidak ditemukan.',
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: _slate, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, color: _border),
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              return Container(
                                color: Colors.white,
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                  leading: CircleAvatar(
                                    backgroundColor: const Color(0xFF4F46E5).withValues(alpha: 0.1),
                                    child: Text(
                                      s.displayName.isNotEmpty ? s.displayName[0].toUpperCase() : '?',
                                      style: const TextStyle(color: _indigo, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  title: Text(s.displayName, style: const TextStyle(fontWeight: FontWeight.w600, color: _dark)),
                                  subtitle: Text(
                                    'NIS: ${s.nis}  •  ${s.gender == 'M' ? 'Laki-laki' : 'Perempuan'}',
                                    style: const TextStyle(fontSize: 12, color: _slate),
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.remove_circle_outline_rounded, color: Color(0xFFEF4444)),
                                    tooltip: 'Keluarkan dari kelas',
                                    onPressed: () => _removeStudent(s.id, s.displayName),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _statChip(IconData icon, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF818CF8), size: 18),
            const SizedBox(width: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
      ],
    );
  }
}
