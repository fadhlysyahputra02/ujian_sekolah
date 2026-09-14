import 'dart:math';
import 'package:flutter/material.dart' show Color;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Helper: load Unicode-capable fonts once per download call
Future<pw.ThemeData> _buildTheme() async {
  final regular = await PdfGoogleFonts.notoSansRegular();
  final bold = await PdfGoogleFonts.notoSansBold();
  return pw.ThemeData.withFont(
    base: regular,
    bold: bold,
  );
}

class ExamPdfGenerator {
  // ── Color helpers ────────────────────────────────────────────────────────
  static PdfColor _pdfColor(Color c) =>
      PdfColor(c.red / 255.0, c.green / 255.0, c.blue / 255.0);

  static final _indigo = _pdfColor(const Color(0xFF4F46E5));
  static final _slate = _pdfColor(const Color(0xFF334155));
  static final _bgGray = _pdfColor(const Color(0xFFF8FAFC));
  static final _border = _pdfColor(const Color(0xFFCBD5E1));
  static final _green = _pdfColor(const Color(0xFF059669));

  // ── Class color palette for seat map ────────────────────────────────────
  static final List<PdfColor> _classColorPalette = [
    _pdfColor(const Color(0xFF6366F1)), // indigo
    _pdfColor(const Color(0xFFEC4899)), // pink
    _pdfColor(const Color(0xFFF59E0B)), // amber
    _pdfColor(const Color(0xFF10B981)), // emerald
    _pdfColor(const Color(0xFF3B82F6)), // blue
    _pdfColor(const Color(0xFFEF4444)), // red
    _pdfColor(const Color(0xFF8B5CF6)), // violet
    _pdfColor(const Color(0xFF14B8A6)), // teal
  ];

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
  //  PDF 1: Denah Kursi (Seat Layout per Room)
  //  1 halaman = 1 ruangan, grid kursi visual dengan nama siswa
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> downloadSeatLayout({
    required String eventName,
    required String examType,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
    required Map<String, List<Map<String, dynamic>>> classRealStudentsMap,
    required Map<String, Map<String, dynamic>> addState,
  }) async {
    final theme = await _buildTheme();
    final doc = pw.Document(theme: theme);

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    // Build class color map across all rooms
    final Set<String> allClassNames = {};
    for (final assignments in roomAssignments.values) {
      for (final a in assignments) {
        final cn = (a['className'] ?? a['classId'] ?? '').toString().trim();
        if (cn.isNotEmpty) allClassNames.add(cn);
      }
    }
    final classColorMap = <String, PdfColor>{};
    final classList = allClassNames.toList()..sort();
    for (int i = 0; i < classList.length; i++) {
      classColorMap[classList[i]] = _classColorPalette[i % _classColorPalette.length];
    }

    // A4 usable width with 20pt margin each side
    const double pageMargin = 20.0;
    const double usableWidth = 595.28 - pageMargin * 2; // ≈ 555pt

    for (final room in rooms) {
      final rid = (room['id'] ?? '').toString();
      final rname = (room['name'] ?? room['code'] ?? rid).toString();
      final roomCapacity = (room['capacity'] as num?)?.toInt() ?? 0;
      final assignments = roomAssignments[rid] ?? [];

      final List<Map<String, String>> seatData = _buildSeatData(
        room: room,
        assignments: assignments,
        rooms: rooms,
        roomAssignments: roomAssignments,
        classRealStudentsMap: classRealStudentsMap,
        addState: addState,
        roomCapacity: roomCapacity,
      );

      final layoutState = addState['layout_$rid'];
      final int totalCols = ((layoutState?['colsPerPair'] as int?) ?? 8).clamp(4, 10);
      final int totalRows = roomCapacity > 0 ? (roomCapacity / totalCols).ceil() : 0;

      // Dynamic seat size: fill full width
      const double seatGap = 4.0;
      final double seatSize = (usableWidth - (totalCols - 1) * seatGap) / totalCols;
      // Font sizes scale with seat size
      final double numFontSize = (seatSize * 0.18).clamp(7.0, 16.0);
      final double nameFontSize = (seatSize * 0.10).clamp(5.0, 9.0);
      final double clsFontSize = (seatSize * 0.08).clamp(4.5, 7.5);

      final classesInRoom = assignments
          .map((a) => (a['className'] ?? a['classId'] ?? '').toString().trim())
          .where((c) => c.isNotEmpty)
          .toSet();

      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(pageMargin),
          build: (ctx) {
            final List<pw.Widget> content = [];

            // ── Compact gray header ──────────────────────────────────────
            content.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: pw.BoxDecoration(
                  color: _slate,
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Denah Kursi Ruang Ujian',
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 11,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          '${eventName.isNotEmpty ? eventName : "Event Ujian"}  |  ${examType.isNotEmpty ? examType : "Ujian"}',
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                        ),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text(
                          dateRange,
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 7.5),
                        ),
                        pw.SizedBox(height: 2),
                        pw.Text(
                          'Dicetak: ${formatIndonesianDate(DateTime.now(), includeDayName: false)} ${DateFormat('HH:mm').format(DateTime.now())}',
                          style: const pw.TextStyle(color: PdfColors.white, fontSize: 6.5),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
            content.add(pw.SizedBox(height: 6));

            // ── Room info bar ────────────────────────────────────────────
            content.add(
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: _bgGray,
                  border: pw.Border(
                    left: pw.BorderSide(color: _slate, width: 3),
                    top: pw.BorderSide(color: _border, width: 0.5),
                    right: pw.BorderSide(color: _border, width: 0.5),
                    bottom: pw.BorderSide(color: _border, width: 0.5),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Ruangan: $rname',
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _slate),
                    ),
                    pw.Text(
                      'Kapasitas: $roomCapacity  |  Terisi: ${seatData.where((s) => s['name']!.isNotEmpty).length}',
                      style: pw.TextStyle(fontSize: 8, color: _slate),
                    ),
                  ],
                ),
              ),
            );
            content.add(pw.SizedBox(height: 5));

            // ── PAPAN TULIS label ────────────────────────────────────────
            content.add(
              pw.Center(
                child: pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 3),
                  decoration: pw.BoxDecoration(
                    color: _pdfColor(const Color(0xFF64748B)),
                    borderRadius: pw.BorderRadius.circular(3),
                  ),
                  child: pw.Text(
                    'PAPAN TULIS',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 7,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              ),
            );
            content.add(pw.SizedBox(height: 6));

            // ── Seat grid — full width, flexible rows ────────────────────
            for (int rowIdx = 0; rowIdx < totalRows; rowIdx++) {
              content.add(
                pw.Padding(
                  padding: pw.EdgeInsets.only(bottom: rowIdx < totalRows - 1 ? seatGap : 0),
                  child: pw.Row(
                    children: List.generate(totalCols, (colIdx) {
                      final seatIdx = rowIdx * totalCols + colIdx;
                      // Filler cell for incomplete last row
                      if (seatIdx >= roomCapacity) {
                        return pw.Padding(
                          padding: pw.EdgeInsets.only(left: colIdx > 0 ? seatGap : 0),
                          child: pw.SizedBox(width: seatSize, height: seatSize),
                        );
                      }

                      final seat = seatIdx < seatData.length
                          ? seatData[seatIdx]
                          : {'name': '', 'class': ''};
                      final sName = seat['name'] ?? '';
                      final sClass = seat['class'] ?? '';
                      final hasStudent = sName.isNotEmpty;

                      final PdfColor cellColor;
                      final PdfColor textColor;
                      if (hasStudent) {
                        cellColor = classColorMap[sClass] ?? _slate;
                        textColor = PdfColors.white;
                      } else {
                        cellColor = _pdfColor(const Color(0xFFEEF0F4));
                        textColor = _pdfColor(const Color(0xFFADB5C4));
                      }

                      return pw.Padding(
                        padding: pw.EdgeInsets.only(left: colIdx > 0 ? seatGap : 0),
                        child: pw.Container(
                          width: seatSize,
                          height: seatSize,
                          decoration: pw.BoxDecoration(
                            color: hasStudent
                                ? PdfColor(cellColor.red, cellColor.green, cellColor.blue, 0.90)
                                : cellColor,
                            borderRadius: pw.BorderRadius.circular(3),
                            border: pw.Border.all(
                              color: hasStudent ? cellColor : _border,
                              width: 0.5,
                            ),
                          ),
                          child: pw.Column(
                            mainAxisAlignment: pw.MainAxisAlignment.center,
                            crossAxisAlignment: pw.CrossAxisAlignment.center,
                            children: [
                              pw.Text(
                                '${seatIdx + 1}',
                                style: pw.TextStyle(
                                  fontSize: numFontSize,
                                  fontWeight: pw.FontWeight.bold,
                                  color: textColor,
                                ),
                                textAlign: pw.TextAlign.center,
                              ),
                              if (hasStudent) ...[
                                pw.SizedBox(height: 1),
                                pw.Padding(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 2),
                                  child: pw.Text(
                                    _abbreviateName(sName),
                                    style: pw.TextStyle(
                                      fontSize: nameFontSize,
                                      color: PdfColors.white,
                                    ),
                                    textAlign: pw.TextAlign.center,
                                    maxLines: 2,
                                  ),
                                ),
                                pw.Text(
                                  sClass,
                                  style: pw.TextStyle(
                                    fontSize: clsFontSize,
                                    color: PdfColor(1, 1, 1, 0.75),
                                    fontWeight: pw.FontWeight.bold,
                                  ),
                                  textAlign: pw.TextAlign.center,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              );
            }

            // ── Legend ────────────────────────────────────────────────────
            if (classesInRoom.isNotEmpty) {
              content.add(pw.SizedBox(height: 10));
              content.add(pw.Divider(color: _border, thickness: 0.5));
              content.add(pw.SizedBox(height: 4));
              content.add(pw.Text(
                'Keterangan Kelas:',
                style: pw.TextStyle(fontSize: 7.5, fontWeight: pw.FontWeight.bold, color: _slate),
              ));
              content.add(pw.SizedBox(height: 4));
              content.add(
                pw.Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: classColorMap.entries
                      .where((e) => classesInRoom.contains(e.key))
                      .map((e) => pw.Row(
                            mainAxisSize: pw.MainAxisSize.min,
                            children: [
                              pw.Container(
                                width: 10,
                                height: 10,
                                decoration: pw.BoxDecoration(
                                  color: e.value,
                                  borderRadius: pw.BorderRadius.circular(2),
                                ),
                              ),
                              pw.SizedBox(width: 4),
                              pw.Text(e.key, style: const pw.TextStyle(fontSize: 7.5)),
                            ],
                          ))
                      .toList(),
                ),
              );
            }

            return content;
          },
        ),
      );
    }

    if (rooms.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => pw.Center(
            child: pw.Text('Belum ada ruangan ujian yang ditambahkan.',
                style: const pw.TextStyle(fontSize: 12)),
          ),
        ),
      );
    }

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'denah_kursi_${eventName.replaceAll(' ', '_')}.pdf',
    );
  }


  // ─────────────────────────────────────────────────────────────────────────
  //  PDF 2: Kartu Meja & Absen (Desk Card per Student)
  //  Kartu kecil potongan per siswa: nama, kelas, nomor kursi, ruangan
  //  Layout: 3 kolom x 6 baris = 18 kartu per halaman
  // ─────────────────────────────────────────────────────────────────────────
  static Future<void> downloadDeskCards({
    required String eventName,
    required String examType,
    required DateTime? startDate,
    required DateTime? endDate,
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
    required Map<String, List<Map<String, dynamic>>> classRealStudentsMap,
    required Map<String, Map<String, dynamic>> addState,
  }) async {
    final theme = await _buildTheme();
    final doc = pw.Document(theme: theme);

    final dateRange = startDate != null && endDate != null
        ? '${formatIndonesianDate(startDate, includeDayName: false)} - ${formatIndonesianDate(endDate, includeDayName: false)}'
        : '-';

    // Calculate academic year from startDate
    String academicYear = '-';
    if (startDate != null) {
      final y = startDate.year;
      academicYear = startDate.month >= 7 ? '$y/${y + 1}' : '${y - 1}/$y';
    }

    final List<Map<String, String>> allCards = [];

    for (final room in rooms) {
      final rid = (room['id'] ?? '').toString();
      final rname = (room['name'] ?? room['code'] ?? rid).toString();
      final roomCapacity = (room['capacity'] as num?)?.toInt() ?? 0;
      final assignments = roomAssignments[rid] ?? [];

      final seatData = _buildSeatData(
        room: room,
        assignments: assignments,
        rooms: rooms,
        roomAssignments: roomAssignments,
        classRealStudentsMap: classRealStudentsMap,
        addState: addState,
        roomCapacity: roomCapacity,
      );

      for (int i = 0; i < seatData.length; i++) {
        final seat = seatData[i];
        final sName = seat['name'] ?? '';
        if (sName.isEmpty) continue;
        allCards.add({
          'name': sName,
          'class': seat['class'] ?? '',
          'seatNo': '${i + 1}',
          'room': rname,
          'eventName': eventName,
          'examType': examType,
          'dateRange': dateRange,
          'academicYear': academicYear,
          'nis': seat['nis'] ?? '',
        });
      }
    }

    // 3 cols x 6 rows = 18 cards per page
    const int cols = 3;
    const int rows = 6;
    const int cardsPerPage = cols * rows;
    const double cardW = 175.0;
    const double cardH = 120.0;

    if (allCards.isEmpty) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(28),
          build: (_) => pw.Center(
            child: pw.Text('Belum ada data siswa yang dialokasikan ke ruangan.',
                style: const pw.TextStyle(fontSize: 12)),
          ),
        ),
      );
    } else {
      final int totalPages = (allCards.length / cardsPerPage).ceil();

      for (int pageIdx = 0; pageIdx < totalPages; pageIdx++) {
        final startIdx = pageIdx * cardsPerPage;
        final endIdx = (startIdx + cardsPerPage).clamp(0, allCards.length);
        final List<Map<String, String>> pageCards = List.from(allCards.sublist(startIdx, endIdx));
        while (pageCards.length < cardsPerPage) {
          pageCards.add({'name': '', 'class': '', 'seatNo': '', 'room': '', 'eventName': '', 'examType': '', 'dateRange': '', 'academicYear': '', 'nis': ''});
        }

        doc.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            margin: const pw.EdgeInsets.all(18),
            build: (ctx) {
              return pw.Column(
                children: List.generate(rows, (rowIdx) {
                  return pw.Padding(
                    padding: pw.EdgeInsets.only(bottom: rowIdx < rows - 1 ? 4.0 : 0),
                    child: pw.Row(
                      children: List.generate(cols, (colIdx) {
                        final cardIdx = rowIdx * cols + colIdx;
                        final card = pageCards[cardIdx];
                        final isEmpty = (card['name'] ?? '').isEmpty;

                        return pw.Padding(
                          padding: const pw.EdgeInsets.all(3.0),
                          child: pw.Container(
                            width: cardW,
                            height: cardH,
                            decoration: pw.BoxDecoration(
                              border: pw.Border.all(color: _border, width: 0.8),
                              borderRadius: pw.BorderRadius.circular(4),
                              color: isEmpty ? PdfColors.grey100 : PdfColors.white,
                            ),
                            child: isEmpty
                                ? pw.Center(
                                    child: pw.Text('-', style: pw.TextStyle(color: _slate, fontSize: 14)),
                                  )
                                : pw.Column(
                                    children: [
                                      // Header
                                      pw.Container(
                                        width: double.infinity,
                                        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: pw.BoxDecoration(
                                          color: _slate,
                                          borderRadius: const pw.BorderRadius.only(
                                            topLeft: pw.Radius.circular(3),
                                            topRight: pw.Radius.circular(3),
                                          ),
                                        ),
                                        child: pw.Row(
                                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: pw.CrossAxisAlignment.center,
                                          children: [
                                            pw.Expanded(
                                              child: pw.Text(
                                                card['eventName']!.isNotEmpty ? card['eventName']! : 'Event Ujian',
                                                style: pw.TextStyle(
                                                  color: PdfColors.white,
                                                  fontSize: 7,
                                                  fontWeight: pw.FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                              ),
                                            ),
                                            pw.SizedBox(width: 6),
                                            pw.Column(
                                              crossAxisAlignment: pw.CrossAxisAlignment.end,
                                              mainAxisAlignment: pw.MainAxisAlignment.center,
                                              children: [
                                                pw.Text(
                                                  card['examType'] ?? '',
                                                  style: pw.TextStyle(
                                                    color: PdfColors.white,
                                                    fontSize: 6.5,
                                                    fontWeight: pw.FontWeight.bold,
                                                  ),
                                                ),
                                                if ((card['academicYear'] ?? '').isNotEmpty)
                                                  pw.Text(
                                                    card['academicYear']!,
                                                    style: const pw.TextStyle(
                                                      color: PdfColors.white,
                                                      fontSize: 6.0,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Body
                                      pw.Expanded(
                                        child: pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          child: pw.Column(
                                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                                            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
                                            children: [
                                              pw.Row(
                                                crossAxisAlignment: pw.CrossAxisAlignment.center,
                                                children: [
                                                  pw.Container(
                                                    width: 30,
                                                    height: 30,
                                                    alignment: pw.Alignment.center,
                                                    decoration: pw.BoxDecoration(
                                                      color: _green,
                                                      borderRadius: pw.BorderRadius.circular(4),
                                                    ),
                                                    child: pw.Text(
                                                      card['seatNo'] ?? '-',
                                                      style: pw.TextStyle(
                                                        color: PdfColors.white,
                                                        fontSize: 13,
                                                        fontWeight: pw.FontWeight.bold,
                                                      ),
                                                    ),
                                                  ),
                                                  pw.SizedBox(width: 8),
                                                  pw.Column(
                                                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                                                    children: [
                                                      pw.Text('No. Kursi',
                                                          style: pw.TextStyle(fontSize: 6, color: _pdfColor(const Color(0xFF94A3B8)))),
                                                      pw.Text(
                                                        card['room']!.isNotEmpty ? 'Ruang ${card['room']}' : '-',
                                                        style: pw.TextStyle(fontSize: 7, color: _slate, fontWeight: pw.FontWeight.bold),
                                                      ),
                                                    ],
                                                  ),
                                                ],
                                              ),
                                              pw.Divider(color: _border, thickness: 0.5),
                                              pw.Text(
                                                card['name'] ?? '-',
                                                style: pw.TextStyle(
                                                  fontSize: 9.5,
                                                  fontWeight: pw.FontWeight.bold,
                                                  color: _slate,
                                                ),
                                                maxLines: 2,
                                              ),
                                              pw.Row(
                                                children: [
                                                  pw.Text('Kelas: ',
                                                      style: pw.TextStyle(fontSize: 7, color: _pdfColor(const Color(0xFF94A3B8)))),
                                                  pw.Text(
                                                    card['class']!.isNotEmpty ? card['class']! : '-',
                                                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold, color: _slate),
                                                  ),
                                                ],
                                              ),
                                              pw.Text(
                                                card['dateRange'] ?? '',
                                                style: pw.TextStyle(fontSize: 6, color: _pdfColor(const Color(0xFF94A3B8))),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        );
                      }),
                    ),
                  );
                }),
              );
            },
          ),
        );
      }
    }

    final bytes = await doc.save();
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'kartu_meja_${eventName.replaceAll(' ', '_')}.pdf',
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Helper: Build seat data list for a room
  // ─────────────────────────────────────────────────────────────────────────
  static List<Map<String, String>> _buildSeatData({
    required Map<String, dynamic> room,
    required List<Map<String, dynamic>> assignments,
    required List<Map<String, dynamic>> rooms,
    required Map<String, List<Map<String, dynamic>>> roomAssignments,
    required Map<String, List<Map<String, dynamic>>> classRealStudentsMap,
    required Map<String, Map<String, dynamic>> addState,
    required int roomCapacity,
  }) {
    final rid = (room['id'] ?? '').toString();
    final layoutState = addState['layout_$rid'];
    final String arrangeMode = (layoutState?['arrange'] as String?) ?? 'normal';
    final int seed = (layoutState?['seed'] as int?) ?? (rid.hashCode.abs() % 100000 + 42);

    final Map<String, int> skipCountMap = {};
    for (var rMap in rooms) {
      final rId = (rMap['id'] ?? rMap['code'] ?? rMap['name'] ?? '').toString();
      final rName = (rMap['name'] ?? rMap['code'] ?? rId).toString();
      final curId = (room['id'] ?? room['code'] ?? room['name'] ?? '').toString();
      final curName = (room['name'] ?? room['code'] ?? curId).toString();
      if (rId == curId || rName == curName) break;

      List rAssgn = [];
      roomAssignments.forEach((k, v) {
        if (rAssgn.isNotEmpty) return;
        final kStr = k.toString();
        final kClean = kStr.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        final rIdClean = rId.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        final rNameClean = rName.toLowerCase().replaceAll(' ', '').replaceAll('_', '').replaceAll('-', '');
        if (kStr == rId || kStr == rName || (kClean.isNotEmpty && (kClean == rIdClean || kClean == rNameClean))) {
          if (v is List) rAssgn = v;
        }
      });

      for (var a in rAssgn) {
        if (a is Map) {
          final cName = (a['className'] ?? a['classId'] ?? '').toString().trim();
          final cnt = (a['count'] as num?)?.toInt() ?? 0;
          if (cName.isNotEmpty && cnt > 0) {
            skipCountMap[cName] = (skipCountMap[cName] ?? 0) + cnt;
            final cleanC = cName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
            if (cleanC.isNotEmpty && cleanC != cName) {
              skipCountMap[cleanC] = (skipCountMap[cleanC] ?? 0) + cnt;
            }
          }
        }
      }
    }

    final List<List<Map<String, String>>> classQueues = [];
    final List<Map<String, String>> allItems = [];

    for (final a in assignments) {
      final cnt = (a['count'] as num?)?.toInt() ?? 0;
      final cName = (a['className'] ?? a['classId'] ?? 'Kelas').toString().trim();
      final cleanC = cName.toLowerCase().replaceAll(' ', '').replaceAll('-', '');
      final studentIdsList = (a['studentIds'] is List)
          ? (a['studentIds'] as List).map((e) => e.toString()).toList()
          : <String>[];
      final realList = classRealStudentsMap[cName] ?? classRealStudentsMap[cleanC] ?? [];
      final skipIdx = skipCountMap[cName] ?? skipCountMap[cleanC] ?? 0;

      final classList = <Map<String, String>>[];
      for (int k = 0; k < cnt; k++) {
        String sName = '';
        String sNis = '';
        if (studentIdsList.isNotEmpty && k < studentIdsList.length) {
          final targetSid = studentIdsList[k];
          final found = realList.firstWhere(
            (r) => (r['studentId'] ?? r['id'] ?? '').toString() == targetSid,
            orElse: () => {},
          );
          if (found.isNotEmpty) {
            sName = (found['displayName'] ?? found['studentName'] ?? '').toString();
            sNis = (found['nis'] ?? found['nisn'] ?? found['noPeserta'] ?? found['studentCode'] ?? found['username'] ?? found['userCode'] ?? '').toString();
          }
        }
        if (sName.isEmpty) {
          final targetIdx = skipIdx + k;
          if (targetIdx < realList.length) {
            final r = realList[targetIdx];
            sName = (r['displayName'] ?? r['studentName'] ?? '').toString();
            sNis = (r['nis'] ?? r['nisn'] ?? r['noPeserta'] ?? r['studentCode'] ?? r['username'] ?? r['userCode'] ?? '').toString();
          }
        }
        if (sName.isEmpty) sName = '$cName #${k + 1}';
        classList.add({'name': sName, 'class': cName, 'nis': sNis});
        allItems.add({'name': sName, 'class': cName, 'nis': sNis});
      }
      classQueues.add(classList);
    }

    final seatData = List<Map<String, String>>.filled(roomCapacity, {'name': '', 'class': ''});

    if (arrangeMode == 'acak') {
      final shuffled = List<Map<String, String>>.from(allItems)..shuffle(Random(seed));
      for (int i = 0; i < shuffled.length && i < roomCapacity; i++) {
        seatData[i] = shuffled[i];
      }
    } else if (arrangeMode == 'zigzag') {
      final qIdx = List.filled(classQueues.length, 0);
      int qi = 0;
      for (int seat = 0; seat < roomCapacity; seat++) {
        int tried = 0;
        while (tried < classQueues.length) {
          final q = qi % classQueues.length;
          if (qIdx[q] < classQueues[q].length) {
            seatData[seat] = classQueues[q][qIdx[q]++];
            qi = q + 1;
            break;
          }
          qi++;
          tried++;
        }
        if (tried == classQueues.length) break;
      }
    } else {
      int seatIdx = 0;
      for (int q = 0; q < classQueues.length && seatIdx < roomCapacity; q++) {
        for (int k = 0; k < classQueues[q].length && seatIdx < roomCapacity; k++) {
          seatData[seatIdx++] = classQueues[q][k];
        }
      }
    }

    return seatData;
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  Helper: Abbreviate long student names for seat grid display
  // ─────────────────────────────────────────────────────────────────────────
  static String _abbreviateName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length <= 2) return name;
    return '${parts.first} ${parts.skip(1).map((p) => '${p[0]}.').join(' ')}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  PDF 3: Jadwal per Kelas (Legacy - backward compat)
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
    final theme = await _buildTheme();
    final doc = pw.Document(theme: theme);

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
    final theme = await _buildTheme();
    final doc = pw.Document(theme: theme);

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
        accentColor: _slate,
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
                left: pw.BorderSide(color: _slate, width: 3),
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
