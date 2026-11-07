import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';

/// Shows what came back from the gallery before anything leaves the phone: the
/// system picker can return more than the person meant to add, and an upload is
/// public once saved. Returns the photos to upload, empty when cancelled.
Future<List<String>> confirmPickedPhotos(
  BuildContext context, {
  required AppLocale locale,
  required List<String> paths,
}) async {
  // Closing the sheet would otherwise hand focus back to the last text field,
  // reopening the keyboard and scrolling the form away from the new photos.
  FocusManager.instance.primaryFocus?.unfocus();
  final chosen = await showModalBottomSheet<List<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PickedPhotosSheet(locale: locale, paths: paths),
  );
  return chosen ?? const [];
}

class PickedPhotosSheet extends StatefulWidget {
  const PickedPhotosSheet({
    super.key,
    required this.locale,
    required this.paths,
  });

  final AppLocale locale;
  final List<String> paths;

  @override
  State<PickedPhotosSheet> createState() => _PickedPhotosSheetState();
}

class _PickedPhotosSheetState extends State<PickedPhotosSheet> {
  late final List<String> _paths = [...widget.paths];

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final count = _paths.length;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Выбрано фото: $count',
                    kz: 'Таңдалған фото: $count',
                    en: 'Photos selected: $count',
                  ),
                  key: const ValueKey('picked-photos-title'),
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  t(
                    locale,
                    ru: 'Проверьте и уберите лишние. Загрузятся только эти фото',
                    kz: 'Тексеріп, артығын алып тастаңыз. Тек осы фотолар жүктеледі',
                    en: 'Check them and remove any extras. Only these will be uploaded',
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Flexible(
                  child: SingleChildScrollView(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        const gap = AppSpacing.xs;
                        final size = (constraints.maxWidth - gap * 2) / 3;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (var i = 0; i < count; i++)
                              _thumb(context, i, size),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          key: const ValueKey('picked-photos-cancel'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 52),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            t(
                              locale,
                              ru: 'Отмена',
                              kz: 'Бас тарту',
                              en: 'Cancel',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: ElevatedButton(
                          key: const ValueKey('picked-photos-confirm'),
                          onPressed: count == 0
                              ? null
                              : () => Navigator.of(context).pop(_paths),
                          child: Text(
                            t(
                              locale,
                              ru: 'Загрузить',
                              kz: 'Жүктеу',
                              en: 'Upload',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, int i, double size) {
    final colors = context.mereytoiColors;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_paths[i]),
              key: ValueKey('picked-photo-$i'),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => ColoredBox(color: colors.surfaceSoft),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              key: ValueKey('picked-photo-remove-$i'),
              tooltip: t(
                widget.locale,
                ru: 'Убрать',
                kz: 'Алып тастау',
                en: 'Remove',
              ),
              onPressed: () => setState(() => _paths.removeAt(i)),
              icon: Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: Color(0x99000000),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
