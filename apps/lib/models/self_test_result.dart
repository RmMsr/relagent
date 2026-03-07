enum SelfTestStatus { pending, running, ok, warning, error }

class SelfTestResult {
  final String id;
  final String label;
  final SelfTestStatus status;
  final String? detail;

  const SelfTestResult({
    required this.id,
    required this.label,
    required this.status,
    this.detail,
  });

  SelfTestResult copyWith({
    String? id,
    String? label,
    SelfTestStatus? status,
    String? detail,
  }) {
    return SelfTestResult(
      id: id ?? this.id,
      label: label ?? this.label,
      status: status ?? this.status,
      detail: detail ?? this.detail,
    );
  }
}
