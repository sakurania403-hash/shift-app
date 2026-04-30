import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/join_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://mvwyclebbaoywyrxugeb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12d3ljbGViYmFveXd5cnh1Z2ViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MTEyMzgsImV4cCI6MjA5MDM4NzIzOH0.oGlisgR0rGA47F0tO4smgbxaW0wtQuSTFOF8bDMM4Mc',
  );

  String? joinToken;

  if (kIsWeb) {
    try {
      // ignore: avoid_web_libraries_in_flutter
      final html = _getWebHash();
      if (html != null && html.startsWith('#/join')) {
        final hashPath = html.substring(1);
        final uri = Uri.parse(hashPath);
        joinToken = uri.queryParameters['invite'];
        debugPrint('joinToken: $joinToken');
      }
    } catch (e) {
      debugPrint('Hash parse error: $e');
    }
  }

  runApp(MyApp(joinToken: joinToken));
}

String? _getWebHash() {
  if (!kIsWeb) return null;
  try {
    // Web環境でのみ実行
    return Uri.base.fragment.isNotEmpty ? '#${Uri.base.fragment}' : null;
  } catch (e) {
    return null;
  }
}

class MyApp extends StatelessWidget {
  final String? joinToken;
  const MyApp({super.key, this.joinToken});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    return MaterialApp(
      title: 'シフト管理アプリ',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ja', 'JP'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ja', 'JP'),
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: joinToken != null
          ? JoinScreen(token: joinToken!)
          : supabase.auth.currentUser != null
              ? const MainScreen()
              : const LoginScreen(),
    );
  }
}