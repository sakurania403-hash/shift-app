import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/join_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://mvwyclebbaoywyrxugeb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12d3ljbGViYmFveXd5cnh1Z2ViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MTEyMzgsImV4cCI6MjA5MDM4NzIzOH0.oGlisgR0rGA47F0tO4smgbxaW0wtQuSTFOF8bDMM4Mc',
  );

  // window.flutterInitialPath からURLを取得
  String? joinToken;
  try {
    final initialPath = html.window.location.href;
    final uri = Uri.parse(initialPath);
    debugPrint('initialPath: $initialPath');
    debugPrint('uri.path: ${uri.path}');
    debugPrint('invite: ${uri.queryParameters['invite']}');
    if (uri.path == '/join') {
      joinToken = uri.queryParameters['invite'];
    }
  } catch (e) {
    debugPrint('URL parse error: $e');
  }

  runApp(MyApp(joinToken: joinToken));
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