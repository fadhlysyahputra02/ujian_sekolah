import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

/// Realtime Network Connectivity & Internet Health Monitoring Service.
class NetworkService extends ChangeNotifier {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal() {
    _initNetworkMonitoring();
  }

  bool _isOnline = true;
  bool _wasOffline = false;
  bool _showReconnectedBanner = false;
  Timer? _checkTimer;
  Timer? _reconnectedTimer;

  bool get isOnline => _isOnline;
  bool get showReconnectedBanner => _showReconnectedBanner;

  void _initNetworkMonitoring() {
    _checkConnection();
    _checkTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _checkConnection();
    });
  }

  Future<void> _checkConnection() async {
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
      notifyListeners();
    }
  }

  /// Manually trigger an immediate connection test
  Future<void> forceCheck() async {
    await _checkConnection();
  }

  @override
  void dispose() {
    _checkTimer?.cancel();
    _reconnectedTimer?.cancel();
    super.dispose();
  }
}
