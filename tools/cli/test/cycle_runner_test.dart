import 'dart:convert';

import 'package:agentic_client/agentic_client.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:relagent_cli/cycle_runner.dart';
import 'package:test/test.dart';

Map<String, dynamic> _messageJson({
  required String id,
  required String role,
  String? content,
  bool isFinal = true,
  List<Map<String, dynamic>>? approvals,
}) {
  return {
    'message_id': id,
    'role': role,
    'content': content,
    'timestamp': '2025-01-01T00:00:00Z',
    'final': isFinal,
    if (approvals != null) 'approvals': approvals,
  };
}

void main() {
  const connection = EngineConnection(
    baseUrl: 'http://engine.test',
    authType: AuthType.none,
  );

  test('a cycle that settles immediately returns the final message', () async {
    final mockClient = MockClient((request) async {
      expect(request.url.path, '/api/v1/messages');
      return http.Response(
        jsonEncode({
          'session_id': 's-1',
          'message': _messageJson(
            id: 'm1',
            role: 'assistant',
            content: 'hello!',
          ),
        }),
        200,
      );
    });

    final result = await runCycle(
      connection: connection,
      sessionId: null,
      content: 'hi',
      decideApproval: (_) async => const ApprovalDecision.decline(),
      client: mockClient,
    );

    expect(result.text, 'hello!');
    expect(result.isFinal, isTrue);
  });

  test(
    'a pending approval is declined and the cycle continues until settled',
    () async {
      var continueCalls = 0;
      final declinedApprovalIds = <String>[];

      final mockClient = MockClient((request) async {
        if (request.url.path == '/api/v1/messages') {
          return http.Response(
            jsonEncode({
              'session_id': 's-1',
              'message': _messageJson(
                id: 'm1',
                role: 'system',
                isFinal: false,
                approvals: [
                  {
                    'id': 'a1',
                    'type': 'data/out',
                    'purpose': 'search the web',
                    'granted': null,
                  },
                ],
              ),
            }),
            200,
          );
        }

        if (request.url.path == '/api/v1/sessions/s-1/approvals/a1/decline') {
          declinedApprovalIds.add('a1');
          return http.Response('', 200);
        }

        if (request.url.path == '/api/v1/sessions/s-1/continue') {
          continueCalls++;
          return http.Response(
            jsonEncode({
              'session_id': 's-1',
              'message': _messageJson(
                id: 'm2',
                role: 'assistant',
                content: 'no search performed',
              ),
            }),
            200,
          );
        }

        fail('unexpected request: ${request.url}');
      });

      final result = await runCycle(
        connection: connection,
        sessionId: null,
        content: 'search cats',
        decideApproval: (_) async => const ApprovalDecision.decline(),
        client: mockClient,
      );

      expect(declinedApprovalIds, ['a1']);
      expect(continueCalls, 1);
      expect(result.text, 'no search performed');
      expect(result.isFinal, isTrue);
    },
  );

  test(
    'an existing session id continues rather than creating a new session',
    () async {
      final mockClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['session_id'], 'existing-session');
        return http.Response(
          jsonEncode({
            'session_id': 'existing-session',
            'message': _messageJson(id: 'm1', role: 'assistant', content: 'ok'),
          }),
          200,
        );
      });

      await runCycle(
        connection: connection,
        sessionId: 'existing-session',
        content: 'continuing our chat',
        decideApproval: (_) async => const ApprovalDecision.decline(),
        client: mockClient,
      );
    },
  );

  test(
    'onIntermediateMessage fires for non-final messages, not the final one',
    () async {
      final seen = <String>[];
      var callCount = 0;

      final mockClient = MockClient((request) async {
        callCount++;
        if (request.url.path == '/api/v1/messages') {
          return http.Response(
            jsonEncode({
              'session_id': 's-1',
              'message': _messageJson(
                id: 'm1',
                role: 'system',
                isFinal: false,
                approvals: [
                  {
                    'id': 'a1',
                    'type': 'data/out',
                    'purpose': 'search the web',
                    'granted': null,
                  },
                ],
              ),
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/sessions/s-1/approvals/a1/decline') {
          return http.Response('', 200);
        }
        return http.Response(
          jsonEncode({
            'session_id': 's-1',
            'message': _messageJson(
              id: 'm2',
              role: 'assistant',
              content: 'done',
            ),
          }),
          200,
        );
      });

      final result = await runCycle(
        connection: connection,
        sessionId: null,
        content: 'search cats',
        decideApproval: (_) async => const ApprovalDecision.decline(),
        onIntermediateMessage: (m) => seen.add(m.messageId),
        client: mockClient,
      );

      expect(seen, ['m1']);
      expect(result.messageId, 'm2');
      expect(callCount, 3);
    },
  );
}
