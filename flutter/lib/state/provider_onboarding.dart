import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/network/api_exception.dart';
import '../core/utils/phone.dart';
import '../models/city.dart';
import '../models/listing.dart';
import '../models/provider_profile.dart';
import 'provider_provider.dart';
import 'providers.dart';

/// Number of steps in the provider onboarding wizard.
const kOnboardingSteps = 6;

/// Experience is a whole number of years in this range.
const kMaxExperienceYears = 80;

/// At most this many photos per onboarding.
const kMaxOnboardingPhotos = 10;

/// A picked photo: its local file, and its public URL once uploaded (kept
/// so a retried publish never uploads the same file twice).
@immutable
class OnboardingPhoto {
  const OnboardingPhoto({required this.path, this.url});

  final String path;
  final String? url;

  OnboardingPhoto withUrl(String url) => OnboardingPhoto(path: path, url: url);
}

enum OnboardingPublishStatus { idle, publishing, failed, done }

/// The wizard's draft plus how far a publish got. Step data survives going
/// back and forth; closing the wizard drops it (the provider is
/// autoDispose), so reopening starts over.
@immutable
class ProviderOnboardingState {
  const ProviderOnboardingState({
    this.step = 0,
    this.categoryId,
    this.restaurant = false,
    this.displayName = '',
    this.description = '',
    this.experienceText = '',
    this.phone = '',
    this.whatsapp = '',
    this.whatsappSame = true,
    this.city,
    this.photos = const [],
    this.serviceName = '',
    this.serviceDescription = '',
    this.priceText = '',
    this.address = '',
    this.latitude,
    this.longitude,
    this.existingProvider,
    this.providerReady = false,
    this.listingAttempted = false,
    this.createdListing,
    this.publishStatus = OnboardingPublishStatus.idle,
    this.error,
  });

  final int step;
  final int? categoryId;

  /// The chosen category is the restaurants one: the first listing then has
  /// an address and a map point instead of a price (prices live in its menus).
  final bool restaurant;
  final String displayName;
  final String description;
  final String experienceText;

  /// The business's public contact number: optional, and never filled in
  /// from the account's private phone.
  final String phone;

  /// The separate WhatsApp number, used when [whatsappSame] is off.
  final String whatsapp;

  /// «WhatsApp на этом же номере».
  final bool whatsappSame;
  final City? city;
  final List<OnboardingPhoto> photos;
  final String serviceName;
  final String serviceDescription;
  final String priceText;
  final String address;
  final double? latitude;
  final double? longitude;

  /// The caller's provider profile if one already existed when the wizard
  /// opened (or was found during publish) — then it's updated, never
  /// created a second time.
  final ProviderProfile? existingProvider;

  /// Publish progress, so a retry skips what already succeeded.
  final bool providerReady;
  final bool listingAttempted;
  final Listing? createdListing;
  final OnboardingPublishStatus publishStatus;
  final Object? error;

  /// Parsed experience; null when blank. Only meaningful when
  /// [experienceValid].
  int? get experienceYears {
    final text = experienceText.trim();
    return text.isEmpty ? null : int.tryParse(text);
  }

  /// The phone is required; WhatsApp is the same number or its own one.
  bool get contactsValid {
    final p = normalizePhone(phone);
    if (p == null || p.isEmpty) return false;
    if (whatsappSame) return true;
    final w = normalizePhone(whatsapp);
    return w != null && w.isNotEmpty;
  }

  /// Contacts as stored by the server (international format).
  String get normalizedPhone => normalizePhone(phone) ?? '';
  String get normalizedWhatsApp =>
      whatsappSame ? normalizedPhone : (normalizePhone(whatsapp) ?? '');

  bool get experienceValid {
    final text = experienceText.trim();
    if (text.isEmpty) return true;
    final v = int.tryParse(text);
    return v != null && v >= 0 && v <= kMaxExperienceYears;
  }

  int? get price => int.tryParse(priceText.trim());

  /// Whether step [index]'s required data is filled in.
  bool stepComplete(int index) {
    switch (index) {
      case 0:
        return categoryId != null;
      case 1:
        return displayName.trim().isNotEmpty &&
            experienceValid &&
            contactsValid;
      case 2:
        return city != null;
      case 3:
        return true; // photos are optional
      case 4:
        return serviceName.trim().isNotEmpty && (restaurant || price != null);
      default:
        return List.generate(5, (i) => i).every(stepComplete);
    }
  }

  bool get canProceed => stepComplete(step);

  ProviderOnboardingState copyWith({
    int? step,
    int? categoryId,
    bool? restaurant,
    String? displayName,
    String? description,
    String? experienceText,
    String? phone,
    String? whatsapp,
    bool? whatsappSame,
    City? city,
    List<OnboardingPhoto>? photos,
    String? serviceName,
    String? serviceDescription,
    String? priceText,
    String? address,
    double? latitude,
    double? longitude,
    ProviderProfile? existingProvider,
    bool? providerReady,
    bool? listingAttempted,
    Listing? createdListing,
    OnboardingPublishStatus? publishStatus,
    Object? error,
    bool clearError = false,
  }) {
    return ProviderOnboardingState(
      step: step ?? this.step,
      categoryId: categoryId ?? this.categoryId,
      restaurant: restaurant ?? this.restaurant,
      displayName: displayName ?? this.displayName,
      description: description ?? this.description,
      experienceText: experienceText ?? this.experienceText,
      phone: phone ?? this.phone,
      whatsapp: whatsapp ?? this.whatsapp,
      whatsappSame: whatsappSame ?? this.whatsappSame,
      city: city ?? this.city,
      photos: photos ?? this.photos,
      serviceName: serviceName ?? this.serviceName,
      serviceDescription: serviceDescription ?? this.serviceDescription,
      priceText: priceText ?? this.priceText,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      existingProvider: existingProvider ?? this.existingProvider,
      providerReady: providerReady ?? this.providerReady,
      listingAttempted: listingAttempted ?? this.listingAttempted,
      createdListing: createdListing ?? this.createdListing,
      publishStatus: publishStatus ?? this.publishStatus,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Picks photos from the gallery (paths). A provider so tests can swap in
/// fixed files.
final onboardingPhotoPickerProvider = Provider<Future<List<String>> Function()>(
  (ref) {
    return () async {
      final picked = await ImagePicker().pickMultiImage(imageQuality: 85);
      return picked.map((f) => f.path).toList();
    };
  },
);

class ProviderOnboardingController
    extends StateNotifier<ProviderOnboardingState> {
  ProviderOnboardingController(this._ref)
    : super(const ProviderOnboardingState());

  final Ref _ref;

  // ---- step data ----

  void selectCategory(int id, {bool restaurant = false}) =>
      state = state.copyWith(categoryId: id, restaurant: restaurant);
  void setDisplayName(String v) => state = state.copyWith(displayName: v);
  void setDescription(String v) => state = state.copyWith(description: v);
  void setExperience(String v) => state = state.copyWith(experienceText: v);
  void setPhone(String v) => state = state.copyWith(phone: v);
  void setWhatsApp(String v) => state = state.copyWith(whatsapp: v);
  void setWhatsAppSame(bool v) => state = state.copyWith(whatsappSame: v);
  void setCity(City city) => state = state.copyWith(city: city);
  void setServiceName(String v) => state = state.copyWith(serviceName: v);
  void setServiceDescription(String v) =>
      state = state.copyWith(serviceDescription: v);
  void setPrice(String v) => state = state.copyWith(priceText: v);
  void setAddress(String v) => state = state.copyWith(address: v);
  void setPoint(double latitude, double longitude) =>
      state = state.copyWith(latitude: latitude, longitude: longitude);

  void addPhotos(List<String> paths) {
    final room = kMaxOnboardingPhotos - state.photos.length;
    if (room <= 0 || paths.isEmpty) return;
    state = state.copyWith(
      photos: [
        ...state.photos,
        for (final p in paths.take(room)) OnboardingPhoto(path: p),
      ],
    );
  }

  void removePhoto(int index) {
    final photos = [...state.photos]..removeAt(index);
    state = state.copyWith(photos: photos);
  }

  /// Moves the photo at [oldIndex] to [newIndex] (the final position, as
  /// [ReorderableListView.onReorderItem] reports it).
  void movePhoto(int oldIndex, int newIndex) {
    final photos = [...state.photos];
    photos.insert(newIndex, photos.removeAt(oldIndex));
    state = state.copyWith(photos: photos);
  }

  /// Fills the profile steps from an existing provider profile, so a
  /// returning provider continues instead of starting a second profile.
  /// A free-text city is matched to the directory when possible.
  void prefillFrom(ProviderProfile provider, {List<City> cities = const []}) {
    City? city;
    final wanted = provider.city.trim().toLowerCase();
    if (wanted.isNotEmpty) {
      for (final c in cities) {
        if ([
          c.nameRu,
          c.nameKz,
          c.nameEn,
        ].any((n) => n.trim().toLowerCase() == wanted)) {
          city = c;
          break;
        }
      }
    }
    state = state.copyWith(
      existingProvider: provider,
      displayName: state.displayName.isEmpty
          ? provider.displayName
          : state.displayName,
      description: state.description.isEmpty
          ? provider.description
          : state.description,
      experienceText:
          state.experienceText.isEmpty && provider.experienceYears != null
          ? '${provider.experienceYears}'
          : state.experienceText,
      phone: state.phone.isEmpty ? provider.phone : state.phone,
      whatsapp: state.whatsapp.isEmpty ? provider.whatsapp : state.whatsapp,
      whatsappSame:
          provider.whatsapp.isEmpty ||
          normalizePhone(provider.whatsapp) == normalizePhone(provider.phone),
      city: state.city ?? city,
    );
  }

  // ---- navigation ----

  bool next() {
    if (!state.canProceed || state.step >= kOnboardingSteps - 1) return false;
    state = state.copyWith(step: state.step + 1, clearError: true);
    return true;
  }

  bool back() {
    if (state.step == 0) return false;
    state = state.copyWith(step: state.step - 1, clearError: true);
    return true;
  }

  // ---- publish ----

  /// Creates/updates the profile, uploads the photos and creates the first
  /// service. Safe to call again after a failure: each part that already
  /// succeeded is skipped, an existing profile is updated instead of
  /// duplicated, and a service whose create response was lost is found in
  /// "Мои услуги" instead of being created twice.
  Future<bool> publish() async {
    if (state.publishStatus == OnboardingPublishStatus.publishing ||
        !state.stepComplete(kOnboardingSteps - 1)) {
      return false;
    }
    state = state.copyWith(
      publishStatus: OnboardingPublishStatus.publishing,
      clearError: true,
    );
    try {
      await _ensureProvider();
      await _uploadPhotos();
      await _ensureListing();
      state = state.copyWith(publishStatus: OnboardingPublishStatus.done);
      return true;
    } catch (e) {
      state = state.copyWith(
        publishStatus: OnboardingPublishStatus.failed,
        error: e,
      );
      return false;
    }
  }

  String get _cityName => state.city?.nameRu ?? '';

  Future<void> _ensureProvider() async {
    if (state.providerReady) return;
    final actions = _ref.read(providerActionsProvider);
    final existing = state.existingProvider;

    Future<ProviderProfile> update(ProviderProfile current) =>
        actions.updateProfile(
          displayName: state.displayName.trim(),
          city: _cityName,
          description: state.description.trim(),
          phone: state.normalizedPhone,
          whatsapp: state.normalizedWhatsApp,
          // Keep the other contact details the profile already has.
          telegram: current.telegram,
          avatarUrl: current.avatarUrl,
          includeExperience: true,
          experienceYears: state.experienceYears,
        );

    ProviderProfile profile;
    if (existing != null) {
      profile = await update(existing);
    } else {
      try {
        profile = await actions.become(
          displayName: state.displayName.trim(),
          city: _cityName,
          description: state.description.trim(),
          phone: state.normalizedPhone,
          whatsapp: state.normalizedWhatsApp,
          experienceYears: state.experienceYears,
        );
      } on ApiException catch (e) {
        // Created meanwhile (another device, or a lost response): fetch it
        // and update instead of creating a second one.
        if (e.type != ApiErrorType.conflict) rethrow;
        final current = await _ref.read(providerServiceProvider).me();
        state = state.copyWith(existingProvider: current);
        profile = await update(current);
      }
    }
    state = state.copyWith(existingProvider: profile, providerReady: true);
  }

  Future<void> _uploadPhotos() async {
    final pending = [
      for (var i = 0; i < state.photos.length; i++)
        if (state.photos[i].url == null) i,
    ];
    if (pending.isEmpty) return;
    final urls = await _ref.read(uploadServiceProvider).uploadImages([
      for (final i in pending) state.photos[i].path,
    ]);
    if (urls.length != pending.length) {
      throw const ApiException(
        ApiErrorType.server,
        debugMessage: 'upload returned a different number of urls',
      );
    }
    final photos = [...state.photos];
    for (var k = 0; k < pending.length; k++) {
      photos[pending[k]] = photos[pending[k]].withUrl(urls[k]);
    }
    state = state.copyWith(photos: photos);
  }

  Future<void> _ensureListing() async {
    if (state.createdListing != null) return;
    final name = state.serviceName.trim();
    final restaurant = state.restaurant;
    final price = restaurant ? 0 : state.price ?? 0;
    final categoryId = state.categoryId!;

    if (state.listingAttempted) {
      // A previous attempt may have reached the server even though its
      // response didn't reach us — look before creating again.
      final mine = await _ref.read(listingServiceProvider).fetchMyListings();
      for (final l in mine) {
        if (l.nameRu == name &&
            l.categoryId == categoryId &&
            l.price == price) {
          state = state.copyWith(createdListing: l);
          return;
        }
      }
    }

    state = state.copyWith(listingAttempted: true);
    final description = state.serviceDescription.trim();
    final listing = await _ref
        .read(providerActionsProvider)
        .createListing(
          categoryId: categoryId,
          // One name/description field in the wizard: used for both
          // languages (the backend requires name_kz).
          nameRu: name,
          nameKz: name,
          descriptionRu: description,
          descriptionKz: description,
          city: _cityName,
          price: price,
          imageUrls: [for (final p in state.photos) p.url!],
          // A restaurant's own contact starts as the business's number.
          phone: restaurant ? state.phone.trim() : '',
          address: restaurant ? state.address.trim() : '',
          latitude: restaurant ? state.latitude : null,
          longitude: restaurant ? state.longitude : null,
        );
    state = state.copyWith(createdListing: listing);
  }
}

final providerOnboardingProvider =
    StateNotifierProvider.autoDispose<
      ProviderOnboardingController,
      ProviderOnboardingState
    >((ref) => ProviderOnboardingController(ref));
