import 'package:agentic_client/agentic_client.dart';
import 'package:http/http.dart' as http;

/// Connection parameters shared by every engine call the CLI makes.
class EngineConnection {
  final String baseUrl;
  final AuthType authType;
  final String? apiKey;

  const EngineConnection({
    required this.baseUrl,
    required this.authType,
    this.apiKey,
  });
}

enum ApprovalDecisionKind { grant, decline }

class ApprovalDecision {
  final ApprovalDecisionKind kind;
  final GrantRequest? grant;

  const ApprovalDecision.grant(GrantRequest this.grant)
    : kind = ApprovalDecisionKind.grant;

  const ApprovalDecision.decline()
    : kind = ApprovalDecisionKind.decline,
      grant = null;
}

/// Called once per pending approval encountered mid-cycle.
typedef ApprovalDecider =
    Future<ApprovalDecision> Function(ApprovalData approval);

/// Called with each intermediate (non-final) message the cycle produces —
/// e.g. a system notification — before the loop moves on to resolve its
/// approvals and continue. Not called for the final settled message, which
/// [runCycle] returns instead.
typedef IntermediateMessageListener = void Function(AgenticMessage message);

/// Drives one full engine cycle: sends [content] (creating a new session
/// when [sessionId] is `null`, continuing the given session otherwise),
/// then repeatedly resolves pending approvals via [decideApproval] and
/// calls `/continue` until the cycle settles. Returns the final settled
/// message.
///
/// Shared by the `ask` and `chat` commands so both reuse the same protocol
/// sequence rather than reimplementing it.
Future<AgenticMessage> runCycle({
  required EngineConnection connection,
  required String? sessionId,
  required String content,
  required ApprovalDecider decideApproval,
  IntermediateMessageListener? onIntermediateMessage,
  http.Client? client,
}) async {
  var response = (await sendAgenticMessage(
    baseUrl: connection.baseUrl,
    sessionId: sessionId,
    content: content,
    authType: connection.authType,
    apiKey: connection.apiKey,
    // ignore: invalid_use_of_visible_for_testing_member
    client: client,
  )).message;

  final activeSessionId = response.sessionId;
  if (activeSessionId == null) {
    throw StateError('Engine response did not include a session id');
  }

  while (!response.isFinal) {
    onIntermediateMessage?.call(response);

    final pending = (response.approvals ?? const <ApprovalData>[]).where(
      (a) => a.resolution == ApprovalResolution.pending,
    );

    for (final approval in pending) {
      final decision = await decideApproval(approval);
      if (decision.kind == ApprovalDecisionKind.grant) {
        await grantSessionApproval(
          baseUrl: connection.baseUrl,
          sessionId: activeSessionId,
          approvalId: approval.id,
          grant: decision.grant,
          authType: connection.authType,
          apiKey: connection.apiKey,
          // ignore: invalid_use_of_visible_for_testing_member
          client: client,
        );
      } else {
        await declineSessionApproval(
          baseUrl: connection.baseUrl,
          sessionId: activeSessionId,
          approvalId: approval.id,
          authType: connection.authType,
          apiKey: connection.apiKey,
          // ignore: invalid_use_of_visible_for_testing_member
          client: client,
        );
      }
    }

    response = (await continueSession(
      baseUrl: connection.baseUrl,
      sessionId: activeSessionId,
      authType: connection.authType,
      apiKey: connection.apiKey,
      // ignore: invalid_use_of_visible_for_testing_member
      client: client,
    )).message;
  }

  return response;
}
