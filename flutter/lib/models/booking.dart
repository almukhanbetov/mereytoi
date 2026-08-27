/// Mirrors the `booking` object POST /api/bookings responds with
/// (backend/internal/models/booking.go). Only the fields the app actually
/// reads after a successful submit are surfaced.
class Booking {
  const Booking({required this.id, required this.publicRef, required this.status});

  final int id;
  final String publicRef;
  final String status;

  factory Booking.fromJson(Map<String, dynamic> json) {
    return Booking(
      id: json['id'] as int? ?? 0,
      publicRef: json['public_ref'] as String? ?? '',
      status: json['status'] as String? ?? 'new',
    );
  }
}
