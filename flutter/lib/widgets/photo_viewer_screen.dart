import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import 'network_image_box.dart';

/// Full-screen photo viewer — Этап 10Б-Б1 (brief section 5): tapping a
/// listing/hall photo now actually opens it full-screen with pinch-to-zoom,
/// swiping between photos, a page counter, and a close button. Built on
/// `InteractiveViewer` (part of the Flutter SDK) rather than pulling in a
/// gallery package — no new dependency needed for "zoom that's justified
/// and already supported."
///
/// `panEnabled: false` on each page's `InteractiveViewer` is deliberate:
/// one-finger *panning* stays the `PageView`'s job (swipe to the next
/// photo); pinch-to-zoom (a two-finger scale gesture) is unaffected. A
/// `WidgetTester.drag()` in a test can make this look like the two
/// recognizers are fighting over a plain one-finger drag — that's an
/// artifact of `drag()`'s instantaneous synthetic gesture, not a real
/// conflict; `WidgetTester.fling()` (and a real touchscreen) resolve it
/// correctly, which is what this file's own tests use.
///
/// `imageUrls` are raw API paths (not yet resolved through
/// `ApiConfig.mediaUrl`) so this can be opened directly from a `Listing`'s
/// own `imageUrls`/a hall's `imageUrls` without every caller re-deriving
/// full URLs first.
class PhotoViewerScreen extends StatefulWidget {
  const PhotoViewerScreen({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  final List<String> imageUrls;
  final int initialIndex;

  static Future<void> open(
    BuildContext context, {
    required List<String> imageUrls,
    int initialIndex = 0,
  }) {
    if (imageUrls.isEmpty) return Future.value();
    return Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (context, animation, _) => FadeTransition(
          opacity: animation,
          child: PhotoViewerScreen(
            imageUrls: imageUrls,
            initialIndex: initialIndex,
          ),
        ),
      ),
    );
  }

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) => InteractiveViewer(
              panEnabled: false,
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: NetworkImageBox(
                  url: ApiConfig.mediaUrl(widget.imageUrls[i]),
                  borderRadius: 0,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  if (widget.imageUrls.length > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${_index + 1} / ${widget.imageUrls.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    )
                  else
                    const SizedBox(width: 40),
                  const SizedBox(width: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}
