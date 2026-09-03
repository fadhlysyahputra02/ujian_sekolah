import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class GeneratePasswordDialog extends StatefulWidget {
  final String tempPassword;
  final String displayName;

  const GeneratePasswordDialog({
    super.key,
    required this.tempPassword,
    required this.displayName,
  });

  @override
  State<GeneratePasswordDialog> createState() => _GeneratePasswordDialogState();
}

class _GeneratePasswordDialogState extends State<GeneratePasswordDialog> {
  bool _isCopied = false;

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.tempPassword));
    setState(() => _isCopied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text('Kata sandi berhasil disalin!', style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
          ],
        ),
        backgroundColor: const Color(0xFF10B981),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _isCopied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(28.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Badge Header
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.key_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Password Sementara',
              style: GoogleFonts.inter(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF0F172A),
                letterSpacing: -0.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Description
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: GoogleFonts.inter(color: const Color(0xFF475569), fontSize: 13.5, height: 1.5),
                children: [
                  const TextSpan(text: 'Kata sandi sementara telah dibuat untuk '),
                  TextSpan(
                    text: widget.displayName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                  ),
                  const TextSpan(text: '. Harap simpan kata sandi ini sekarang karena hanya ditampilkan sekali.'),
                ],
              ),
            ),
            const SizedBox(height: 22),

            // Password Display Card
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'KATA SANDI BARU',
                          style: GoogleFonts.inter(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF64748B),
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          widget.tempPassword,
                          style: GoogleFonts.firaCode(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF4F46E5),
                            letterSpacing: 2.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: _isCopied ? const Color(0xFFECFDF5) : const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: _copyToClipboard,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                              size: 16,
                              color: _isCopied ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isCopied ? 'Tersalin' : 'Salin',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: _isCopied ? const Color(0xFF10B981) : const Color(0xFF4F46E5),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Button: OK
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4F46E5),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: Text(
                  'OK',
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 15, letterSpacing: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
