import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class ConnectivityService {
  Future<bool> isUnmetered();
  Stream<bool> get onUnmeteredChanged;
  void dispose();
}

class DefaultConnectivityService implements ConnectivityService {
  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool? _lastValue;

  DefaultConnectivityService({Connectivity? connectivity})
      : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(
      (results) {
        final unmetered = isResultsUnmetered(results);
        if (_lastValue != unmetered) {
          _lastValue = unmetered;
          if (!_controller.isClosed) {
            _controller.add(unmetered);
          }
        }
      },
      onError: (e) {
        if (kDebugMode) {
          print('Connectivity stream error: $e');
        }
      },
    );
  }

  static bool isResultsUnmetered(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    if (results.contains(ConnectivityResult.wifi) ||
        results.contains(ConnectivityResult.ethernet)) {
      return true;
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return false;
    }
    if (results.contains(ConnectivityResult.vpn) ||
        results.contains(ConnectivityResult.other)) {
      return true;
    }
    return false;
  }

  @override
  Future<bool> isUnmetered() async {
    try {
      final results = await _connectivity.checkConnectivity();
      final unmetered = isResultsUnmetered(results);
      _lastValue = unmetered;
      return unmetered;
    } catch (e) {
      if (kDebugMode) {
        print('Connectivity check failed: $e');
      }
      return _lastValue ?? false; // Fail-closed to protect user data quota
    }
  }

  @override
  Stream<bool> get onUnmeteredChanged => _controller.stream;

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _controller.close();
  }
}

class MockConnectivityService implements ConnectivityService {
  bool _isUnmetered;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  MockConnectivityService({bool initialIsUnmetered = true})
      : _isUnmetered = initialIsUnmetered;

  bool get isUnmeteredConnection => _isUnmetered;

  set isUnmeteredConnection(bool value) {
    _isUnmetered = value;
    if (!_controller.isClosed) {
      _controller.add(value);
    }
  }

  void setUnmetered(bool value) {
    isUnmeteredConnection = value;
  }

  @override
  Future<bool> isUnmetered() async => _isUnmetered;

  @override
  Stream<bool> get onUnmeteredChanged => _controller.stream;

  @override
  void dispose() {
    _controller.close();
  }
}

const String kWaitingForUnmeteredMessage = 'Waiting for unmetered Wi-Fi connection';

bool isWaitingForUnmetered(String? error) {
  if (error == null || error.isEmpty) return false;
  return error == kWaitingForUnmeteredMessage ||
      (error.toLowerCase().contains('unmetered') && error.toLowerCase().contains('wi-fi'));
}
