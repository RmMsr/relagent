import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ConnectivityState {
  final ConnectivityResult connectivity;
  final bool hasInternet;

  const ConnectivityState({
    required this.connectivity,
    required this.hasInternet,
  });

  factory ConnectivityState.initial() {
    return const ConnectivityState(
      connectivity: ConnectivityResult.none,
      hasInternet: false,
    );
  }

  ConnectivityState copyWith({
    ConnectivityResult? connectivity,
    bool? hasInternet,
  }) {
    return ConnectivityState(
      connectivity: connectivity ?? this.connectivity,
      hasInternet: hasInternet ?? this.hasInternet,
    );
  }

  bool get isOnline => hasInternet;

  @override
  String toString() {
    return 'ConnectivityState(connectivity: $connectivity, hasInternet: $hasInternet)';
  }
}

final connectivityProvider =
    NotifierProvider<ConnectivityNotifier, ConnectivityState>(() {
      return ConnectivityNotifier();
    });

class ConnectivityNotifier extends Notifier<ConnectivityState> {
  late final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  ConnectivityState build() {
    _connectivity = Connectivity();

    // Initialize current connectivity status
    _initConnectivity();

    // Listen to connectivity changes
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _updateConnectivity,
    );

    // Dispose subscription when provider is disposed
    ref.onDispose(() {
      _connectivitySubscription?.cancel();
    });

    return ConnectivityState.initial();
  }

  Future<void> _initConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isNotEmpty) {
        _updateConnectivity(results);
      }
    } catch (e) {
      debugPrint('ConnectivityProvider: Error checking connectivity: $e');
    }
  }

  void _updateConnectivity(List<ConnectivityResult> results) {
    if (results.isEmpty) return;

    // Use the first (most reliable) connectivity result
    final result = results.first;
    final hasInternet = result != ConnectivityResult.none;
    state = state.copyWith(connectivity: result, hasInternet: hasInternet);

    debugPrint(
      'ConnectivityProvider: Connectivity changed to $result (hasInternet: $hasInternet)',
    );
  }
}
