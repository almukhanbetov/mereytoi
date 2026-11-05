import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/services/listing_management_service.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:mereytoi_app/state/listing_management_actions.dart';
import 'package:mereytoi_app/state/listings_provider.dart';

void main() {
  test('deleting a hall refreshes «Мои рестораны»', () async {
    var fetches = 0;
    final container = ProviderContainer(
      overrides: [
        myListingsProvider.overrideWith((ref) async {
          fetches++;
          return const <Listing>[];
        }),
        listingManagementServiceProvider.overrideWithValue(_Service()),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(myListingsProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(myListingsProvider.future);
    expect(fetches, 1);

    await container.read(listingManagementActionsProvider).deleteHall(1, 2);
    await container.read(myListingsProvider.future);
    expect(fetches, 2);
  });
}

class _Service implements ListingManagementService {
  @override
  Future<void> deleteHall(int listingId, int hallId) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
