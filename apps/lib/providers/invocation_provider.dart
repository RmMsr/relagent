import 'package:flutter_riverpod/flutter_riverpod.dart';

class InvocationNotifier extends Notifier<String?> {
  final String? _initialText;

  InvocationNotifier([this._initialText]);

  @override
  String? build() => _initialText;

  void set(String text) {
    state = text;
  }

  String? consume() {
    final text = state;
    state = null;
    return text;
  }
}

final invocationProvider = NotifierProvider<InvocationNotifier, String?>(
  InvocationNotifier.new,
);
