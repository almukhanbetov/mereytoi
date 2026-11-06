import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/locale_provider.dart';
import '../../profile/provider/my_services_screen.dart';
import '../../profile/restaurant_admin/restaurant_manage_screen.dart';
import '../business/my_business_screen.dart';
import '../../profile/provider/widgets/provider_service_form_sheet.dart';

/// "✓ Профиль создан" — shown once the onboarding published. Both buttons
/// lead to the existing provider screens: «Мои услуги», or «Мои услуги»
/// with the existing add-service form opened on top.
class ProviderOnboardingSuccessScreen extends ConsumerWidget {
  const ProviderOnboardingSuccessScreen({
    super.key,
    this.openBusiness = false,
    this.restaurantId,
  });

  /// Reached from the «Для бизнеса» mode: the main button opens
  /// «Мой бизнес» instead of «Мои услуги».
  final bool openBusiness;

  /// The listing just published is this restaurant: the main button goes on
  /// to its halls and menus.
  final int? restaurantId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;

    void openMyServices({bool addService = false}) {
      final navigator = Navigator.of(context);
      navigator.pushReplacement(
        MaterialPageRoute(builder: (_) => const MyServicesScreen()),
      );
      if (!addService) return;
      // Over the freshly pushed «Мои услуги», from the navigator's own
      // context (this screen's context is being replaced).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        openProviderServiceForm(navigator.context);
      });
    }

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSpacing.lg * 2,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        color: colors.goldPrimary.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.check_rounded,
                        size: 48,
                        color: colors.goldPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    t(
                      locale,
                      ru: 'Профиль создан',
                      kz: 'Профиль жасалды',
                      en: 'Profile created',
                    ),
                    textAlign: TextAlign.center,
                    style: textTheme.titleLarge?.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    t(
                      locale,
                      ru: 'Теперь клиенты смогут найти ваши услуги',
                      kz: 'Енді клиенттер қызметтеріңізді таба алады',
                      en: 'Clients can now find your services',
                    ),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  SizedBox(
                    height: 52,
                    child: restaurantId != null
                        ? ElevatedButton(
                            key: const ValueKey('success-restaurant-manage'),
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => RestaurantManageScreen(
                                      listingId: restaurantId!,
                                    ),
                                  ),
                                ),
                            child: Text(
                              t(
                                locale,
                                ru: 'Добавить залы и меню',
                                kz: 'Залдар мен мәзір қосу',
                                en: 'Add halls and menus',
                              ),
                            ),
                          )
                        : openBusiness
                        ? ElevatedButton(
                            key: const ValueKey('success-my-business'),
                            onPressed: () =>
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(
                                    builder: (_) => const MyBusinessScreen(),
                                  ),
                                ),
                            child: Text(
                              t(
                                locale,
                                ru: 'Открыть мой бизнес',
                                kz: 'Менің бизнесімді ашу',
                                en: 'Open my business',
                              ),
                            ),
                          )
                        : ElevatedButton(
                            key: const ValueKey('success-my-services'),
                            onPressed: openMyServices,
                            child: Text(
                              t(
                                locale,
                                ru: 'Мои услуги',
                                kz: 'Менің қызметтерім',
                                en: 'My services',
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      key: const ValueKey('success-add-service'),
                      onPressed: () => openMyServices(addService: true),
                      child: Text(
                        t(
                          locale,
                          ru: 'Добавить ещё услугу',
                          kz: 'Тағы қызмет қосу',
                          en: 'Add another service',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
