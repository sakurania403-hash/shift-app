import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import 'login_screen.dart';
import 'store_setup_screen.dart';
import 'recruitment_screen.dart';
import 'invite_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _authService = AuthService();
  final _storeService = StoreService();
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final stores = await _storeService.getMyStores();
      final isAdmin = stores.any((m) => m['role'] == 'admin');
      setState(() {
        _stores = stores;
        _isAdmin = isAdmin;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_stores.isEmpty) {
      return const StoreSetupScreen();
    }

    // 管理者用ナビ
    final adminDestinations = const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'ホーム',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        selectedIcon: Icon(Icons.event_note),
        label: 'シフト募集',
      ),
      NavigationDestination(
        icon: Icon(Icons.person_add_outlined),
        selectedIcon: Icon(Icons.person_add),
        label: 'スタッフ招待',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '設定',
      ),
    ];

    // スタッフ用ナビ
    final staffDestinations = const [
      NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home),
        label: 'ホーム',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        selectedIcon: Icon(Icons.event_note),
        label: 'シフト',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '設定',
      ),
    ];

    // 管理者用画面
    final adminScreens = [
      // ホーム
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month,
                size: 80, color: Colors.teal),
            const SizedBox(height: 24),
            Text(
              '所属店舗',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ..._stores.map((m) {
              final store = m['stores'] as Map<String, dynamic>;
              final role = m['role'] as String;
              return ListTile(
                leading: const Icon(Icons.store, color: Colors.teal),
                title: Text(store['name']),
                subtitle: Text(role == 'admin' ? '管理者' : 'スタッフ'),
              );
            }),
          ],
        ),
      ),
      const RecruitmentScreen(),
      const InviteScreen(),
      const Center(child: Text('設定（実装予定）')),
    ];

    // スタッフ用画面
    final staffScreens = [
      Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.calendar_month,
                size: 80, color: Colors.teal),
            const SizedBox(height: 24),
            Text(
              '所属店舗',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            ..._stores.map((m) {
              final store = m['stores'] as Map<String, dynamic>;
              return ListTile(
                leading: const Icon(Icons.store, color: Colors.teal),
                title: Text(store['name']),
                subtitle: const Text('スタッフ'),
              );
            }),
          ],
        ),
      ),
      const RecruitmentScreen(),
      const Center(child: Text('設定（実装予定）')),
    ];

    final destinations =
        _isAdmin ? adminDestinations : staffDestinations;
    final screens = _isAdmin ? adminScreens : staffScreens;
    final currentIndex =
        _selectedIndex >= screens.length ? 0 : _selectedIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('シフト管理アプリ'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) =>
            setState(() => _selectedIndex = i),
        destinations: destinations,
      ),
    );
  }
}