import 'dart:math' show pi;
import 'package:flutter/material.dart' show Color, Colors;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class ExamPdfGenerator {
  // ── Color helpers ────────────────────────────────────────────────────────
  static PdfColor _pdfColor(Color c) =>
      PdfColor(c.red / 255.0, c.green / 255.0, c.blue / 255.0);

  static final _indigo = _pdfColor(const Color(0xFF475569));
  static final _violet = _pdfColor(const Color(0xFF475569));
  static final _slate = _pdfColor(const Color(0xFF334155));
  static final _slateLight = _pdfColor(const Color(0xFF64748B));
  static final _bgGray = _pdfColor(const Color(0xFFF8FAFC));
  static final _border = _pdfColor(const Color(0xFFE2E8F0));
  static final _green = _pdfColor(const Color(0xFF475569));

  // ── Date Formatting Bahasa Indonesia ─────────────────────────────────────
  static String formatIndonesianDate(DateTime date, {bool includeDayName = true}) {
    final days = {
      'Monday': 'Senin',
      'Tuesday': 'Selasa',
      'Wednesday': 'Rabu',
      'Thursday': 'Kamis',
      'Friday': 'Jumat',
      'Saturday': 'Sabtu',
      'Sunday': 'Minggu',
    };
    final months = {
      'January': 'Januari',
      'February': 'Februari',
      'March': 'Maret',
      'April': 'April',
      'May': 'Mei',
      'June': 'Juni',
      'July': 'Juli',
      'August': 'Agustus',
      'September': 'September',
      'October': 'Oktober',
      'November': 'November',
      'December': 'Desember',
    };

    final dayNameEnglish = DateFormat('EEEE').format(date);
    final monthNameEnglish = DateFormat('MMMM').format(date);

    final dayName = days[dayNameEnglish] ?? dayNameEnglish;
    final monthName = months[monthNameEnglish] ?? monthNameEnglish;

    if (includeDayName) {
      return '$dayName, ${date.day} $monthName ${date.year}';
    } else {
      return '${date.day} $monthName ${date.year}';
    }
  }

  // ── Common header ────────────────────────────────────────────────────────
  static pw.Widget _pageHeader({
    required String eventName,
    required String examType,
    required String dateRange,
    required String title,
    required PdfColor accentColor,
    bool showPrintedDate = true,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: accentColor,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      width: double.infinity,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            '$eventName  |  $examType',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            dateRange,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9),
            textAlign: pw.TextAlign.center,
          ),
          if (showPrintedDate) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'Dicetak: ${formatIndonesianDate(DateTime.now(), includeDayName: false)} ${DateFormat('HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 7.5),
              textAlign: pw.TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PDF 1: Jadwal per Kelas (untuk Murid)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> downloadSchedulePerClass({
    required String eventName,
    required String examType,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> timetable,
    required Map<String, String> scheduleGrid,
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
  }) async {
    final doc = pw.Document();

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    // Build exam days list
    final days = <DateTime>[];
    if (startDate != null && endDate != null) {
      DateTime cur = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      while (!cur.isAfter(end)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
    }

    // Collect unique classes from timetable
    final classMap = <String, String>{}; // classId -> className
    for (final t in timetable) {
      classMap[t['classId'] as String? ?? ''] = t['className'] as String? ?? '-';
    }

    // Per-class schedule: className -> list of { day, session, subjectName }
    final classSchedules = <String, List<Map<String, dynamic>>>{};
    for (final entry in classMap.entries) {
      final cid = entry.key;
      final cname = entry.value;
      classSchedules[cname] = [];

      for (int d = 0; d < days.length; d++) {
        for (int s = 0; s < sessions.length; s++) {
          final key = 'day_${d}_session_$s';
          final subjectId = scheduleGrid[key];
          if (subjectId == null) continue;
          // Check if this class has this subject
          final hasSubject = timetable.any(
            (t) => t['classId'] == cid && t['subjectId'] == subjectId,
          );
          if (!hasSubject) continue;
          final session = sessions[s];
          final subjectName = timetable.firstWhere(
            (t) => t['subjectId'] == subjectId,
            orElse: () => {'subjectName': subjectId},
          )['subjectName'] as String? ?? subjectId ?? '-';

          classSchedules[cname]!.add({
            'day': formatIndonesianDate(days[d]),
            'sessionName': session['name'] ?? 'Sesi ${s + 1}',
            'time': '${session['startTime']} - ${session['endTime']}',
            'subject': subjectName,
          });
        }
      }
    }

    final sortedClasses = classSchedules.keys.toList()..sort();

    for (final className in sortedClasses) {
      final entries = classSchedules[className] ?? [];
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _pageHeader(
                eventName: eventName,
                examType: examType,
                dateRange: dateRange,
                title: 'Jadwal Ujian per Kelas',
                accentColor: _indigo,
                showPrintedDate: false,
              ),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: pw.BoxDecoration(
                  color: _bgGray,
                  border: pw.Border(
                    left: pw.BorderSide(color: _indigo, width: 3),
                    top: pw.BorderSide(color: _border, width: 0.5),
                    right: pw.BorderSide(color: _border, width: 0.5),
                    bottom: pw.BorderSide(color: _border, width: 0.5),
                  ),
                ),
                child: pw.Row(
                  children: [
                    pw.Text(
                      'Kelas: $className',
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: _slate,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 8),
              if (entries.isEmpty)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 12, bottom: 8),
                  child: pw.Text('Tidak ada jadwal ujian.', style: const pw.TextStyle(fontSize: 9)),
                )
              else ...[
                // Group entries by day
                ...() {
                  final Map<String, List<Map<String, dynamic>>> dayGrouped = {};
                  for (final entry in entries) {
                    final day = entry['day'] as String? ?? '-';
                    dayGrouped.putIfAbsent(day, () => []).add(entry);
                  }

                  return dayGrouped.entries.map((dayEntry) {
                    final dayName = dayEntry.key;
                    final sessionsList = dayEntry.value;

                    return pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Day Sub-header
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          width: double.infinity,
                          decoration: pw.BoxDecoration(
                            color: _bgGray,
                            border: pw.Border(
                              left: pw.BorderSide(color: _indigo, width: 3),
                              top: pw.BorderSide(color: _border, width: 0.5),
                              right: pw.BorderSide(color: _border, width: 0.5),
                              bottom: pw.BorderSide(color: _border, width: 0.5),
                            ),
                          ),
                          child: pw.Text(
                            dayName,
                            style: pw.TextStyle(
                              fontSize: 9,
                              fontWeight: pw.FontWeight.bold,
                              color: _slate,
                            ),
                          ),
                        ),
                        // Sessions Table
                        pw.Table(
                          border: pw.TableBorder.all(color: _border, width: 0.5),
                          columnWidths: {
                            0: const pw.FlexColumnWidth(1.2), // Sesi
                            1: const pw.FlexColumnWidth(1.2), // Waktu
                            2: const pw.FlexColumnWidth(3),   // Mata Pelajaran
                          },
                          children: [
                            // Table Header inside table
                            pw.TableRow(
                              decoration: pw.BoxDecoration(color: _bgGray),
                              children: ['Sesi', 'Waktu', 'Mata Pelajaran']
                                  .map((h) => pw.Padding(
                                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        child: pw.Text(h,
                                            style: pw.TextStyle(
                                              color: _slate,
                                              fontSize: 8,
                                              fontWeight: pw.FontWeight.bold,
                                            )),
                                      ))
                                  .toList(),
                            ),
                            // Rows data
                            ...sessionsList.asMap().entries.map((se) {
                              final sIdx = se.key;
                              final sRow = se.value;
                              final isOdd = sIdx.isOdd;
                              return pw.TableRow(
                                decoration: pw.BoxDecoration(
                                  color: isOdd ? _bgGray : PdfColors.white,
                                ),
                                children: [
                                  sRow['sessionName'],
                                  sRow['time'],
                                  sRow['subject'],
                                ].map((cell) => pw.Padding(
                                      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      child: pw.Text(
                                        cell as String? ?? '-',
                                        style: const pw.TextStyle(fontSize: 8),
                                      ),
                                    )).toList(),
                              );
                            }).toList(),
                          ],
                        ),
                        pw.SizedBox(height: 12),
                      ],
                    );
                  }).toList();
                }(),
              ],
            ],
          ),
        ),
      );
    }

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'jadwal_per_kelas_${eventName.replaceAll(' ', '_')}.pdf',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PDF 2: Jadwal Seluruh Ujian + Pengawas (untuk Pengawas)
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> downloadProctorSchedule({
    required String eventName,
    required String examType,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<Map<String, dynamic>> sessions,
    required List<Map<String, dynamic>> timetable,
    required Map<String, String> scheduleGrid,
    required Map<String, String> proctorGrid,
    required List<Map<String, dynamic>> teachers, // [{id, displayName}]
  }) async {
    final doc = pw.Document();

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    // Build exam days
    final days = <DateTime>[];
    if (startDate != null && endDate != null) {
      DateTime cur = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      while (!cur.isAfter(end)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
    }

    // Helper: teacher name by id
    String teacherName(String? tid) {
      if (tid == null) return '-';
      final t = teachers.firstWhere((t) => t['id'] == tid, orElse: () => {'displayName': '-'});
      return t['displayName'] as String? ?? '-';
    }

    // Helper: subject name by id
    String subjectName(String? sid) {
      if (sid == null) return '-';
      final t = timetable.firstWhere((t) => t['subjectId'] == sid, orElse: () => {'subjectName': '-'});
      return t['subjectName'] as String? ?? '-';
    }

    // Helper: classes for subject
    String classesForSubject(String? sid) {
      if (sid == null) return '-';
      final classes = timetable
          .where((t) => t['subjectId'] == sid)
          .map((t) => t['className'] as String? ?? '-')
          .toSet()
          .toList()
        ..sort();
      return classes.join(', ');
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          _pageHeader(
            eventName: eventName,
            examType: examType,
            dateRange: dateRange,
            title: 'Jadwal Ujian & Pengawas Ruangan',
            accentColor: _violet,
          ),
          pw.SizedBox(height: 16),
          ...List.generate(days.length, (dayIdx) {
            final day = days[dayIdx];
            final dayLabel = formatIndonesianDate(day);
            final sessionRows = List.generate(sessions.length, (sIdx) {
              final key = 'day_${dayIdx}_session_$sIdx';
              final sid = scheduleGrid[key];
              final tid = proctorGrid[key];
              final session = sessions[sIdx];
              return {
                'session': session['name'] ?? 'Sesi ${sIdx + 1}',
                'time': '${session['startTime']} - ${session['endTime']}',
                'subject': subjectName(sid),
                'classes': classesForSubject(sid),
                'proctor': teacherName(tid),
              };
            });

            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Day header
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: _bgGray,
                    border: pw.Border(
                      left: pw.BorderSide(color: _violet, width: 3),
                      top: pw.BorderSide(color: _border, width: 0.5),
                      right: pw.BorderSide(color: _border, width: 0.5),
                      bottom: pw.BorderSide(color: _border, width: 0.5),
                    ),
                  ),
                  child: pw.Row(
                    children: [
                      pw.Text(
                        dayLabel,
                        style: pw.TextStyle(
                          color: _slate,
                          fontSize: 10,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Table(
                  border: pw.TableBorder.all(color: _border, width: 0.5),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(1.2),
                    1: const pw.FlexColumnWidth(1.2),
                    2: const pw.FlexColumnWidth(1.8),
                    3: const pw.FlexColumnWidth(2.5),
                    4: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    pw.TableRow(
                      decoration: pw.BoxDecoration(color: _bgGray),
                      children: ['Sesi', 'Waktu', 'Mata Pelajaran', 'Kelas', 'Pengawas']
                          .map((h) => pw.Padding(
                                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                child: pw.Text(h,
                                    style: pw.TextStyle(
                                      color: _slate,
                                      fontSize: 9,
                                      fontWeight: pw.FontWeight.bold,
                                    )),
                              ))
                          .toList(),
                    ),
                    ...sessionRows.asMap().entries.map((e) {
                      final isOdd = e.key.isOdd;
                      final row = e.value;
                      return pw.TableRow(
                        decoration: pw.BoxDecoration(
                          color: isOdd ? _bgGray : PdfColors.white,
                        ),
                        children: [
                          row['session'],
                          row['time'],
                          row['subject'],
                          row['classes'],
                          row['proctor'],
                        ]
                            .map((cell) => pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                  child: pw.Text(
                                    cell as String? ?? '-',
                                    style: const pw.TextStyle(fontSize: 9),
                                  ),
                                ))
                            .toList(),
                      );
                    }),
                  ],
                ),
                pw.SizedBox(height: 14),
              ],
            );
          }),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'jadwal_pengawas_${eventName.replaceAll(' ', '_')}.pdf',
    );
  }
}
