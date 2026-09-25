import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// The one bottom-sheet shell every restaurant-management add/edit form
/// uses (hall/menu/section/item/extra) — drag handle, title, scrollable
/// form body, inline error, sticky save button. Mirrors the exact
/// surfaceElevated/rounded-top/SafeArea/keyboard-inset shell
/// `CreateEventSheet` already established, pulled out once here instead of
/// being re-typed five times.
class FormSheetScaffold extends StatelessWidget {
  const FormSheetScaffold({
    super.key,
    required this.title,
    required this.formKey,
    required this.children,
    required this.onSave,
    required this.saving,
    this.error,
    this.saveLabel,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;
  final String? error;
  final String? saveLabel;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
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
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: colors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(title, style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: AppSpacing.md),
                    ...children,
                    if (error != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        error!,
                        style: TextStyle(color: colors.error, fontSize: 13),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving ? null : onSave,
                        child: saving
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: colors.onGold,
                                ),
                              )
                            : Text(saveLabel ?? 'Сохранить'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A generic "delete this?" confirm sheet — reused by hall/menu/section/
/// item/extra delete actions instead of five near-identical dialogs.
class ConfirmDeleteSheet extends StatelessWidget {
  const ConfirmDeleteSheet({
    super.key,
    required this.title,
    required this.confirmLabel,
    required this.cancelLabel,
  });

  final String title;
  final String confirmLabel;
  final String cancelLabel;

  static Future<bool> show(
    BuildContext context, {
    required String title,
    String confirmLabel = 'Удалить',
    String cancelLabel = 'Отмена',
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => ConfirmDeleteSheet(
        title: title,
        confirmLabel: confirmLabel,
        cancelLabel: cancelLabel,
      ),
    );
    return result ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.md),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.error,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(confirmLabel),
                ),
                const SizedBox(height: AppSpacing.xs),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(cancelLabel),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
