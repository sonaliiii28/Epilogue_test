import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/theme.dart';
import 'core/router.dart';

String _normalizeSupabaseUrlForPlatform(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return url;

  // If you're running local Supabase on your dev machine:
  // - Android emulator cannot reach host via localhost/127.0.0.1
  // - Use 10.0.2.2 instead
  final isLocalhost = uri.host == 'localhost' || uri.host == '127.0.0.1';
  final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  if (isAndroid && isLocalhost) {
    return uri.replace(host: '10.0.2.2').toString();
  }

  return url;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const rawSupabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://gihlsiuuogeyvuxrregl.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdpaGxzaXV1b2dleXZ1eHJyZWdsIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzI2NTQ4OTEsImV4cCI6MjA4ODIzMDg5MX0.VDTlrXI01FHjYc8suUZmTW9N8AGZhpNaXu9huMLNJu0',
  );

  final supabaseUrl = _normalizeSupabaseUrlForPlatform(rawSupabaseUrl);
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
    throw StateError(
      'Missing SUPABASE_URL or SUPABASE_ANON_KEY. Pass them via --dart-define.',
    );
  }

  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  debugPrint('Supabase initialized: $supabaseUrl');

  runApp(const EpilogueApp());
}

class EpilogueApp extends StatefulWidget {
  const EpilogueApp({super.key});

  @override
  State<EpilogueApp> createState() => _EpilogueAppState();
}

class _EpilogueAppState extends State<EpilogueApp> {
  late final SupabaseClient _client;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _client = Supabase.instance.client;
    _authSubscription = _client.auth.onAuthStateChange.listen(
      (data) {
        if (data.event == AuthChangeEvent.passwordRecovery) {
          appRouter.go('/reset-password');
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        final message = _mapRecoveryError(error);
        if (message == null) return;

        final uri = Uri(
          path: '/reset-password',
          queryParameters: {'error': message},
        );
        appRouter.go(uri.toString());
        rootScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
    );
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  String? _mapRecoveryError(Object error) {
    if (error is! AuthException) return null;

    final message = error.message.toLowerCase();
    final code = (error.code ?? '').toLowerCase();
    final looksLikeRecoveryError =
        message.contains('otp') ||
        message.contains('link') ||
        message.contains('code') ||
        message.contains('verify') ||
        code == 'otp_expired' ||
        code == 'bad_code_verifier';

    if (!looksLikeRecoveryError) {
      return null;
    }

    if (message.contains('expired') || code == 'otp_expired') {
      return 'Link expired';
    }
    if (message.contains('invalid') ||
        message.contains('used') ||
        message.contains('code') ||
        code == 'bad_code_verifier') {
      return 'Invalid or already used link';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Epilogue',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.system,
      routerConfig: appRouter,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
    );
  }
}
