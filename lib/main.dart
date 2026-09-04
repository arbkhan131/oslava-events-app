import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app/app.dart';
import 'app/bootstrap.dart';
import 'core/config/app_environment.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final environment = AppEnvironment.fromDartDefines();

  await Supabase.initialize(
    url: environment.supabaseUrl,
    publishableKey: environment.supabaseAnonKey,
  );

  runApp(
    ProviderScope(
      overrides: [appEnvironmentProvider.overrideWithValue(environment)],
      child: const OslavaApp(),
    ),
  );
}
