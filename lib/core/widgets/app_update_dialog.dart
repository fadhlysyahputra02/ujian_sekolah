import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/app_update_model.dart';

class AppUpdateDialog extends StatefulWidget {
  final AppUpdateInfo updateInfo;
  final String currentVersion;

  const AppUpdateDialog({
    super.key,
    required this.updateInfo,
    required this.currentVersion,
  });

  static Future<void> show(
    BuildContext context, {
    required AppUpdateInfo updateInfo,
    required String currentVersion,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: !updateInfo.forceUpdate,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (context) => PopScope(
        canPop: !updateInfo.forceUpdate,
        child: AppUpdateDialog(
          updateInfo: updateInfo,
          currentVersion: currentVersion,
        ),
      ),
    );
  }

  @override
  State<AppUpdateDialog> createState() => _AppUpdateDialogState();
}

class _AppUpdateDialogState extends State<AppUpdateDialog>
    with SingleTickerProviderStateMixin {
  static const MethodChannel _installerChannel =
      MethodChannel('com.sesicermat.sys_exam_school/app_installer');

  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _statusText = '';
  String? _errorMessage;
  bool _copied = false;
  StreamSubscription? _downloadSubscription;
  HttpClient? _httpClient;

  @override
  void dispose() {
    _downloadSubscription?.cancel();
    _httpClient?.close(force: true);
    super.dispose();
  }

  Future<void> _startDownloadAndInstall() async {
    if (kIsWeb || !Platform.isAndroid) {
      if (widget.updateInfo.apkUrl.isNotEmpty) {
        Clipboard.setData(ClipboardData(text: widget.updateInfo.apkUrl));
        setState(() {
          _copied = true;
          _errorMessage =
              'Auto-install langsung hanya tersedia pada perangkat Android APK. Tautan unduhan APK telah disalin ke papan klip!';
        });
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _copied = false);
        });
      } else {
        setState(() {
          _errorMessage =
              'Fitur auto-install hanya didukung pada aplikasi Android APK dan URL APK belum dikonfigurasi.';
        });
      }
      return;
    }

    if (widget.updateInfo.apkUrl.isEmpty) {
      setState(() {
        _errorMessage = 'Tautan (URL) file APK belum dikonfigurasi oleh administrator.';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _statusText = 'Menghubungkan ke server pembaruan...';
      _errorMessage = null;
    });

    try {
      final uri = Uri.parse(widget.updateInfo.apkUrl);
      _httpClient = HttpClient();
      _httpClient!.autoUncompress = true;
      _httpClient!.connectionTimeout = const Duration(seconds: 20);

      final request = await _httpClient!.getUrl(uri);
      request.headers.set('User-Agent', 'Mozilla/5.0 (Android; Mobile; rv:109.0)');
      
      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException(
            'Server mengembalikan kode status ${response.statusCode} (${response.reasonPhrase})');
      }

      final contentLength = response.contentLength;
      final tempDir = await getTemporaryDirectory();
      final sanitizedVersion = widget.updateInfo.latestVersion.replaceAll(RegExp(r'[^a-zA-Z0-9_\.]'), '_');
      final apkFile = File('${tempDir.path}/SesiCermat_v$sanitizedVersion.apk');

      if (await apkFile.exists()) {
        try {
          await apkFile.delete();
        } catch (_) {}
      }

      final fileSink = apkFile.openWrite();
      int receivedBytes = 0;

      final completer = Completer<void>();

      _downloadSubscription = response.listen(
        (List<int> chunk) {
          fileSink.add(chunk);
          receivedBytes += chunk.length;

          if (mounted) {
            setState(() {
              if (contentLength > 0) {
                _downloadProgress = (receivedBytes / contentLength).clamp(0.0, 1.0);
                final receivedMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                final totalMb = (contentLength / (1024 * 1024)).toStringAsFixed(1);
                _statusText = 'Mengunduh: $receivedMb MB / $totalMb MB (${(_downloadProgress * 100).toInt()}%)';
              } else {
                final receivedMb = (receivedBytes / (1024 * 1024)).toStringAsFixed(1);
                _statusText = 'Mengunduh: $receivedMb MB...';
              }
            });
          }
        },
        onDone: () async {
          await fileSink.flush();
          await fileSink.close();
          completer.complete();
        },
        onError: (e) async {
          await fileSink.close();
          completer.completeError(e);
        },
        cancelOnError: true,
      );

      await completer.future;

      if (!mounted) return;

      // Verifikasi ukuran file APK (harus > 1MB)
      final fileSize = await apkFile.length();
      if (fileSize < 1024 * 1024) {
        throw Exception('File APK yang diunduh tidak lengkap (${(fileSize / 1024).toStringAsFixed(1)} KB). Pastikan link APK valid.');
      }

      setState(() {
        _statusText = 'Membuka pemasang aplikasi Android...';
        _downloadProgress = 1.0;
      });

      // Jalankan pemasangan melalui native FileProvider
      final result = await _installerChannel.invokeMethod('installApk', {
        'filePath': apkFile.path,
      });

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusText = 'Pemasangan dimulai. Silakan konfirmasi di layar.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Gagal mengunduh atau memasang update: $e';
        _isDownloading = false;
      });
    }
  }

  List<String> _parseReleaseNotes(String rawNotes) {
    if (rawNotes.trim().isEmpty) {
      return ['Peningkatan performa dan stabilitas sistem aplikasi.'];
    }
    final lines = rawNotes
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (lines.isEmpty) {
      return ['Pembaruan versi terbaru untuk pengalaman ujian yang lebih baik.'];
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final bool isForced = widget.updateInfo.forceUpdate;
    final notes = _parseReleaseNotes(widget.updateInfo.releaseNotes);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1E1B4B).withValues(alpha: 0.22),
                blurRadius: 40,
                offset: const Offset(0, 20),
              ),
              BoxShadow(
                color: const Color(0xFF4F46E5).withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: const Color(0xFFE2E8F0),
              width: 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ══════════════════════════════════════════════════════════════
              // HERO HEADER DENGAN GRADASI PREMIUM & GLOW EFFECT
              // ══════════════════════════════════════════════════════════════
              Stack(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0xFF1E1B4B),
                          Color(0xFF312E81),
                          Color(0xFF4338CA),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Lingkaran Icon 3D Glassmorphism
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.28),
                              width: 1.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6366F1)
                                    .withValues(alpha: 0.4),
                                blurRadius: 24,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                          child: Center(
                            child: Container(
                              width: 52,
                              height: 52,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    Color(0xFF818CF8),
                                    Color(0xFF4F46E5),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                              child: const Icon(
                                Icons.rocket_launch_rounded,
                                size: 28,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Pill Kategori Status
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: isForced
                                ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                                : const Color(0xFF10B981).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isForced
                                  ? const Color(0xFFFCA5A5).withValues(alpha: 0.5)
                                  : const Color(0xFF6EE7B7).withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isForced
                                    ? Icons.priority_high_rounded
                                    : Icons.auto_awesome_rounded,
                                size: 13,
                                color: isForced
                                    ? const Color(0xFFFECACA)
                                    : const Color(0xFFA7F3D0),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isForced
                                    ? 'PEMBARUAN WAJIB'
                                    : 'VERSI BARU TERSEDIA',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Judul Modal
                        Text(
                          isForced
                              ? 'Pembaruan Diperlukan'
                              : 'Waktunya Memperbarui Aplikasi!',
                          style: GoogleFonts.inter(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tingkatkan aplikasi untuk fitur terbaru & performa maksimal',
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFFC7D2FE),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  // Tombol Tutup Silang (Hanya jika bukan force update)
                  if (!isForced && !_isDownloading)
                    Positioned(
                      top: 14,
                      right: 14,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => Navigator.of(context).pop(),
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.2),
                              ),
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),

              // ══════════════════════════════════════════════════════════════
              // KONTEN BODY: VERSI BADGE & CHANGELOG
              // ══════════════════════════════════════════════════════════════
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Version Comparison Card
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Versi Saat Ini
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'Versi Saat Ini',
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE2E8F0),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'v${widget.currentVersion}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: const Color(0xFF334155),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Panah Transisi
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFFC7D2FE),
                              ),
                            ),
                            child: const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                              color: Color(0xFF4F46E5),
                            ),
                          ),

                          // Versi Terbaru
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF10B981),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Versi Baru',
                                      style: GoogleFonts.inter(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF047857),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 3),
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFFEEF2FF),
                                        Color(0xFFE0E7FF),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: const Color(0xFFA5B4FC),
                                    ),
                                  ),
                                  child: Text(
                                    'v${widget.updateInfo.latestVersion}',
                                    style: GoogleFonts.inter(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF4338CA),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Header Changelog
                    Row(
                      children: [
                        const Icon(
                          Icons.format_list_bulleted_rounded,
                          size: 16,
                          color: Color(0xFF4F46E5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Catatan Pembaruan',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Box Changelog List
                    Container(
                      constraints: const BoxConstraints(maxHeight: 130),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: Scrollbar(
                        thumbVisibility: notes.length > 3,
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: notes.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) {
                            final line = notes[index].replaceFirst(
                                RegExp(r'^[-*•\d\.\s]+'), '');
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  margin: const EdgeInsets.only(top: 5),
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF6366F1),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    line.isEmpty ? notes[index] : line,
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: const Color(0xFF334155),
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),

                    // Pesan Error jika ada
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFFECACA),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              size: 18,
                              color: Color(0xFFDC2626),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF991B1B),
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 20),

                    // ══════════════════════════════════════════════════════════
                    // DOWNLOAD PROGRESS ATAU ACTION BUTTONS
                    // ══════════════════════════════════════════════════════════
                    if (_isDownloading) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFFC7D2FE),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation(
                                            Color(0xFF4F46E5)),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Mengunduh...',
                                      style: GoogleFonts.inter(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF312E81),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  '${(_downloadProgress * 100).toInt()}%',
                                  style: GoogleFonts.inter(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4338CA),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: LinearProgressIndicator(
                                value: _downloadProgress > 0
                                    ? _downloadProgress
                                    : null,
                                minHeight: 8,
                                backgroundColor: const Color(0xFFC7D2FE),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    Color(0xFF4F46E5)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _statusText,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: const Color(0xFF4338CA),
                              ),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      Row(
                        children: [
                          if (!isForced) ...[
                            Expanded(
                              flex: 1,
                              child: OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: const BorderSide(
                                    color: Color(0xFFCBD5E1),
                                    width: 1.2,
                                  ),
                                ),
                                child: Text(
                                  'Nanti Saja',
                                  style: GoogleFonts.inter(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            flex: isForced ? 1 : 2,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: const LinearGradient(
                                  colors: [
                                    Color(0xFF4F46E5),
                                    Color(0xFF6366F1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF4F46E5)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: _startDownloadAndInstall,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 13),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      _copied
                                          ? Icons.check_rounded
                                          : Icons.download_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _copied
                                          ? 'Link Tersalin!'
                                          : 'Perbarui Sekarang',
                                      style: GoogleFonts.inter(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

