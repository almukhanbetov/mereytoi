import 'package:flutter/material.dart';

import 'comment_list.dart';

/// The event-wide "Обсуждение" tab — brief section 13. `candidateId: null`
/// scopes `EventCommentList` to the general discussion (not any one
/// candidate's own thread, that's `CandidateCommentsSheet`).
class DiscussionTab extends StatelessWidget {
  const DiscussionTab({super.key, required this.eventId, required this.myRole});

  final int eventId;
  final String myRole;

  @override
  Widget build(BuildContext context) {
    return EventCommentList(eventId: eventId);
  }
}
