import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Realtime Network Connectivity & Internet Health Monitoring Service.
class NetworkService extends ChangeNotifier with WidgetsBindingObserver {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;

  bool _isOnline = true;
  bool _wasOffline = false;
  bool _showReconnectedBanner = false;
  bool _suppressBanner = true; // Default suppress on app launch / resume
  bool _isAppActive = true;

  Timer? _checkTimer;
  Timer? _reconnectedTimer;
  Timer? _resumeTimer;

  NetworkService._internal() {
    WidgetsBinding.instance.addObserver(this);
    _initNetworkMonitoring();
  }

  bool get isOnline => _isOnline;
  bool get showReconnectedBanner => _showReconnectedBanner;
  bool get suppressBanner => _suppressBanner;

  void _initNetworkMonitoring() {
    // Initial check on app startup (suppressed so opening app doesn't show popup)
    _checkConnection(isSilent: true);

    // Initial grace period after app launch (5 seconds)
    _resumeTimer?.cancel();
    _resumeTimer = Timer(const Duration(seconds: 5), () {
      _suppressBanner = false;
      notifyListeners();
    });

    _checkTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkConnection();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isAppActive = false;
      _suppressBanner = true;
      _showReconnectedBanner = false;
      _reconnectedTimer?.cancel();
      notifyListeners();
    } else if (state == AppLifecycleState.resumed) {
      _isAppActive = false;
      _suppressBanner = true;
      _showReconnectedBanner = false;
      _reconnectedTimer?.cancel();
      notifyListeners();

      // Silent connection check upon waking up / opening app
      _checkConnection(isSilent: true);

      // Grace period of 5 seconds after waking up / resuming app
      _resumeTimer?.cancel();
      _resumeTimer = Timer(const Duration(seconds: 5), () {
        _isAppActive = true;
        _suppressBanner = false;
        notifyListeners();
      });
    }
  }

  Future<void> _checkConnection({bool isSilent = false}) async {
    bool previousOnline = _isOnline;
    bool currentOnline = true;

    try {
      if (kIsWeb) {
        currentOnline = true;
      } else {
        final result = await InternetAddress.lookup('dns.google').timeout(
          const Duration(seconds: 3),
        );
        currentOnline = result.isNotEmpty && result[0].rawAddress.isNotEmpty;
      }
    } catch (_) {
      currentOnline = false;
    }

    if (previousOnline != currentOnline) {
      _isOnline = currentOnline;

      if (isSilent || _suppressBanner || !_isAppActive) {
        if (!_isOnline) {
          _wasOffline = true;
        } else {
          _wasOffline = false;
        }
        _showReconnectedBanner = false;
      } else {
        if (!_isOnline) {
          _wasOffline = true;
          _showReconnectedBanner = false;
        } else if (_wasOffline) {
          _showReconnectedBanner = true;
          _wasOffline = false;
          _reconnectedTimer?.cancel();
          _reconnectedTimer = Timer(const Duration(seconds: 4), () {
            _showReconnectedBanner = false;
            notifyListeners();
          });
        }
      }
      notifyListeners();
    }
  }

  /// Manually trigger an immediate connection test (e.g. "Coba Lagi" button)
  Future<void> forceCheck() async {
    _suppressBanner = false;
    await _checkConnection();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _checkTimer?.cancel();
    _reconnectedTimer?.cancel();
    _resumeTimer?.cancel();
    super.dispose();
  }
}

