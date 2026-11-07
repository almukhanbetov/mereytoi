/// «Быстро создать меню из текста», the same rules as the admin's
/// RestaurantMenuImport.jsx: a line without a leading «-» or «•» starts a new
/// section, the ones with it are items of the latest section, and an optional
/// « — текст» after an item is its portion.
class MenuTextItem {
  const MenuTextItem(this.name, this.quantityText);

  final String name;
  final String quantityText;
}

class MenuTextSection {
  MenuTextSection(this.title);

  final String title;
  final List<MenuTextItem> items = [];
}

List<MenuTextSection> parseMenuText(String text) {
  final sections = <MenuTextSection>[];
  MenuTextSection? current;
  final bullet = RegExp(r'^[-•]\s*');
  for (final raw in text.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (bullet.hasMatch(line)) {
      current ??= () {
        final implicit = MenuTextSection('Без названия');
        sections.add(implicit);
        return implicit;
      }();
      final parts = line.replaceFirst(bullet, '').split(RegExp(r'\s+—\s+'));
      current.items.add(MenuTextItem(parts.first, parts.skip(1).join(' — ')));
    } else {
      current = MenuTextSection(line);
      sections.add(current);
    }
  }
  return sections;
}
