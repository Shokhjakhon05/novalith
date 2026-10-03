/// Analytics behind an interface. The game only ever calls [Analytics.log]; which backend
/// receives the events (or none at all) is decided in main.dart and can be swapped freely.
library;

import 'package:flutter/foundation.dart';

abstract class Analytics {
  void log(String event, [Map<String, Object> params = const {}]);
}

/// Ships by default: no SDK, no network, nothing collected.
class NoAnalytics implements Analytics {
  const NoAnalytics();

  @override
  void log(String event, [Map<String, Object> params = const {}]) {}
}

/// Prints events to the console in debug builds.
class DebugAnalytics implements Analytics {
  const DebugAnalytics();

  @override
  void log(String event, [Map<String, Object> params = const {}]) {
    if (kDebugMode) debugPrint('[analytics] $event $params');
  }
}

/// Keeps events in memory - used by tests to assert what was reported.
class RecordingAnalytics implements Analytics {
  final List<String> events = [];

  @override
  void log(String event, [Map<String, Object> params = const {}]) => events.add(event);
}
