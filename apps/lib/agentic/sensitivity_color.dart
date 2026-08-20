import 'package:agentic_client/agentic_client.dart';
import 'package:flutter/material.dart';

/// UI-side color mapping for [SensitivityLevel] — kept out of the pure-Dart
/// `agentic_client` package since [Color] is a Flutter type.
extension SensitivityLevelColor on SensitivityLevel {
  Color get color => switch (this) {
    SensitivityLevel.openInformation => Colors.green,
    SensitivityLevel.specific => Colors.teal,
    SensitivityLevel.personal => Colors.orange,
    SensitivityLevel.confidential => Colors.deepOrange,
    SensitivityLevel.internal => Colors.red,
  };
}
