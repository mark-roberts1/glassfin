import 'package:flutter_test/flutter_test.dart';
import 'package:glassfin/jellyfin/models.dart';
import 'package:glassfin/nav/routes.dart';

const _film = Item(id: 'film', name: 'Arrival', type: ItemKind.movie);
const _library = Item(id: 'lib', name: 'Films', type: ItemKind.unknown);

void main() {
  test('starts at Home', () {
    expect(RouteStack.initial.current, isA<HomeRoute>());
    expect(RouteStack.initial.canPop, isFalse);
  });

  test('Back returns to whichever screen Detail was opened from', () {
    // The whole reason this is a stack rather than a current-screen name: the
    // same Detail route is reachable from Home, a library and Search.
    final fromLibrary = RouteStack.initial
        .push(const LibraryRoute(_library))
        .push(const DetailRoute(_film));
    expect(fromLibrary.pop().current, isA<LibraryRoute>());

    final fromSearch = RouteStack.initial
        .push(const SearchRoute())
        .push(const DetailRoute(_film));
    expect(fromSearch.pop().current, isA<SearchRoute>());
  });

  test('refuses to empty the stack', () {
    // There is always somewhere to be; a blank screen from three metres is
    // indistinguishable from a crash.
    final popped = RouteStack.initial.pop();
    expect(popped.entries, hasLength(1));
    expect(popped.current, isA<HomeRoute>());
  });

  test('Home resets the whole stack rather than pushing another Home', () {
    final deep = RouteStack.initial
        .push(const LibraryRoute(_library))
        .push(const DetailRoute(_film));
    final reset = deep.home();
    expect(reset.entries, hasLength(1));
    expect(reset.canPop, isFalse);
  });

  test('is immutable: pushing does not disturb the stack it came from', () {
    final base = RouteStack.initial;
    base.push(const SearchRoute());
    expect(base.entries, hasLength(1));
  });

  test('isDetail is what suppresses the ambient backdrop', () {
    // Detail draws its own hero; both at once would be two backdrops fighting.
    expect(RouteStack.initial.isDetail, isFalse);
    expect(RouteStack.initial.push(const DetailRoute(_film)).isDetail, isTrue);
    expect(
      RouteStack.initial
          .push(const DetailRoute(_film))
          .push(const SearchRoute())
          .isDetail,
      isFalse,
    );
  });
}
