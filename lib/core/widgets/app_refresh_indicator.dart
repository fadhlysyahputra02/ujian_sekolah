import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// A custom Pull-To-Refresh indicator for Mobile Student views.
/// Displays a floating top banner with the App Logo (School Icon), spinning animation,
/// status text ("Memuat data terbaru..."), and a guaranteed minimum visual delay
/// so the user clearly experiences the refresh action.
class AppRefreshIndicator extends StatefulWidget {
  final Future<void> Function() onRefresh;
  final Widget child;

  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  @override
  State<AppRefreshIndicator> createState() => _AppRefreshIndicatorState();
}

class _AppRefreshIndicatorState extends State<AppRefreshIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _rotationAnim;

  bool _isRefreshing = false;
  bool _isCompleted = false;
  double _dragOffset = 0.0;
  static const double _refreshThreshold = 65.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _rotationAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.linear),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _triggerRefresh() async {
    if (_isRefreshing) return;
    final stopwatch = Stopwatch()..start();

    setState(() {
      _isRefreshing = true;
      _isCompleted = false;
      _dragOffset = _refreshThreshold;
    });
    _animController.repeat();

    try {
      await widget.onRefresh();
    } finally {
      // Guarantee at least 800ms animation duration so user sees the refresh status
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 800) {
        await Future.delayed(Duration(milliseconds: 800 - elapsed));
      }

      if (mounted) {
        setState(() {
          _isCompleted = true;
        });
        await Future.delayed(const Duration(milliseconds: 400));
      }

      if (mounted) {
        _animController.stop();
        _animController.reset();
        setState(() {
          _isRefreshing = false;
          _isCompleted = false;
          _dragOffset = 0.0;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final double pullRatio = (_dragOffset / _refreshThreshold).clamp(0.0, 1.0);
    final bool showHeader = _dragOffset > 10 || _isRefreshing;

    return NotificationListener<ScrollNotification>(
      onNotification: (ScrollNotification notification) {
        if (_isRefreshing) return false;

        if (notification is ScrollUpdateNotification) {
          if (notification.metrics.pixels < 0) {
            setState(() {
              _dragOffset = (-notification.metrics.pixels).clamp(0.0, 100.0);
            });
          } else if (_dragOffset > 0 && notification.metrics.pixels >= 0) {
            setState(() {
              _dragOffset = 0.0;
            });
          }
        } else if (notification is OverscrollNotification) {
          if (notification.overscroll < 0) {
            setState(() {
              _dragOffset = (_dragOffset - notification.overscroll).clamp(0.0, 100.0);
            });
          }
        } else if (notification is ScrollEndNotification) {
          if (_dragOffset >= _refreshThreshold && !_isRefreshing) {
            _triggerRefresh();
          } else if (!_isRefreshing) {
            setState(() {
              _dragOffset = 0.0;
            });
          }
        }
        return false;
      },
      child: Stack(
        children: [
          // Content with top margin when refreshing to create a clear physical gap/pause
          AnimatedPadding(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(top: _isRefreshing ? 54.0 : 0.0),
            child: widget.child,
          ),

          // Floating Refresh Status Banner
          if (showHeader)
            Positioned(
              top: _isRefreshing ? 12.0 : (12.0 + (_dragOffset * 0.15)),
              left: 0,
              right: 0,
              child: Center(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: pullRatio,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A), // Slate 900
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(
                        color: _isCompleted
                            ? const Color(0xFF10B981)
                            : const Color(0xFF6366F1).withValues(alpha: 0.6),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                          blurRadius: 18,
                          spreadRadius: 2,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // App Logo Icon Badge
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isCompleted
                                  ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                  : [const Color(0xFF6366F1), const Color(0xFF4F46E5)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: _isCompleted
                              ? const Icon(
                                  Icons.check_rounded,
                                  size: 16,
                                  color: Colors.white,
                                )
                              : RotationTransition(
                                  turns: _isRefreshing
                                      ? _rotationAnim
                                      : AlwaysStoppedAnimation(pullRatio * 0.5),
                                  child: const Icon(
                                    Icons.school_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        // Status Text
                        Text(
                          _isCompleted
                              ? 'Berhasil Diperbarui!'
                              : (_isRefreshing
                                  ? 'Memuat data terbaru...'
                                  : (pullRatio >= 1.0 ? 'Lepaskan untuk refresh' : 'Tarik ke bawah...')),
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
