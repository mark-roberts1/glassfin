/// Where the viewer is: **a stack, not a current-screen name.**
///
/// Detail is reachable from Home, from a library and from Search, and Back has
/// to return to whichever it was. A single `currentScreen` string cannot express
/// that, and every attempt to patch one into behaving like a stack ends up being
/// a stack with the bookkeeping spread out.
///
/// See `docs/ui-spec.md` §0.
library;

import 'package:flutter/foundation.dart';

import '../jellyfin/models.dart';

@immutable
sealed class GlassfinRoute {
  const GlassfinRoute();
}

final class HomeRoute extends GlassfinRoute {
  const HomeRoute();
}

final class SearchRoute extends GlassfinRoute {
  const SearchRoute();
}

final class SettingsRoute extends GlassfinRoute {
  const SettingsRoute();
}

final class LibraryRoute extends GlassfinRoute {
  const LibraryRoute(this.library);

  final Item library;
}

final class DetailRoute extends GlassfinRoute {
  const DetailRoute(this.item);

  final Item item;
}

/// A non-empty stack of routes, oldest first.
///
/// Immutable, so that a screen holding one cannot quietly rewrite history: every
/// change produces a new stack, which the application root swaps in.
@immutable
class RouteStack {
  const RouteStack(this.entries);

  static const RouteStack initial = RouteStack([HomeRoute()]);

  final List<GlassfinRoute> entries;

  GlassfinRoute get current => entries.last;

  /// True when the top of the stack is Detail, which suppresses the ambient
  /// backdrop — Detail draws its own hero and the two would fight.
  bool get isDetail => current is DetailRoute;

  bool get canPop => entries.length > 1;

  RouteStack push(GlassfinRoute route) => RouteStack([...entries, route]);

  /// **Refuses to empty the stack.** There is always somewhere to be, and a
  /// blank screen from three metres is indistinguishable from a crash.
  RouteStack pop() =>
      canPop ? RouteStack(entries.sublist(0, entries.length - 1)) : this;

  /// The Home action resets the whole stack rather than pushing another Home,
  /// so pressing it twice does not leave two of them buried underneath.
  RouteStack home() => initial;
}
