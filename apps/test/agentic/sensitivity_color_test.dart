import 'package:agentic_client/agentic_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/sensitivity_color.dart';

void main() {
  group('SensitivityLevelColor', () {
    test('each level has a distinct color', () {
      final colors = SensitivityLevel.values.map((l) => l.color).toSet();
      expect(colors.length, 5);
    });

    test('color mapping matches design spec', () {
      expect(SensitivityLevel.openInformation.color, Colors.green);
      expect(SensitivityLevel.specific.color, Colors.teal);
      expect(SensitivityLevel.personal.color, Colors.orange);
      expect(SensitivityLevel.confidential.color, Colors.deepOrange);
      expect(SensitivityLevel.internal.color, Colors.red);
    });
  });
}
