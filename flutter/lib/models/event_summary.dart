/// The bare JSON shape `GET /api/events/:id/summary` returns
/// (event_handler.go's `Summary`) — not a persisted model, so no `id`, and
/// deliberately never recomputed client-side: `spent`/`remaining` are
/// always derived live from selected candidates on the backend, so this
/// app only ever displays exactly what that endpoint already computed.
class EventSummary {
  const EventSummary({
    required this.budgetTotal,
    required this.spent,
    required this.remaining,
    required this.categoriesTotal,
    required this.categoriesCovered,
    required this.membersCount,
    required this.selectedCount,
    required this.shortlistedCount,
  });

  final int budgetTotal;
  final int spent;

  /// Can be negative — `int(budget_total) - int(spent)` on the Go side,
  /// signed on purpose so an over-budget event is visibly negative rather
  /// than clamped to 0.
  final int remaining;
  final int categoriesTotal;
  final int categoriesCovered;
  final int membersCount;
  final int selectedCount;
  final int shortlistedCount;

  factory EventSummary.fromJson(Map<String, dynamic> json) {
    return EventSummary(
      budgetTotal: json['budget_total'] as int? ?? 0,
      spent: json['spent'] as int? ?? 0,
      remaining: json['remaining'] as int? ?? 0,
      categoriesTotal: json['categories_total'] as int? ?? 0,
      categoriesCovered: json['categories_covered'] as int? ?? 0,
      membersCount: json['members_count'] as int? ?? 0,
      selectedCount: json['selected_count'] as int? ?? 0,
      shortlistedCount: json['shortlisted_count'] as int? ?? 0,
    );
  }
}
