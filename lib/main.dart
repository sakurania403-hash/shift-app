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

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final supabase = Supabase.instance.client;
    final uri = Uri.base;
    final token = uri.queryParameters['token'];
    final isJoinRoute =
        uri.path == '/join' && token != null && token.isNotEmpty;

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
      initialRoute: '/',
      onGenerateRoute: (settings) {
  if (isJoinRoute && token != null) {
    return MaterialPageRoute(
      builder: (_) => JoinScreen(token: token!),
    );
  }
        // 通常ルート
        return MaterialPageRoute(
          builder: (_) => supabase.auth.currentUser != null
              ? const MainScreen()
              : const LoginScreen(),
        );
      },
    );
  }
}