import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/format.dart';
import '../../../models/category.dart';
import '../../../state/categories_provider.dart';
import '../../../state/city_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../state/provider_onboarding.dart';
import '../../../state/provider_provider.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_skeleton.dart';
import '../../../widgets/city_selector.dart';
import '../../../widgets/provider/provider_form_widgets.dart';
import '../../../widgets/services/services_category_grid.dart';
import 'provider_onboarding_success_screen.dart';

String _yearsLabel(AppLocale locale, int years) {
  switch (locale) {
    case AppLocale.kz:
      return '$years жыл';
    case AppLocale.en:
      return years == 1 ? '1 year' : '$years years';
    case AppLocale.ru:
      final mod10 = years % 10, mod100 = years % 100;
      final word = mod10 == 1 && mod100 != 11
          ? 'год'
          : mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)
          ? 'года'
          : 'лет';
      return '$years $word';
  }
}

/// «Стать услугодателем» — a six-step wizard: category, about you, city,
/// photos, first service, preview → «Опубликовать». One existing User
/// becomes a provider (no second account); a returning provider's
/// profile is prefilled and updated, never duplicated. See
/// [ProviderOnboardingController] for the publish/retry logic.
class ProviderOnboardingScreen extends ConsumerStatefulWidget {
  const ProviderOnboardingScreen({super.key});

  @override
  ConsumerState<ProviderOnboardingScreen> createState() =>
      _ProviderOnboardingScreenState();
}

class _ProviderOnboardingScreenState
    extends ConsumerState<ProviderOnboardingScreen> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _experience = TextEditingController();
  final _serviceName = TextEditingController();
  final _serviceDescription = TextEditingController();
  final _price = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prefillFromExistingProvider();
  }

  Future<void> _prefillFromExistingProvider() async {
    try {
      final existing = await ref.read(providerProfileProvider.future);
      if (existing == null || !mounted) return;
      final cities = await ref
          .read(citiesProvider.future)
          .catchError((_) => const <Never>[]);
      if (!mounted) return;
      final notifier = ref.read(providerOnboardingProvider.notifier);
      notifier.prefillFrom(existing, cities: cities);
      final s = ref.read(providerOnboardingProvider);
      if (_name.text.isEmpty) _name.text = s.displayName;
      if (_description.text.isEmpty) _description.text = s.description;
      if (_experience.text.isEmpty) _experience.text = s.experienceText;
    } catch (_) {
      // No profile info — the wizard simply starts empty.
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _experience,
      _serviceName,
      _serviceDescription,
      _price,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _onPrimary() async {
    final notifier = ref.read(providerOnboardingProvider.notifier);
    final s = ref.read(providerOnboardingProvider);
    FocusScope.of(context).unfocus();
    if (s.step < kOnboardingSteps - 1) {
      notifier.next();
      return;
    }
    final ok = await notifier.publish();
    if (!mounted) return;
    if (ok) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const ProviderOnboardingSuccessScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final s = ref.watch(providerOnboardingProvider);
    final notifier = ref.read(providerOnboardingProvider.notifier);
    final colors = context.mereytoiColors;
    final publishing = s.publishStatus == OnboardingPublishStatus.publishing;

    return PopScope(
      canPop: s.step == 0 && !publishing,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !publishing) notifier.back();
      },
      child: Scaffold(
        backgroundColor: colors.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: colors.backgroundPrimary,
          leading: IconButton(
            tooltip: t(locale, ru: 'Закрыть', kz: 'Жабу', en: 'Close'),
            icon: const Icon(Icons.close_rounded),
            onPressed: publishing ? null : () => Navigator.of(context).pop(),
          ),
          title: Text(
            t(
              locale,
              ru: 'Стать услугодателем',
              kz: 'Қызмет көрсетуші болу',
              en: 'Become a provider',
            ),
          ),
        ),
        body: Column(
          children: [
            _ProgressHeader(step: s.step, locale: locale),
            Expanded(
              child: IndexedStack(
                index: s.step,
                children: [
                  _CategoryStep(locale: locale),
                  _ProfileStep(
                    locale: locale,
                    name: _name,
                    description: _description,
                    experience: _experience,
                  ),
                  _CityStep(locale: locale),
                  _PhotosStep(locale: locale),
                  _ServiceStep(
                    locale: locale,
                    name: _serviceName,
                    description: _serviceDescription,
                    price: _price,
                  ),
                  _PreviewStep(locale: locale),
                ],
              ),
            ),
            _BottomBar(
              locale: locale,
              step: s.step,
              canProceed: s.canProceed,
              publishing: publishing,
              onBack: publishing ? null : notifier.back,
              onPrimary: _onPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  const _ProgressHeader({required this.step, required this.locale});

  final int step;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final n = step + 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              locale,
              ru: '$n из $kOnboardingSteps',
              kz: '$kOnboardingSteps қадамның $n-і',
              en: '$n of $kOnboardingSteps',
            ),
            key: const ValueKey('onboarding-progress-label'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.goldMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: n / kOnboardingSteps),
              duration: const Duration(milliseconds: 250),
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 6,
                color: colors.goldPrimary,
                backgroundColor: colors.surfaceSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.locale,
    required this.step,
    required this.canProceed,
    required this.publishing,
    required this.onBack,
    required this.onPrimary,
  });

  final AppLocale locale;
  final int step;
  final bool canProceed;
  final bool publishing;
  final VoidCallback? onBack;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final last = step == kOnboardingSteps - 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              if (step > 0) ...[
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    key: const ValueKey('onboarding-back'),
                    // The theme's buttons are full-width by default; this
                    // one shares the row with «Далее».
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(96, 52),
                    ),
                    onPressed: onBack,
                    child: Text(
                      t(locale, ru: 'Назад', kz: 'Артқа', en: 'Back'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    key: const ValueKey('onboarding-next'),
                    onPressed: canProceed && !publishing ? onPrimary : null,
                    child: publishing
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: colors.onGold,
                            ),
                          )
                        : Text(
                            last
                                ? t(
                                    locale,
                                    ru: 'Опубликовать',
                                    kz: 'Жариялау',
                                    en: 'Publish',
                                  )
                                : t(
                                    locale,
                                    ru: 'Далее',
                                    kz: 'Әрі қарай',
                                    en: 'Next',
                                  ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A step's scrollable body with its title and subtitle.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: textTheme.bodyMedium?.copyWith(
            color: context.mereytoiColors.textSecondary,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        ...children,
      ],
    );
  }
}

// ---------------------------------------------------------------- step 1

class _CategoryStep extends ConsumerWidget {
  const _CategoryStep({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final selected = ref.watch(
      providerOnboardingProvider.select((s) => s.categoryId),
    );
    final notifier = ref.read(providerOnboardingProvider.notifier);

    return _StepScaffold(
      title: t(
        locale,
        ru: 'Чем вы занимаетесь?',
        kz: 'Немен айналысасыз?',
        en: 'What do you do?',
      ),
      subtitle: t(
        locale,
        ru: 'Выберите основную категорию ваших услуг',
        kz: 'Қызметтеріңіздің негізгі санатын таңдаңыз',
        en: 'Choose the main category of your services',
      ),
      children: [
        categories.when(
          loading: () => GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: AppSpacing.xs,
            crossAxisSpacing: AppSpacing.xs,
            childAspectRatio: 2.3,
            children: List.generate(
              6,
              (_) => const AppSkeleton(height: 76, borderRadius: 16),
            ),
          ),
          error: (err, _) => AppErrorView(
            message: apiErrorMessage(locale, err),
            locale: locale,
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
          data: (list) => ProviderCategoryGrid(
            categories: list,
            selectedId: selected,
            locale: locale,
            onSelect: (c) => notifier.selectCategory(c.id),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- step 2

class _ProfileStep extends ConsumerWidget {
  const _ProfileStep({
    required this.locale,
    required this.name,
    required this.description,
    required this.experience,
  });

  final AppLocale locale;
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController experience;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final valid = ref.watch(
      providerOnboardingProvider.select((s) => s.experienceValid),
    );
    final notifier = ref.read(providerOnboardingProvider.notifier);
    return _StepScaffold(
      title: t(
        locale,
        ru: 'Расскажите о себе',
        kz: 'Өзіңіз туралы айтыңыз',
        en: 'Tell us about yourself',
      ),
      subtitle: t(
        locale,
        ru: 'Так клиенты узнают, кто вы и чем полезны',
        kz: 'Клиенттер сізді осылай таниды',
        en: 'This is how clients get to know you',
      ),
      children: [
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-name'),
          label: t(
            locale,
            ru: 'Имя или название',
            kz: 'Аты немесе атауы',
            en: 'Name or business name',
          ),
          hint: t(
            locale,
            ru: 'Например, Ерлан Тамада',
            kz: 'Мысалы, Ерлан Тамада',
            en: 'e.g. Erlan Host',
          ),
          controller: name,
          maxLength: 150,
          onChanged: notifier.setDisplayName,
        ),
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-description'),
          label: t(locale, ru: 'Описание', kz: 'Сипаттама', en: 'Description'),
          hint: t(
            locale,
            ru: 'Чем вы занимаетесь, ваш стиль, что входит в работу',
            kz: 'Немен айналысасыз, стиліңіз',
            en: 'What you do, your style, what is included',
          ),
          controller: description,
          maxLength: 1000,
          minLines: 3,
          maxLines: 6,
          onChanged: notifier.setDescription,
        ),
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-experience'),
          label: t(
            locale,
            ru: 'Опыт, лет',
            kz: 'Тәжірибе, жыл',
            en: 'Experience, years',
          ),
          hint: '0–$kMaxExperienceYears',
          controller: experience,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 2,
          errorText: valid
              ? null
              : t(
                  locale,
                  ru: 'От 0 до $kMaxExperienceYears',
                  kz: '0-ден $kMaxExperienceYears-ге дейін',
                  en: 'From 0 to $kMaxExperienceYears',
                ),
          onChanged: notifier.setExperience,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- step 3

class _CityStep extends ConsumerWidget {
  const _CityStep({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city = ref.watch(providerOnboardingProvider.select((s) => s.city));

    Future<void> pick() async {
      final picked = await showCityPicker(context, selectedId: city?.id);
      if (picked != null) {
        ref.read(providerOnboardingProvider.notifier).setCity(picked);
      }
    }

    return _StepScaffold(
      title: t(
        locale,
        ru: 'Где вы работаете?',
        kz: 'Қай жерде жұмыс істейсіз?',
        en: 'Where do you work?',
      ),
      subtitle: t(
        locale,
        ru: 'Клиенты увидят ваши услуги, выбрав этот город',
        kz: 'Клиенттер осы қаланы таңдағанда қызметтеріңізді көреді',
        en: 'Clients choosing this city will see your services',
      ),
      children: [
        ProviderPickerCard(
          tapKey: const ValueKey('onboarding-city'),
          icon: Icons.location_on_rounded,
          semanticLabel: t(
            locale,
            ru: 'Выбрать город',
            kz: 'Қаланы таңдау',
            en: 'Choose city',
          ),
          value: city?.name(locale),
          placeholder: t(
            locale,
            ru: 'Выберите город',
            kz: 'Қаланы таңдаңыз',
            en: 'Select city',
          ),
          onTap: pick,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- step 4

class _PhotosStep extends ConsumerWidget {
  const _PhotosStep({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(
      providerOnboardingProvider.select((s) => s.photos),
    );
    final notifier = ref.read(providerOnboardingProvider.notifier);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;

    Future<void> add() async {
      try {
        final paths = await ref.read(onboardingPhotoPickerProvider)();
        notifier.addPhotos(paths);
      } catch (_) {
        // Picker cancelled or unavailable — nothing to add.
      }
    }

    final addLabel = t(
      locale,
      ru: 'Добавить фото',
      kz: 'Фото қосу',
      en: 'Add photos',
    );

    return _StepScaffold(
      title: t(
        locale,
        ru: 'Добавьте фотографии',
        kz: 'Фотосуреттер қосыңыз',
        en: 'Add photos',
      ),
      subtitle: t(
        locale,
        ru: 'Покажите свою работу — с фото услугу выбирают чаще',
        kz: 'Жұмысыңызды көрсетіңіз — фотосы бар қызметті жиі таңдайды',
        en: 'Show your work — services with photos get chosen more often',
      ),
      children: [
        if (photos.isEmpty)
          DecoratedBox(
            decoration: providerCardDecoration(context),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: colors.goldPrimary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_photo_alternate_outlined,
                      size: 30,
                      color: colors.goldPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    t(
                      locale,
                      ru: 'Пока нет фото',
                      kz: 'Әзірге фото жоқ',
                      en: 'No photos yet',
                    ),
                    style: textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    t(
                      locale,
                      ru: 'До $kMaxOnboardingPhotos фото. Первое станет обложкой.',
                      kz: '$kMaxOnboardingPhotos фотоға дейін. Біріншісі мұқаба болады.',
                      en: 'Up to $kMaxOnboardingPhotos photos. The first is the cover.',
                    ),
                    textAlign: TextAlign.center,
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      key: const ValueKey('onboarding-add-photos'),
                      onPressed: add,
                      icon: const Icon(Icons.add_rounded),
                      label: Text(addLabel),
                    ),
                  ),
                ],
              ),
            ),
          )
        else ...[
          SizedBox(
            height: 128,
            child: ReorderableListView.builder(
              scrollDirection: Axis.horizontal,
              buildDefaultDragHandles: false,
              itemCount: photos.length,
              onReorderItem: notifier.movePhoto,
              itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                key: ValueKey('photo-${photos[i].path}'),
                index: i,
                child: Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: _PhotoThumb(
                    path: photos[i].path,
                    cover: i == 0,
                    locale: locale,
                    onRemove: () => notifier.removePhoto(i),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            t(
              locale,
              ru: 'Удерживайте фото, чтобы изменить порядок. Первое — обложка.',
              kz: 'Ретін өзгерту үшін фотоны басып тұрыңыз. Біріншісі — мұқаба.',
              en: 'Long-press a photo to reorder. The first one is the cover.',
            ),
            style: textTheme.bodySmall?.copyWith(color: colors.textSecondary),
          ),
          if (photos.length < kMaxOnboardingPhotos) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                key: const ValueKey('onboarding-add-photos'),
                onPressed: add,
                icon: const Icon(Icons.add_rounded),
                label: Text(addLabel),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _PhotoThumb extends StatelessWidget {
  const _PhotoThumb({
    required this.path,
    required this.cover,
    required this.locale,
    required this.onRemove,
  });

  final String path;
  final bool cover;
  final AppLocale locale;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return SizedBox(
      width: 128,
      height: 128,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: cover ? colors.goldPrimary : colors.border,
                  width: cover ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: colors.surfaceSoft,
                    child: Icon(Icons.image_outlined, color: colors.textMuted),
                  ),
                ),
              ),
            ),
          ),
          if (cover)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.goldPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  t(locale, ru: 'Обложка', kz: 'Мұқаба', en: 'Cover'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 2,
            right: 2,
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                tooltip: t(locale, ru: 'Удалить', kz: 'Жою', en: 'Remove'),
                onPressed: onRemove,
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
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- step 5

class _ServiceStep extends ConsumerWidget {
  const _ServiceStep({
    required this.locale,
    required this.name,
    required this.description,
    required this.price,
  });

  final AppLocale locale;
  final TextEditingController name;
  final TextEditingController description;
  final TextEditingController price;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(providerOnboardingProvider);
    final notifier = ref.read(providerOnboardingProvider.notifier);
    final category = _categoryOf(ref, s.categoryId);

    return _StepScaffold(
      title: t(
        locale,
        ru: 'Создайте первую услугу',
        kz: 'Алғашқы қызметті жасаңыз',
        en: 'Create your first service',
      ),
      subtitle: t(
        locale,
        ru: 'Её увидят клиенты в каталоге',
        kz: 'Оны клиенттер каталогта көреді',
        en: 'Clients will see it in the catalog',
      ),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (category != null)
              _InfoChip(
                icon: servicesCategoryIcon(category.slug),
                label: category.name(locale),
              ),
            if (s.city != null)
              _InfoChip(
                icon: Icons.location_on_rounded,
                label: s.city!.name(locale),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-service-name'),
          label: t(
            locale,
            ru: 'Название услуги',
            kz: 'Қызмет атауы',
            en: 'Service name',
          ),
          hint: t(
            locale,
            ru: 'Например, Проведение тоя',
            kz: 'Мысалы, Той жүргізу',
            en: 'e.g. Wedding hosting',
          ),
          controller: name,
          maxLength: 200,
          onChanged: notifier.setServiceName,
        ),
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-service-description'),
          label: t(locale, ru: 'Описание', kz: 'Сипаттама', en: 'Description'),
          controller: description,
          maxLength: 2000,
          minLines: 3,
          maxLines: 6,
          onChanged: notifier.setServiceDescription,
        ),
        ProviderTextField(
          fieldKey: const ValueKey('onboarding-price'),
          label: t(locale, ru: 'Цена', kz: 'Бағасы', en: 'Price'),
          hint: '50 000',
          suffixText: '₸',
          controller: price,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          maxLength: 9,
          onChanged: notifier.setPrice,
        ),
      ],
    );
  }
}

Category? _categoryOf(WidgetRef ref, int? id) {
  if (id == null) return null;
  for (final c in ref.watch(categoriesProvider).valueOrNull ?? const []) {
    if (c.id == id) return c;
  }
  return null;
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: colors.goldPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colors.goldPrimary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- step 6

class _PreviewStep extends ConsumerWidget {
  const _PreviewStep({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(providerOnboardingProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final category = _categoryOf(ref, s.categoryId);
    final cover = s.photos.isEmpty ? null : s.photos.first.path;
    final name = s.displayName.trim();

    return _StepScaffold(
      title: t(
        locale,
        ru: 'Предпросмотр',
        kz: 'Алдын ала қарау',
        en: 'Preview',
      ),
      subtitle: t(
        locale,
        ru: 'Так вас увидят клиенты. Всё можно изменить позже.',
        kz: 'Клиенттер сізді осылай көреді. Кейін өзгертуге болады.',
        en: 'This is how clients will see you. You can edit it later.',
      ),
      children: [
        // Profile
        DecoratedBox(
          decoration: providerCardDecoration(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: colors.goldPrimary.withValues(
                        alpha: 0.15,
                      ),
                      child: Text(
                        name.isEmpty
                            ? '?'
                            : name.characters.first.toUpperCase(),
                        style: textTheme.titleLarge?.copyWith(
                          color: colors.goldPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (category != null) category.name(locale),
                              if (s.city != null) s.city!.name(locale),
                              if (s.experienceYears != null)
                                t(
                                  locale,
                                  ru: 'опыт ${_yearsLabel(locale, s.experienceYears!)}',
                                  kz: 'тәжірибе ${_yearsLabel(locale, s.experienceYears!)}',
                                  en: '${_yearsLabel(locale, s.experienceYears!)} of experience',
                                ),
                            ].join(' · '),
                            key: const ValueKey('preview-meta'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (s.description.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    s.description.trim(),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        // First service
        DecoratedBox(
          decoration: providerCardDecoration(context),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: cover == null
                        ? ColoredBox(
                            color: colors.surfaceSoft,
                            child: Icon(
                              Icons.celebration_outlined,
                              color: colors.goldPrimary,
                            ),
                          )
                        : Image.file(
                            File(cover),
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                ColoredBox(color: colors.surfaceSoft),
                          ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: SizedBox(
                    height: 104,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (category != null)
                              Text(
                                category.name(locale),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.goldMuted,
                                ),
                              ),
                            Text(
                              s.serviceName.trim(),
                              key: const ValueKey('preview-service-name'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium,
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            if (s.city != null)
                              Expanded(
                                child: Text(
                                  s.city!.name(locale),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall,
                                ),
                              )
                            else
                              const Spacer(),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  formatPrice(s.price ?? 0),
                                  key: const ValueKey('preview-price'),
                                  style: TextStyle(
                                    color: colors.goldSoft,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
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
              ],
            ),
          ),
        ),
        if (s.photos.length > 1) ...[
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 64,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: s.photos.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
              itemBuilder: (_, i) => ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: Image.file(
                    File(s.photos[i].path),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        ColoredBox(color: colors.surfaceSoft),
                  ),
                ),
              ),
            ),
          ),
        ],
        if (s.publishStatus == OnboardingPublishStatus.failed) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            key: const ValueKey('onboarding-publish-error'),
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: colors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${t(locale, ru: 'Не удалось опубликовать.', kz: 'Жариялау мүмкін болмады.', en: 'Could not publish.')} '
              '${apiErrorMessage(locale, s.error ?? '')} '
              '${t(locale, ru: 'Нажмите «Опубликовать» ещё раз — уже сохранённое не задублируется.', kz: '«Жариялау» түймесін қайта басыңыз — сақталғаны қайталанбайды.', en: 'Tap Publish again — what was already saved won\'t be duplicated.')}',
              style: textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
        ],
      ],
    );
  }
}
