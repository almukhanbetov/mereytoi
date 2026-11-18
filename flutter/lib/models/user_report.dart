/// One of the signed-in user's own reports (GET /api/reports/mine): what,
/// why, the status and dates — never the administrators' notes or ids.
class UserReport {
  const UserReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.targetTitle,
    required this.reason,
    required this.status,
    this.createdAt,
    this.resolvedAt,
  });

  final int id;
  final String targetType;
  final int targetId;
  final String targetTitle;
  final String reason;

  /// new | in_review | resolved | rejected
  final String status;
  final DateTime? createdAt;
  final DateTime? resolvedAt;

  factory UserReport.fromJson(Map<String, dynamic> j) => UserReport(
    id: (j['id'] as num?)?.toInt() ?? 0,
    targetType: j['target_type'] as String? ?? '',
    targetId: (j['target_id'] as num?)?.toInt() ?? 0,
    targetTitle: j['target_title'] as String? ?? '',
    reason: j['reason'] as String? ?? '',
    status: j['status'] as String? ?? '',
    createdAt: DateTime.tryParse(j['created_at'] as String? ?? '')?.toLocal(),
    resolvedAt: DateTime.tryParse(j['resolved_at'] as String? ?? '')?.toLocal(),
  );
}
