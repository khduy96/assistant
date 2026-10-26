import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';

Future<void> main(List<String> args) async {
  final app = await bootstrap(args);
  // Null for a clock window (--pomodoro, --countdown): it runs its own app.
  if (app != null) runApp(app);
}
