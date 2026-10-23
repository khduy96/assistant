import 'package:flutter/material.dart' as material show TimeOfDay;

import '../../../core/domain/time_of_day.dart' as core;

// The domain keeps its own plain-Dart TimeOfDay; Flutter's pickers and
// formatTime take Flutter's. Both are imported under an alias here, so no file
// has to see the two names side by side: the rest of presentation converts
// with these extensions.

/// The domain's time as Flutter's, for the pickers and `formatTime`.
extension CoreTimeOfDayToFlutter on core.TimeOfDay {
  material.TimeOfDay toFlutter() =>
      material.TimeOfDay(hour: hour, minute: minute);
}

/// Flutter's time as the domain's, for what the editor hands back.
extension FlutterTimeOfDayToCore on material.TimeOfDay {
  core.TimeOfDay toCore() => core.TimeOfDay(hour: hour, minute: minute);
}
