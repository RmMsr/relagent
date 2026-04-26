import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:relagent/agentic/models.dart';

void main() {
  group('SensitivityLevel', () {
    test('fromValue returns correct level', () {
      expect(SensitivityLevel.fromValue(1), SensitivityLevel.openInformation);
      expect(SensitivityLevel.fromValue(2), SensitivityLevel.specific);
      expect(SensitivityLevel.fromValue(3), SensitivityLevel.personal);
      expect(SensitivityLevel.fromValue(4), SensitivityLevel.confidential);
      expect(SensitivityLevel.fromValue(5), SensitivityLevel.internal);
    });

    test('fromValue defaults to personal for unknown values', () {
      expect(SensitivityLevel.fromValue(99), SensitivityLevel.personal);
    });

    test('fromName handles engine enum names', () {
      expect(
        SensitivityLevel.fromName('OpenInformation'),
        SensitivityLevel.openInformation,
      );
      expect(SensitivityLevel.fromName('Specific'), SensitivityLevel.specific);
      expect(SensitivityLevel.fromName('Personal'), SensitivityLevel.personal);
      expect(
        SensitivityLevel.fromName('Confidential'),
        SensitivityLevel.confidential,
      );
      expect(SensitivityLevel.fromName('Internal'), SensitivityLevel.internal);
    });

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

  group('AgenticMessage.fromJson', () {
    test('parses system role with approvals', () {
      final json = {
        'role': 'system',
        'sequence_id': 5,
        'timestamp': '2024-01-15T10:00:00Z',
        'notification': 'Additional permissions required',
        'approvals': [
          {
            'id': 'abc-123',
            'type': 'data/out',
            'component': 'web_search',
            'purpose': "Searching the web for 'flutter'",
            'allowed_parameters': {'query': 'flutter'},
            'sensitivity': 3,
            'granted': false,
          },
        ],
      };

      final msg = AgenticMessage.fromJson(json);

      expect(msg.role, AgenticRole.system);
      expect(msg.id, 5);
      expect(msg.notification, 'Additional permissions required');
      expect(msg.approvals, isNotNull);
      expect(msg.approvals!.length, 1);

      final approval = msg.approvals!.first;
      expect(approval.id, 'abc-123');
      expect(approval.type, ApprovalType.outgoingData);
      expect(approval.component, 'web_search');
      expect(approval.purpose, "Searching the web for 'flutter'");
      expect(approval.sensitivity, SensitivityLevel.personal);
      expect(approval.granted, false);
      expect(approval.resolution, ApprovalResolution.pending);
    });

    test('parses system role with granted approval', () {
      final json = {
        'role': 'system',
        'approvals': [
          {
            'id': 'abc-123',
            'type': 'data/out',
            'purpose': 'test',
            'granted': true,
          },
        ],
      };

      final msg = AgenticMessage.fromJson(json);
      expect(msg.approvals!.first.resolution, ApprovalResolution.granted);
    });

    test('parses system role with notification only', () {
      final json = {
        'role': 'system',
        'notification': 'Session sensitivity changed',
      };

      final msg = AgenticMessage.fromJson(json);

      expect(msg.role, AgenticRole.system);
      expect(msg.notification, 'Session sensitivity changed');
      expect(msg.approvals, isNull);
      expect(msg.text, 'Session sensitivity changed');
    });

    test('parses user and assistant roles unchanged', () {
      final userJson = {
        'role': 'user',
        'content': 'Hello',
      };
      final assistantJson = {
        'role': 'assistant',
        'content': 'Hi there',
      };

      final user = AgenticMessage.fromJson(userJson);
      final assistant = AgenticMessage.fromJson(assistantJson);

      expect(user.role, AgenticRole.user);
      expect(user.text, 'Hello');
      expect(user.approvals, isNull);

      expect(assistant.role, AgenticRole.assistant);
      expect(assistant.text, 'Hi there');
      expect(assistant.approvals, isNull);
    });

    test('handles sensitivity as string name', () {
      final json = {
        'role': 'system',
        'approvals': [
          {
            'id': 'abc-123',
            'type': 'data/out',
            'purpose': 'test',
            'sensitivity': 'Confidential',
            'granted': false,
          },
        ],
      };

      final msg = AgenticMessage.fromJson(json);
      expect(
        msg.approvals!.first.sensitivity,
        SensitivityLevel.confidential,
      );
    });
  });

  group('GrantRequest', () {
    test('toJson produces correct structure without wildcard', () {
      final grant = GrantRequest(
        approvalType: ApprovalType.outgoingData,
        component: 'web_search',
        allowedParameters: {'query': 'test'},
        maxSensitivity: SensitivityLevel.personal,
      );

      final json = grant.toJson();

      expect(json['approval_type'], 'data/out');
      expect(json['component'], 'web_search');
      expect(json['allowed_parameters'], {'query': 'test'});
      expect(json['max_sensitivity'], 3);
      expect(json.containsKey('expires_at'), false);
      expect(json.containsKey('wildcard_parameter'), false);
    });

    test('toJson includes wildcard_parameter when set', () {
      final grant = GrantRequest(
        approvalType: ApprovalType.outgoingData,
        component: 'web_search',
        allowedParameters: {},
        wildcardParameter: 'query',
        maxSensitivity: SensitivityLevel.personal,
      );

      final json = grant.toJson();

      expect(json['wildcard_parameter'], 'query');
      expect(json['allowed_parameters'], <String, dynamic>{});
    });

    test('fromApproval creates matching grant without wildcard', () {
      final approval = ApprovalData(
        id: 'abc',
        type: ApprovalType.outgoingData,
        component: 'web_search',
        purpose: 'test',
        allowedParameters: {'query': 'flutter'},
        sensitivity: SensitivityLevel.personal,
      );

      final grant = GrantRequest.fromApproval(
        approval,
        maxSensitivity: SensitivityLevel.confidential,
      );

      expect(grant.approvalType, ApprovalType.outgoingData);
      expect(grant.component, 'web_search');
      expect(grant.allowedParameters, {'query': 'flutter'});
      expect(grant.wildcardParameter, isNull);
      expect(grant.maxSensitivity, SensitivityLevel.confidential);
    });

    test('fromApproval removes wildcarded key from allowedParameters', () {
      final approval = ApprovalData(
        id: 'abc',
        type: ApprovalType.outgoingData,
        component: 'web_search',
        purpose: 'test',
        allowedParameters: {'query': 'flutter', 'lang': 'en'},
        sensitivity: SensitivityLevel.personal,
      );

      final grant = GrantRequest.fromApproval(
        approval,
        maxSensitivity: SensitivityLevel.personal,
        wildcardParameter: 'query',
      );

      expect(grant.wildcardParameter, 'query');
      expect(grant.allowedParameters, {'lang': 'en'});
      expect(grant.allowedParameters.containsKey('query'), false);
    });
  });
}
