// Models for the mobile admin panel — the JSON of the server's /api/admin
// endpoints (backend/internal/handlers/admin_users.go, admin_reports.go).
// Parsing is lenient: a missing field falls back to an empty value rather
// than failing the whole screen.

DateTime? _date(Object? v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

int _int(Object? v) => v is num ? v.toInt() : 0;

int? _intOrNull(Object? v) => v is num ? v.toInt() : null;

String _str(Object? v) => v is String ? v : '';

Map<String, dynamic> _map(Object? v) =>
    v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<Map<String, dynamic>> _list(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// One page of a paged admin list.
class AdminPage<T> {
  const AdminPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<T> items;
  final int total;
  final int page;
  final int perPage;

  bool get hasMore => page * perPage < total;
}

class AdminSummary {
  const AdminSummary({
    required this.reportsNew,
    required this.reportsInReview,
    required this.reportsMine,
    required this.reviewsPending,
    required this.recoveryRequestsPending,
    required this.supportChatsOpen,
    required this.eventRequestsWaiting,
    required this.blockedUsers,
    required this.hiddenListings,
  });

  final int reportsNew;
  final int reportsInReview;
  final int reportsMine;
  final int reviewsPending;
  final int recoveryRequestsPending;
  final int supportChatsOpen;
  final int eventRequestsWaiting;
  final int blockedUsers;
  final int hiddenListings;

  factory AdminSummary.fromJson(Map<String, dynamic> j) => AdminSummary(
    reportsNew: _int(j['reports_new']),
    reportsInReview: _int(j['reports_in_review']),
    reportsMine: _int(j['reports_mine']),
    reviewsPending: _int(j['reviews_pending']),
    recoveryRequestsPending: _int(j['recovery_requests_pending']),
    supportChatsOpen: _int(j['support_chats_open']),
    eventRequestsWaiting: _int(j['event_requests_waiting']),
    blockedUsers: _int(j['blocked_users']),
    hiddenListings: _int(j['hidden_listings']),
  );
}

class AdminBlock {
  const AdminBlock({
    required this.active,
    this.blockedAt,
    this.until,
    required this.reason,
  });

  final bool active;
  final DateTime? blockedAt;

  /// Null for an indefinite block.
  final DateTime? until;
  final String reason;

  factory AdminBlock.fromJson(Map<String, dynamic> j) => AdminBlock(
    active: j['active'] == true,
    blockedAt: _date(j['blocked_at']),
    until: _date(j['until']),
    reason: _str(j['reason']),
  );
}

class AdminProviderInfo {
  const AdminProviderInfo({
    required this.id,
    required this.displayName,
    required this.city,
    required this.phone,
    required this.whatsapp,
    required this.status,
  });

  final int id;
  final String displayName;
  final String city;
  final String phone;
  final String whatsapp;
  final String status;

  factory AdminProviderInfo.fromJson(Map<String, dynamic> j) =>
      AdminProviderInfo(
        id: _int(j['id']),
        displayName: _str(j['display_name']),
        city: _str(j['city']),
        phone: _str(j['phone']),
        whatsapp: _str(j['whatsapp']),
        status: _str(j['status']),
      );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.role,
    required this.status,
    this.createdAt,
    this.block,
    this.provider,
    required this.listingsCount,
  });

  final int id;
  final String name;
  final String email;
  final String phone;
  final String role;
  final String status;
  final DateTime? createdAt;
  final AdminBlock? block;
  final AdminProviderInfo? provider;
  final int listingsCount;

  bool get isAdmin => role == 'admin';
  bool get isBlocked => block?.active ?? false;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
    id: _int(j['id']),
    name: _str(j['name']),
    email: _str(j['email']),
    phone: _str(j['phone']),
    role: _str(j['role']),
    status: _str(j['status']),
    createdAt: _date(j['created_at']),
    block: j['block'] is Map ? AdminBlock.fromJson(_map(j['block'])) : null,
    provider: j['provider'] is Map
        ? AdminProviderInfo.fromJson(_map(j['provider']))
        : null,
    listingsCount: _int(j['listings_count']),
  );
}

class AdminListing {
  const AdminListing({
    required this.id,
    required this.categoryId,
    required this.nameRu,
    required this.city,
    required this.role,
    required this.isActive,
    this.moderationHiddenAt,
    required this.moderationReason,
    required this.publiclyVisible,
  });

  final int id;
  final int categoryId;
  final String nameRu;
  final String city;

  /// The user's role on this listing: owner | manager.
  final String role;

  /// The owner's own publish switch.
  final bool isActive;
  final DateTime? moderationHiddenAt;
  final String moderationReason;
  final bool publiclyVisible;

  bool get hiddenByAdmin => moderationHiddenAt != null;

  factory AdminListing.fromJson(Map<String, dynamic> j) => AdminListing(
    id: _int(j['id']),
    categoryId: _int(j['category_id']),
    nameRu: _str(j['name_ru']),
    city: _str(j['city']),
    role: _str(j['role']),
    isActive: j['is_active'] == true,
    moderationHiddenAt: _date(j['moderation_hidden_at']),
    moderationReason: _str(j['moderation_reason']),
    publiclyVisible: j['publicly_visible'] == true,
  );
}

class AdminAuditEvent {
  const AdminAuditEvent({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.action,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.changes,
    this.createdAt,
  });

  final int id;
  final int actorId;
  final String actorName;
  final String action;
  final String targetType;
  final int targetId;
  final String reason;
  final Map<String, dynamic> changes;
  final DateTime? createdAt;

  factory AdminAuditEvent.fromJson(Map<String, dynamic> j) => AdminAuditEvent(
    id: _int(j['id']),
    actorId: _int(j['actor_id']),
    actorName: _str(j['actor_name']),
    action: _str(j['action']),
    targetType: _str(j['target_type']),
    targetId: _int(j['target_id']),
    reason: _str(j['reason']),
    changes: _map(j['changes']),
    createdAt: _date(j['created_at']),
  );
}

class AdminUserDetail {
  const AdminUserDetail({
    required this.user,
    required this.listings,
    required this.history,
  });

  final AdminUser user;
  final List<AdminListing> listings;
  final List<AdminAuditEvent> history;

  factory AdminUserDetail.fromJson(Map<String, dynamic> j) => AdminUserDetail(
    user: AdminUser.fromJson(_map(j['user'])),
    listings: _list(j['listings']).map(AdminListing.fromJson).toList(),
    history: _list(j['history']).map(AdminAuditEvent.fromJson).toList(),
  );
}

class AdminPerson {
  const AdminPerson({required this.id, required this.name, this.email = ''});

  final int id;
  final String name;
  final String email;

  static AdminPerson? fromJsonOrNull(Object? v) {
    if (v is! Map) return null;
    final j = Map<String, dynamic>.from(v);
    return AdminPerson(
      id: _int(j['id']),
      name: _str(j['name']),
      email: _str(j['email']),
    );
  }
}

class AdminReportTarget {
  const AdminReportTarget({
    required this.exists,
    required this.title,
    required this.detail,
  });

  final bool exists;
  final String title;
  final Map<String, dynamic> detail;

  factory AdminReportTarget.fromJson(Map<String, dynamic> j) =>
      AdminReportTarget(
        exists: j['exists'] == true,
        title: _str(j['title']),
        detail: _map(j['detail']),
      );
}

class AdminReport {
  const AdminReport({
    required this.id,
    required this.reporterId,
    required this.targetType,
    required this.targetId,
    this.targetUserId,
    required this.reason,
    required this.details,
    required this.status,
    this.assigneeId,
    this.resolvedBy,
    this.resolvedAt,
    required this.resolution,
    this.createdAt,
    this.reporter,
    this.targetUser,
    required this.target,
    required this.openOnSameTarget,
  });

  final int id;
  final int reporterId;
  final String targetType;
  final int targetId;
  final int? targetUserId;
  final String reason;
  final String details;
  final String status;
  final int? assigneeId;
  final int? resolvedBy;
  final DateTime? resolvedAt;
  final String resolution;
  final DateTime? createdAt;
  final AdminPerson? reporter;
  final AdminPerson? targetUser;
  final AdminReportTarget target;
  final int openOnSameTarget;

  bool get isOpen => status == 'new' || status == 'in_review';

  factory AdminReport.fromJson(Map<String, dynamic> j) => AdminReport(
    id: _int(j['id']),
    reporterId: _int(j['reporter_id']),
    targetType: _str(j['target_type']),
    targetId: _int(j['target_id']),
    targetUserId: _intOrNull(j['target_user_id']),
    reason: _str(j['reason']),
    details: _str(j['details']),
    status: _str(j['status']),
    assigneeId: _intOrNull(j['assignee_id']),
    resolvedBy: _intOrNull(j['resolved_by']),
    resolvedAt: _date(j['resolved_at']),
    resolution: _str(j['resolution']),
    createdAt: _date(j['created_at']),
    reporter: AdminPerson.fromJsonOrNull(j['reporter']),
    targetUser: AdminPerson.fromJsonOrNull(j['target_user']),
    target: AdminReportTarget.fromJson(_map(j['target'])),
    openOnSameTarget: _int(j['open_on_same_target']),
  );
}

class AdminRelatedReport {
  const AdminRelatedReport({
    required this.id,
    required this.reason,
    required this.status,
    this.createdAt,
  });

  final int id;
  final String reason;
  final String status;
  final DateTime? createdAt;

  factory AdminRelatedReport.fromJson(Map<String, dynamic> j) =>
      AdminRelatedReport(
        id: _int(j['id']),
        reason: _str(j['reason']),
        status: _str(j['status']),
        createdAt: _date(j['created_at']),
      );
}

class AdminReportDetail {
  const AdminReportDetail({
    required this.report,
    required this.related,
    required this.history,
  });

  final AdminReport report;
  final List<AdminRelatedReport> related;
  final List<AdminAuditEvent> history;

  factory AdminReportDetail.fromJson(Map<String, dynamic> j) =>
      AdminReportDetail(
        report: AdminReport.fromJson(_map(j['report'])),
        related: _list(j['related']).map(AdminRelatedReport.fromJson).toList(),
        history: _list(j['history']).map(AdminAuditEvent.fromJson).toList(),
      );
}
