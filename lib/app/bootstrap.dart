import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_environment.dart';

final appEnvironmentProvider = Provider<AppEnvironment>(
  (ref) => AppEnvironment.fromDartDefines(),
);

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);
