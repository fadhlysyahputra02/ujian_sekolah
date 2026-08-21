import 'package:flutter/material.dart' show Color;
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
  static final _bgGray = _pdfColor(const Color(0xFFF8FAFC));
  static final _border = _pdfColor(const Color(0xFFCBD5E1));

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
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      width: double.infinity,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            '$eventName  |  $examType',
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 9.5),
            textAlign: pw.TextAlign.center,
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            dateRange,
            style: const pw.TextStyle(color: PdfColors.white, fontSize: 8.5),
            textAlign: pw.TextAlign.center,
          ),
          if (showPrintedDate) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              'Dicetak: ${formatIndonesianDate(DateTime.now(), includeDayName: false)} ${DateFormat('HH:mm').format(DateTime.now())}',
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 7),
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
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
  }) async {
    final doc = pw.Document();

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    final days = <DateTime>[];
    if (startDate != null && endDate != null) {
      DateTime cur = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      while (!cur.isAfter(end)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
    }

    final classMap = <String, String>{};
    for (final t in timetable) {
      final cid = t['classId']?.toString() ?? '';
      final cname = t['className']?.toString() ?? '-';
      if (cid.isNotEmpty) classMap[cid] = cname;
    }

    final classSchedules = <String, List<Map<String, String>>>{};
    for (final entry in classMap.entries) {
      final cid = entry.key;
      final cname = entry.value;
      final scheduleEntries = <Map<String, String>>[];

      for (int d = 0; d < days.length; d++) {
        for (int s = 0; s < sessions.length; s++) {
          final sessionKey = 'day_${d}_session_$s';
          final matched = timetable.where(
            (t) => t['classId']?.toString() == cid && t['sessionId']?.toString() == sessionKey,
          ).toList();
          if (matched.isEmpty) continue;

          final session = sessions[s];
          for (final m in matched) {
            scheduleEntries.add({
              'day': formatIndonesianDate(days[d]),
              'sessionName': session['name']?.toString() ?? 'Sesi ${s + 1}',
              'time': '${session['startTime'] ?? ''} - ${session['endTime'] ?? ''}',
              'subject': m['subjectName']?.toString() ?? '-',
            });
          }
        }
      }
      classSchedules[cname] = scheduleEntries;
    }

    final sortedClasses = classSchedules.keys.toList()..sort();

    for (final className in sortedClasses) {
      final entries = classSchedules[className] ?? [];
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (ctx) => [
            _pageHeader(
              eventName: eventName.isNotEmpty ? eventName : 'Event Ujian',
              examType: examType.isNotEmpty ? examType : 'Ujian',
              dateRange: dateRange,
              title: 'Jadwal Ujian per Kelas',
              accentColor: _indigo,
              showPrintedDate: false,
            ),
            pw.SizedBox(height: 12),
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
            pw.SizedBox(height: 10),
            if (entries.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 4, top: 8),
                child: pw.Text('Tidak ada jadwal ujian untuk kelas ini.', style: const pw.TextStyle(fontSize: 9)),
              )
            else ...() {
              final Map<String, List<Map<String, String>>> dayGrouped = {};
              for (final entry in entries) {
                final day = entry['day'] ?? '-';
                dayGrouped.putIfAbsent(day, () => []).add(entry);
              }

              final List<pw.Widget> widgets = [];
              for (final dayEntry in dayGrouped.entries) {
                final dayName = dayEntry.key;
                final sessionsList = dayEntry.value;

                widgets.add(
                  pw.Container(
                    margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    width: double.infinity,
                    decoration: pw.BoxDecoration(
                      color: _bgGray,
                      border: pw.Border.all(color: _border, width: 0.5),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                    child: pw.Text(
                      dayName,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _slate),
                    ),
                  ),
                );

                widgets.add(
                  pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(color: _border, width: 0.5),
                    headers: ['Sesi', 'Waktu', 'Mata Pelajaran'],
                    data: sessionsList.map((s) => [
                      s['sessionName'] ?? '-',
                      s['time'] ?? '-',
                      s['subject'] ?? '-',
                    ]).toList(),
                    headerStyle: pw.TextStyle(color: _slate, fontSize: 8, fontWeight: pw.FontWeight.bold),
                    headerDecoration: pw.BoxDecoration(color: _bgGray),
                    headerHeight: 20,
                    cellHeight: 20,
                    cellStyle: const pw.TextStyle(fontSize: 8),
                    cellAlignments: {
                      0: pw.Alignment.centerLeft,
                      1: pw.Alignment.centerLeft,
                      2: pw.Alignment.centerLeft,
                    },
                    columnWidths: {
                      0: const pw.FlexColumnWidth(1.2),
                      1: const pw.FlexColumnWidth(1.3),
                      2: const pw.FlexColumnWidth(3.0),
                    },
                  ),
                );
                widgets.add(pw.SizedBox(height: 8));
              }
              return widgets;
            }(),
          ],
        ),
      );
    }

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
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
    required Map<String, String> proctorGrid,
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
    required List<Map<String, dynamic>> teachers,
  }) async {
    final doc = pw.Document();

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    final days = <DateTime>[];
    if (startDate != null && endDate != null) {
      DateTime cur = DateTime(startDate.year, startDate.month, startDate.day);
      final end = DateTime(endDate.year, endDate.month, endDate.day);
      while (!cur.isAfter(end)) {
        days.add(cur);
        cur = cur.add(const Duration(days: 1));
      }
    }

    String teacherName(String? tid) {
      if (tid == null || tid.isEmpty) return '-';
      for (final t in teachers) {
        if (t['id']?.toString() == tid) {
          return t['displayName']?.toString() ?? '-';
        }
      }
      return '-';
    }

    final List<pw.Widget> pageContent = [
      _pageHeader(
        eventName: eventName.isNotEmpty ? eventName : 'Event Ujian',
        examType: examType.isNotEmpty ? examType : 'Ujian',
        dateRange: dateRange,
        title: 'Jadwal Ujian & Pengawas Ruangan',
        accentColor: _violet,
      ),
      pw.SizedBox(height: 12),
    ];

    if (days.isEmpty) {
      pageContent.add(
        pw.Text('Belum ada tanggal pelaksanaan ujian.', style: const pw.TextStyle(fontSize: 10)),
      );
    } else {
      for (int dayIdx = 0; dayIdx < days.length; dayIdx++) {
        final day = days[dayIdx];
        final dayLabel = formatIndonesianDate(day);

        pageContent.add(
          pw.Container(
            margin: const pw.EdgeInsets.only(top: 8, bottom: 4),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: _bgGray,
              border: pw.Border(
                left: pw.BorderSide(color: _violet, width: 3),
                top: pw.BorderSide(color: _border, width: 0.5),
                right: pw.BorderSide(color: _border, width: 0.5),
                bottom: pw.BorderSide(color: _border, width: 0.5),
              ),
            ),
            child: pw.Text(
              dayLabel,
              style: pw.TextStyle(color: _slate, fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );

        final List<List<String>> tableData = [];
        for (int sIdx = 0; sIdx < sessions.length; sIdx++) {
          final session = sessions[sIdx];
          final sessionKey = 'day_${dayIdx}_session_$sIdx';
          final sName = session['name']?.toString() ?? 'Sesi ${sIdx + 1}';
          final sTime = '${session['startTime'] ?? ''} - ${session['endTime'] ?? ''}';

          if (rooms.isEmpty) {
            final proctorKey = 'day_${dayIdx}_session_$sIdx';
            final tid = proctorGrid[proctorKey];
            final pname = teacherName(tid);

            final scheduledEntries = timetable
                .where((t) => t['sessionId']?.toString() == sessionKey)
                .toList();

            final subjectText = scheduledEntries.isEmpty
                ? '-'
                : scheduledEntries
                    .map((t) => t['subjectName']?.toString() ?? '-')
                    .toSet()
                    .join(' & ');

            final classesText = scheduledEntries.isEmpty
                ? '-'
                : scheduledEntries
                    .map((t) => t['className']?.toString() ?? '-')
                    .toSet()
                    .toList()
                    .join(', ');

            tableData.add([sName, sTime, '-', subjectText, classesText, pname]);
          } else {
            for (final room in rooms) {
              final rid = room['id']?.toString() ?? '';
              final rname = room['name']?.toString() ?? room['code']?.toString() ?? '-';

              final proctorKey = 'day_${dayIdx}_session_${sIdx}_room_$rid';
              final tid = proctorGrid[proctorKey] ?? proctorGrid['day_${dayIdx}_session_$sIdx'];
              final pname = teacherName(tid);

              final roomClasses = roomAssignments[rid] ?? [];
              final roomClassIds = roomClasses.map((rc) => rc['classId']?.toString() ?? '').toSet();

              final scheduledEntries = timetable
                  .where((t) =>
                      t['sessionId']?.toString() == sessionKey &&
                      (roomClassIds.isEmpty || roomClassIds.contains(t['classId']?.toString() ?? '')))
                  .toList();

              final subjectText = scheduledEntries.isEmpty
                  ? '-'
                  : scheduledEntries
                      .map((t) => t['subjectName']?.toString() ?? '-')
                      .toSet()
                      .join(' & ');

              final classesText = scheduledEntries.isEmpty
                  ? '-'
                  : scheduledEntries
                      .map((t) => t['className']?.toString() ?? '-')
                      .toSet()
                      .toList()
                      .join(', ');

              tableData.add([sName, sTime, rname, subjectText, classesText, pname]);
            }
          }
        }

        if (tableData.isEmpty) {
          pageContent.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 8),
              child: pw.Text('Tidak ada sesi ujian pada hari ini.', style: const pw.TextStyle(fontSize: 8)),
            ),
          );
        } else {
          pageContent.add(
            pw.TableHelper.fromTextArray(
              border: pw.TableBorder.all(color: _border, width: 0.5),
              headers: ['Sesi', 'Waktu', 'Ruangan', 'Mata Pelajaran', 'Kelas', 'Pengawas'],
              data: tableData,
              headerStyle: pw.TextStyle(color: _slate, fontSize: 8, fontWeight: pw.FontWeight.bold),
              headerDecoration: pw.BoxDecoration(color: _bgGray),
              headerHeight: 22,
              cellHeight: 20,
              cellStyle: const pw.TextStyle(fontSize: 7.5),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.centerLeft,
                3: pw.Alignment.centerLeft,
                4: pw.Alignment.centerLeft,
                5: pw.Alignment.centerLeft,
              },
              columnWidths: {
                0: const pw.FlexColumnWidth(1.1),
                1: const pw.FlexColumnWidth(1.2),
                2: const pw.FlexColumnWidth(1.1),
                3: const pw.FlexColumnWidth(2.0),
                4: const pw.FlexColumnWidth(1.6),
                5: const pw.FlexColumnWidth(1.8),
              },
            ),
          );
        }
        pageContent.add(pw.SizedBox(height: 10));
      }
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pageContent,
      ),
    );

    final pdfBytes = await doc.save();
    await Printing.sharePdf(
      bytes: pdfBytes,
      filename: 'jadwal_pengawas_${eventName.replaceAll(' ', '_')}.pdf',
    );
  }
}
