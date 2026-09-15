import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';
import 'comment_list.dart';

/// The per-candidate comment thread, opened from a candidate card's own
/// comment-count button — a tall bottom sheet rather than a full screen
/// push, so the shortlist underneath stays one tap away.
class CandidateCommentsSheet extends ConsumerWidget {
  const CandidateCommentsSheet({
    super.key,
    required this.eventId,
    required this.candidateId,
  });

  final int eventId;
  final int candidateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.mereytoiColors.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                t(locale, ru: 'Обсуждение услуги', kz: 'Қызметті талқылау'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: EventCommentList(
                eventId: eventId,
                candidateId: candidateId,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
