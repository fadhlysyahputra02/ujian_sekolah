import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/models/bug_report.dart';
import '../../../core/services/bug_report_service.dart';
import 'package:intl/intl.dart';

class BugReportTicketsPage extends StatefulWidget {
  const BugReportTicketsPage({super.key});

  @override
  State<BugReportTicketsPage> createState() => _BugReportTicketsPageState();
}

class _BugReportTicketsPageState extends State<BugReportTicketsPage> {
  final BugReportService _bugReportService = BugReportService();
  String _selectedFilter = 'semua';
  late Stream<List<BugReport>> _reportsStream;

  @override
  void initState() {
    super.initState();
    _reportsStream = _bugReportService.streamAllBugReports();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 768;

    return StreamBuilder<List<BugReport>>(
      stream: _reportsStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
        }

        final allReports = snapshot.data ?? [];
        final filteredReports = allReports.where((r) {
          if (_selectedFilter == 'semua') return true;
          return r.status == _selectedFilter;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tiket Laporan',
                style: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFilterChip('semua', 'Semua'),
                  _buildFilterChip('terbuka', 'Terbuka'),
                  _buildFilterChip('diproses', 'Diproses'),
                  _buildFilterChip('selesai', 'Selesai'),
                  _buildFilterChip('ditolak', 'Ditolak'),
                ],
              ),
              const SizedBox(height: 24),
              Expanded(
                child: filteredReports.isEmpty
                    ? const Center(child: Text('Tidak ada laporan.'))
                    : ListView.separated(
                        itemCount: filteredReports.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 16),
                        itemBuilder: (context, index) {
                          return _buildTicketCard(filteredReports[index], isDesktop);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String value, String label) {
    final isSelected = _selectedFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _selectedFilter = value);
      },
    );
  }

  Widget _buildTicketCard(BugReport report, bool isDesktop) {
    Color statusColor = Colors.grey;
    switch (report.status) {
      case 'terbuka': statusColor = Colors.red; break;
      case 'diproses': statusColor = Colors.orange; break;
      case 'selesai': statusColor = Colors.green; break;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        report.schoolName,
                        style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(report.senderEmail, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(report.status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (isDesktop)
            Row(
              children: [
                Expanded(child: Text(report.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(report.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd/MM/yyyy HH:mm').format(report.createdAt), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                Text(report.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
          const SizedBox(height: 8),
          Text(report.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () => _showDetailDialog(report),
              icon: const Icon(Icons.remove_red_eye, size: 16),
              label: const Text('Lihat Detail & Tanggapi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(BugReport report) {
    String selectedStatus = report.status;
    final resController = TextEditingController(text: report.adminResponse ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                width: 600,
                padding: const EdgeInsets.all(24),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    Text('Detail Laporan', style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text('Judul:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                    Text(report.title, style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 12),
                    Text('Deskripsi:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                    Text(report.description),
                    const SizedBox(height: 16),
                    if (report.screenshotUrl.isNotEmpty) ...[
                      Text('Screenshot:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
                      const SizedBox(height: 8),
                      Image.network(report.screenshotUrl, height: 200, fit: BoxFit.contain, alignment: Alignment.centerLeft),
                      const SizedBox(height: 16),
                    ],
                    const Divider(),
                    const SizedBox(height: 16),
                    Text('Tanggapan Super Admin', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(labelText: 'Status Tiket', border: OutlineInputBorder()),
                      items: ['terbuka', 'diproses', 'selesai', 'ditolak']
                          .map((s) => DropdownMenuItem(value: s, child: Text(s.toUpperCase())))
                          .toList(),
                      onChanged: (v) => setState(() => selectedStatus = v!),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: resController,
                      decoration: const InputDecoration(labelText: 'Pesan Balasan', border: OutlineInputBorder()),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            await _bugReportService.updateReportStatus(
                              schoolId: report.schoolId,
                              reportId: report.id,
                              status: selectedStatus,
                              adminResponse: resController.text,
                            );
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: const Text('Simpan & Update'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
