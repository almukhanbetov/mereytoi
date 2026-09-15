import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/event/event_status.dart';

void main() {
  group('eventRoleRank', () {
    test(
      'ranks owner > editor > viewer > unknown, mirroring models.RoleRank',
      () {
        expect(
          eventRoleRank(eventRoleOwner),
          greaterThan(eventRoleRank(eventRoleEditor)),
        );
        expect(
          eventRoleRank(eventRoleEditor),
          greaterThan(eventRoleRank(eventRoleViewer)),
        );
        expect(
          eventRoleRank(eventRoleViewer),
          greaterThan(eventRoleRank('nonsense')),
        );
      },
    );
  });

  group('requestIsEditable', () {
    test('draft and changes_requested are editable', () {
      expect(requestIsEditable(requestDraft), isTrue);
      expect(requestIsEditable(requestChangesRequested), isTrue);
    });

    test('every other status is not editable', () {
      for (final status in [
        requestSubmitted,
        requestInReview,
        requestApproved,
        requestRejected,
        requestCancelled,
      ]) {
        expect(requestIsEditable(status), isFalse, reason: status);
      }
    });
  });

  group('requestIsCancellable', () {
    test('approved/rejected/cancelled can no longer be cancelled', () {
      expect(requestIsCancellable(requestApproved), isFalse);
      expect(requestIsCancellable(requestRejected), isFalse);
      expect(requestIsCancellable(requestCancelled), isFalse);
    });

    test(
      'draft/submitted/in_review/changes_requested are still cancellable',
      () {
        for (final status in [
          requestDraft,
          requestSubmitted,
          requestInReview,
          requestChangesRequested,
        ]) {
          expect(requestIsCancellable(status), isTrue, reason: status);
        }
      },
    );
  });
}
