import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/services/school_service.dart';
import 'add_school_page.dart';

class SchoolListPage extends StatefulWidget {
  const SchoolListPage({super.key});

  @override
  State<SchoolListPage> createState() => _SchoolListPageState();
}

class _SchoolListPageState extends State<SchoolListPage> {
  final SchoolService _schoolService = SchoolService();

  Future<void> _toggleSchoolStatus(String schoolId, bool currentDisabled) async {
    try {
      // Toggle the value
      await _schoolService.toggleSchoolStatus(
        schoolId: schoolId,
        disabled: !currentDisabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              !currentDisabled
                  ? 'Sekolah dinonaktifkan sementara'
                  : 'Sekolah berhasil diaktifkan kembali',
            ),
            backgroundColor: !currentDisabled ? const Color(0xFFEF4444) : const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal mengubah status sekolah: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  void _openAddSchoolDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AddSchoolDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Manajemen Sekolah',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1E293B),
        elevation: 0,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ElevatedButton.icon(
              onPressed: _openAddSchoolDialog,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Daftar Sekolah'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          )
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _schoolService.getSchoolsStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Terjadi kesalahan: ${snapshot.error}',
                style: const TextStyle(color: Color(0xFFEF4444)),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                color: Color(0xFF4F46E5),
              ),
            );
          }

          final schools = snapshot.data?.docs ?? [];

          if (schools.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.domain_disabled_rounded,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Belum ada sekolah terdaftar',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _openAddSchoolDialog,
                    child: const Text('Daftarkan Sekolah Pertama'),
                  )
                ],
              ),
            );
          }

          return Container(
            padding: const EdgeInsets.all(24),
            child: isDesktop ? _buildTableView(schools) : _buildListView(schools),
          );
        },
      ),
    );
  }

  Widget _buildTableView(List<QueryDocumentSnapshot<Map<String, dynamic>>> schools) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: const Color(0xFFF1F5F9),
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
          headingTextStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Color(0xFF475569),
          ),
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('Kode')),
            DataColumn(label: Text('Nama Sekolah')),
            DataColumn(label: Text('Admin Email')),
            DataColumn(label: Text('Guru')),
            DataColumn(label: Text('Murid')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Kontrol')),
          ],
          rows: schools.map((doc) {
            final data = doc.data();
            final meta = data['meta'] as Map<String, dynamic>? ?? {};
            final teacherCount = meta['teacherCount'] ?? 0;
            final studentCount = meta['studentCount'] ?? 0;
            final disabled = data['disabled'] == true;

            return DataRow(
              cells: [
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      data['code'] ?? '-',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Color(0xFF475569),
                      ),
                    ),
                  ),
                ),
                DataCell(Text(
                  data['name'] ?? '-',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                )),
                DataCell(Text(data['adminEmail'] ?? '-')),
                DataCell(Text('$teacherCount orang')),
                DataCell(Text('$studentCount orang')),
                DataCell(
                  _buildStatusBadge(disabled),
                ),
                DataCell(
                  Switch.adaptive(
                    value: !disabled,
                    activeTrackColor: const Color(0xFF10B981),
                    onChanged: (val) => _toggleSchoolStatus(doc.id, disabled),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildListView(List<QueryDocumentSnapshot<Map<String, dynamic>>> schools) {
    return ListView.builder(
      itemCount: schools.length,
      itemBuilder: (context, index) {
        final doc = schools[index];
        final data = doc.data();
        final meta = data['meta'] as Map<String, dynamic>? ?? {};
        final teacherCount = meta['teacherCount'] ?? 0;
        final studentCount = meta['studentCount'] ?? 0;
        final disabled = data['disabled'] == true;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        data['name'] ?? '-',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    _buildStatusBadge(disabled),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.tag, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      data['code'] ?? '-',
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    ),
                    const SizedBox(width: 16),
                    const Icon(Icons.email, size: 14, color: Colors.grey),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        data['adminEmail'] ?? '-',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.people, size: 16, color: Color(0xFF4F46E5)),
                        const SizedBox(width: 6),
                        Text(
                          'Guru: $teacherCount | Murid: $studentCount',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text(
                          'Aktif',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 4),
                        Switch.adaptive(
                          value: !disabled,
                          activeTrackColor: const Color(0xFF10B981),
                          onChanged: (val) => _toggleSchoolStatus(doc.id, disabled),
                        ),
                      ],
                    )
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(bool disabled) {
    final isActive = !disabled;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Aktif' : 'Nonaktif',
        style: TextStyle(
          color: isActive ? const Color(0xFF065F46) : const Color(0xFF991B1B),
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
