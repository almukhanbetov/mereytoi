import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../state/locale_provider.dart';

/// One command in a card's «⋮» menu. A null [onTap] shows it disabled, e.g.
/// «Выше» on the first row.
class ManageAction {
  const ManageAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.destructive = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool destructive;
}

/// The «⋮» on a hall, menu, section or item: keeps the card readable on a phone
/// while offering what the admin shows as a row of links. 48dp by default.
class ManageActionsButton extends StatelessWidget {
  const ManageActionsButton({
    super.key,
    required this.locale,
    required this.actions,
  });

  final AppLocale locale;
  final List<ManageAction> actions;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return PopupMenuButton<int>(
      tooltip: t(locale, ru: 'Действия', kz: 'Әрекеттер', en: 'Actions'),
      icon: Icon(Icons.more_vert_rounded, color: colors.textSecondary),
      onSelected: (i) => actions[i].onTap?.call(),
      itemBuilder: (context) => [
        for (var i = 0; i < actions.length; i++)
          PopupMenuItem<int>(
            value: i,
            enabled: actions[i].onTap != null,
            child: Row(
              children: [
                Icon(
                  actions[i].icon,
                  size: 20,
                  color: actions[i].destructive ? colors.error : null,
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    actions[i].label,
                    style: actions[i].destructive
                        ? TextStyle(color: colors.error)
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Runs a management command, showing a failure as a snackbar.
Future<void> runManaged(
  BuildContext context,
  AppLocale locale,
  Future<void> Function() command, {
  String? doneMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await command();
    if (doneMessage != null) {
      messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
    }
  } catch (err) {
    messenger.showSnackBar(
      SnackBar(content: Text(apiErrorMessage(locale, err))),
    );
  }
}

/// The standard «⋮» commands for moving a row, by [index] in its sorted list.
List<ManageAction> moveActions(
  AppLocale locale, {
  required int index,
  required int count,
  required void Function(int delta) onMove,
}) => [
  ManageAction(
    label: t(locale, ru: 'Выше', kz: 'Жоғары', en: 'Move up'),
    icon: Icons.arrow_upward_rounded,
    onTap: index > 0 ? () => onMove(-1) : null,
  ),
  ManageAction(
    label: t(locale, ru: 'Ниже', kz: 'Төмен', en: 'Move down'),
    icon: Icons.arrow_downward_rounded,
    onTap: index < count - 1 ? () => onMove(1) : null,
  ),
];

/// [list] with the row at [index] moved by [delta].
List<T> movedBy<T>(List<T> list, int index, int delta) {
  final out = [...list];
  out.insert(index + delta, out.removeAt(index));
  return out;
}
