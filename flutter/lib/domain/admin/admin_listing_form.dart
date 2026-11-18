import '../../models/listing.dart';

/// The web admin's «Новая услуга» / «Редактировать услугу» form
/// (frontend/src/components/admin/ServiceForm.jsx) as plain data: the same
/// fields, the same defaults, the same checks the browser applies to its
/// inputs (`required`, `min`, `max`, `step`, `maxLength`) and the same
/// request body. No new rule lives here.
class AdminListingValues {
  AdminListingValues({
    this.categoryId,
    this.nameRu = '',
    this.nameKz = '',
    this.descriptionRu = '',
    this.descriptionKz = '',
    this.city = '',
    this.phone = '',
    this.price = '0',
    this.minGuests = '0',
    this.maxGuests = '0',
    this.rating = '0',
    this.emoji = '✨',
    this.colorFrom = '#3a1420',
    this.colorTo = '#d4af6a',
    List<String>? imageUrls,
    List<String>? videoUrls,
  }) : imageUrls = imageUrls ?? [],
       videoUrls = videoUrls ?? [];

  /// ServiceForm's EMPTY merged with `initial` — for an existing listing
  /// every field starts from what it has.
  factory AdminListingValues.fromListing(Listing l) => AdminListingValues(
    categoryId: l.categoryId,
    nameRu: l.nameRu,
    nameKz: l.nameKz,
    descriptionRu: l.descriptionRu,
    descriptionKz: l.descriptionKz,
    city: l.city,
    phone: l.phone,
    price: '${l.price}',
    minGuests: '${l.minGuests}',
    maxGuests: '${l.maxGuests}',
    rating: _ratingText(l.rating),
    emoji: l.emoji,
    colorFrom: l.colorFrom,
    colorTo: l.colorTo,
    imageUrls: [...l.imageUrls],
    videoUrls: [...l.videoUrls],
  );

  int? categoryId;
  String nameRu;
  String nameKz;
  String descriptionRu;
  String descriptionKz;
  String city;
  String phone;
  String price;
  String minGuests;
  String maxGuests;
  String rating;
  String emoji;
  String colorFrom;
  String colorTo;
  final List<String> imageUrls;
  final List<String> videoUrls;
}

String _ratingText(double r) {
  final rounded = (r * 10).round() / 10;
  return rounded == rounded.roundToDouble()
      ? '${rounded.toInt()}'
      : rounded.toString();
}

/// Messages for each field, null when it's fine. Mirrors what the browser
/// refuses on submit for ServiceForm's inputs.
class AdminListingErrors {
  const AdminListingErrors({
    this.nameRu,
    this.nameKz,
    this.category,
    this.price,
    this.rating,
    this.minGuests,
    this.maxGuests,
    this.emoji,
    this.colorFrom,
    this.colorTo,
  });

  final String? nameRu;
  final String? nameKz;
  final String? category;
  final String? price;
  final String? rating;
  final String? minGuests;
  final String? maxGuests;
  final String? emoji;
  final String? colorFrom;
  final String? colorTo;

  bool get isEmpty => [
    nameRu,
    nameKz,
    category,
    price,
    rating,
    minGuests,
    maxGuests,
    emoji,
    colorFrom,
    colorTo,
  ].every((e) => e == null);
}

const _required = 'Заполните это поле';
const _wholeNumber = 'Введите целое число от 0';

/// `<input type="number" min="0">` (step 1): empty is allowed (sent as 0),
/// anything else must be a whole number ≥ 0.
String? _wholeNonNegative(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return null;
  final n = int.tryParse(v);
  return n == null || n < 0 ? _wholeNumber : null;
}

/// `<input type="number" min="0" max="5" step="0.1">`.
String? _ratingError(String raw) {
  final v = raw.trim().replaceAll(',', '.');
  if (v.isEmpty) return null;
  final n = double.tryParse(v);
  const msg = 'Рейтинг — число от 0 до 5 с шагом 0.1';
  if (n == null || n < 0 || n > 5) return msg;
  final tenths = n * 10;
  return (tenths - tenths.round()).abs() > 1e-9 ? msg : null;
}

final _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

AdminListingErrors validateAdminListing(AdminListingValues v) {
  return AdminListingErrors(
    nameRu: v.nameRu.trim().isEmpty ? _required : null,
    nameKz: v.nameKz.trim().isEmpty ? _required : null,
    category: v.categoryId == null ? 'Выберите категорию' : null,
    price: _wholeNonNegative(v.price),
    rating: _ratingError(v.rating),
    minGuests: _wholeNonNegative(v.minGuests),
    maxGuests: _wholeNonNegative(v.maxGuests),
    // maxLength={4} counts UTF-16 code units, as Dart's String.length does.
    emoji: v.emoji.length > 4 ? 'Не больше 4 символов' : null,
    colorFrom: _hexColor.hasMatch(v.colorFrom) ? null : 'Цвет в формате #RRGGBB',
    colorTo: _hexColor.hasMatch(v.colorTo) ? null : 'Цвет в формате #RRGGBB',
  );
}

int _numberOr0(String raw) => int.tryParse(raw.trim()) ?? 0;

double _ratingOr0(String raw) =>
    double.tryParse(raw.trim().replaceAll(',', '.')) ?? 0;

/// ServiceForm's `payload`: `{...values, category_id: Number(...), price:
/// Number(...) || 0, ...}`. When editing, `values` started as the whole
/// listing, so every field the form doesn't show (address, coordinates,
/// place, capacity, price type, publication) goes back unchanged — the
/// server's PUT replaces the whole row.
Map<String, dynamic> adminListingPayload(
  AdminListingValues v, {
  Listing? existing,
}) {
  return {
    if (existing != null) ...{
      'address': existing.address ?? '',
      'latitude': existing.latitude,
      'longitude': existing.longitude,
      'place_id': existing.placeId,
      'capacity': existing.capacity,
      'price_type': existing.priceType ?? '',
      'is_active': existing.isActive,
    },
    'category_id': v.categoryId,
    'name_ru': v.nameRu,
    'name_kz': v.nameKz,
    'description_ru': v.descriptionRu,
    'description_kz': v.descriptionKz,
    'city': v.city,
    'phone': v.phone,
    'price': _numberOr0(v.price),
    'min_guests': _numberOr0(v.minGuests),
    'max_guests': _numberOr0(v.maxGuests),
    'rating': _ratingOr0(v.rating),
    'emoji': v.emoji,
    'color_from': v.colorFrom,
    'color_to': v.colorTo,
    'image_urls': [...v.imageUrls],
    'video_urls': [...v.videoUrls],
  };
}

/// Where the server keeps a video's poster: `uploads/posters/<name>.jpg`
/// (backend/internal/media/video.go `PosterURLFor`). It may not exist yet
/// right after an upload — the preview then shows its plain fallback.
String? videoPosterPath(String videoUrl) {
  const prefix = '/uploads/';
  if (!videoUrl.startsWith(prefix)) return null;
  final name = videoUrl.substring(prefix.length);
  if (name.isEmpty || name.contains('/')) return null;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  return '${prefix}posters/$stem.jpg';
}
