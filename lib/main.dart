import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'screens/join_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://mvwyclebbaoywyrxugeb.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im12d3ljbGViYmFveXd5cnh1Z2ViIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4MTEyMzgsImV4cCI6MjA5MDM4NzIzOH0.oGlisgR0rGA47F0tO4smgbxaW0wtQuSTFOF8bDMM4Mc',
  );

  String? joinToken;

  if (kIsWeb) {
    try {
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
      title: 'シフトチェック',
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
              ? const HomeRouter()
              : const LoginScreen(),
    );
  }
}

class HomeRouter extends StatefulWidget {
  const HomeRouter({super.key});

  @override
  State<HomeRouter> createState() => _HomeRouterState();
}

class _HomeRouterState extends State<HomeRouter> {
  final _authService = AuthService();
  bool _isLoading = true;
  String _mode = 'store';

  @override
  void initState() {
    super.initState();
    _loadMode();
  }

  Future<void> _loadMode() async {
    try {
      final mode = await _authService.getUserMode();
      if (mounted) {
        setState(() {
          _mode = mode;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mode = 'store';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
    return MainScreen(mode: _mode);
  }
}