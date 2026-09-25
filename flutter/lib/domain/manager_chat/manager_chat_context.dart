import '../../core/utils/format.dart';
import '../../state/locale_provider.dart';

/// The "what page were they on" context a Manager Chat opening can carry —
/// mirrors `AppProviders.jsx`'s `chatContext` shape exactly:
/// `{ listingId, listingName, listingPrice, categoryName, eventId,
/// eventTitle, ... }` plus the restaurant-variant fields
/// `RestaurantMenuCalculator.jsx`'s own `handleAskManager` adds
/// (hallName/menuName/menuPricePerGuest/guestCount/estimatedTotal).
///
/// Only `eventId`/`listingId` are ever sent to the backend
/// (`POST /api/manager-chat/start` — see `startConversationInput` in
/// event_candidate_handler... i.e. manager_chat_handler.go — has no
/// hall/menu/guest columns at all); everything else here exists only to
/// (a) render an on-screen context card and (b) get folded into the
/// *first* message's text via [managerChatContextLine], exactly like the
/// web widget's own `restaurantContextText`.
class ManagerChatContext {
  const ManagerChatContext({
    this.eventId,
    this.eventTitle,
    this.listingId,
    this.listingName,
    this.listingPrice,
    this.hallName,
    this.menuName,
    this.menuPricePerGuest,
    this.guestCount,
    this.estimatedTotal,
  });

  final int? eventId;
  final String? eventTitle;
  final int? listingId;
  final String? listingName;
  final int? listingPrice;
  final String? hallName;
  final String? menuName;
  final int? menuPricePerGuest;
  final int? guestCount;
  final int? estimatedTotal;
}

/// Exact Dart port of `FloatingManagerWidget.jsx`'s `restaurantContextText`
/// — only ever prefixed onto the *first* message of a brand-new thread
/// (see `ManagerChatScreen`'s own send logic), since it's the one thing
/// that actually survives into the conversation history a manager reads
/// later (the backend has no columns to persist hall/menu/guests on the
/// conversation itself).
String restaurantContextText(AppLocale locale, ManagerChatContext ctx) {
  if ((ctx.menuName == null || ctx.menuName!.isEmpty) &&
      (ctx.hallName == null || ctx.hallName!.isEmpty)) {
    return '';
  }
  final parts = <String>[];
  if (ctx.hallName != null && ctx.hallName!.isNotEmpty) {
    parts.add(
      '${t(locale, ru: "Зал", kz: "Зал", en: "Hall")}: ${ctx.hallName}',
    );
  }
  if (ctx.menuName != null && ctx.menuName!.isNotEmpty) {
    final price = ctx.menuPricePerGuest != null && ctx.menuPricePerGuest! > 0
        ? ' (${formatPrice(ctx.menuPricePerGuest!)}/${t(locale, ru: "чел.", kz: "адам", en: "guest")})'
        : '';
    parts.add(
      '${t(locale, ru: "Меню", kz: "Мәзір", en: "Menu")}: ${ctx.menuName}$price',
    );
  }
  if (ctx.guestCount != null && ctx.guestCount! > 0) {
    parts.add(
      '${ctx.guestCount} ${t(locale, ru: "гостей", kz: "қонақ", en: "guests")}',
    );
  }
  if (ctx.estimatedTotal != null && ctx.estimatedTotal! > 0) {
    parts.add('≈${formatPrice(ctx.estimatedTotal!)}');
  }
  return parts.isEmpty
      ? ''
      : '${t(locale, ru: "Контекст", kz: "Контекст", en: "Context")}: ${parts.join(', ')}. ';
}
