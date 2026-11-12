import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../state/promotion_provider.dart';

/// Counts an ad impression only when the card was really seen: at least
/// half of it on screen for [minVisible] without interruption. Scrolling
/// past quickly doesn't count; the server drops repeats and own views.
class AdImpressionTracker extends ConsumerStatefulWidget {
  const AdImpressionTracker({
    super.key,
    required this.promotionId,
    required this.child,
  });

  final int promotionId;
  final Widget child;

  static const minVisible = Duration(seconds: 1);
  static const minFraction = 0.5;

  @override
  ConsumerState<AdImpressionTracker> createState() =>
      _AdImpressionTrackerState();
}

class _AdImpressionTrackerState extends ConsumerState<AdImpressionTracker> {
  Timer? _timer;
  bool _sent = false;

  void _onVisibility(VisibilityInfo info) {
    if (_sent || !mounted) return;
    if (info.visibleFraction >= AdImpressionTracker.minFraction) {
      _timer ??= Timer(AdImpressionTracker.minVisible, () {
        if (!mounted) return;
        _sent = true;
        ref.read(adTrackerProvider).impression(widget.promotionId);
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VisibilityDetector(
      key: ValueKey('ad-visibility-${widget.promotionId}'),
      onVisibilityChanged: _onVisibility,
      child: widget.child,
    );
  }
}
