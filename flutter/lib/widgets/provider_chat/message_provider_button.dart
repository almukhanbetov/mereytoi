import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../screens/provider_chat/provider_chat_screen.dart';
import '../../state/locale_provider.dart';

/// «Написать услугодателю» (Этап 11G brief section 2) — a second, distinct
/// channel from [AskManagerButton]'s "Спросить менеджера": this opens
/// [ProviderChatScreen], a direct thread with the service's own provider,
/// never MEREYTOI staff. Auth gating happens inside that screen itself
/// (same convention AskManagerButton already uses), so this button is
/// always tappable.
class MessageProviderButton extends StatelessWidget {
  const MessageProviderButton({
    super.key,
    required this.providerId,
    required this.providerName,
    required this.locale,
    this.providerAvatarUrl,
    this.listingId,
    this.listingName,
    this.listingPrice,
  });

  final int providerId;
  final String providerName;
  final AppLocale locale;
  final String? providerAvatarUrl;
  final int? listingId;
  final String? listingName;
  final int? listingPrice;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ProviderChatScreen(
            providerId: providerId,
            peerName: providerName,
            peerAvatarUrl: providerAvatarUrl,
            listingId: listingId,
            listingName: listingName,
            listingPrice: listingPrice,
          ),
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 15),
      label: Text(
        t(
          locale,
          ru: 'Написать услугодателю',
          kz: 'Қызмет көрсетушіге жазу',
          en: 'Message the provider',
        ),
      ),
    );
  }
}
