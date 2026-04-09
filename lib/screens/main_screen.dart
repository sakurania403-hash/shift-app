import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/store_settings_service.dart';
import 'login_screen.dart';
import 'store_setup_screen.dart';
import 'recruitment_screen.dart';
import 'invite_screen.dart';
import 'store_settings_screen.dart';
import 'member_management_screen.dart';
import 'staff_payroll_screen.dart';
import 'staff_settings_screen.dart';
import 'home_calendar_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _authService  = AuthService();
  final _storeService = StoreService();
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  bool _isAdmin   = false;
  int  _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    StoreSettingsService.getJapaneseHolidays();
    _loadStores();
  }

  Future<void> _loadStores() async {
    try {
      final stores  = await _storeService.getMyStores();
      final isAdmin = stores.any((m) => m['role'] == 'admin');
      setState(() {
        _stores    = stores;
        _isAdmin   = isAdmin;
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

  Map<String, dynamic> _toMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    return Map<String, dynamic>.from(value as Map);
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

    // ─── 管理者ナビ ───────────────────────────────────────────
    const adminDestinations = [
      NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'ホーム',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        selectedIcon: Icon(Icons.event_note),
        label: 'シフト募集',
      ),
      NavigationDestination(
        icon: Icon(Icons.people_outline),
        selectedIcon: Icon(Icons.people),
        label: 'メンバー',
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

    // ─── スタッフナビ ─────────────────────────────────────────
    const staffDestinations = [
      NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'ホーム',
      ),
      NavigationDestination(
        icon: Icon(Icons.event_note_outlined),
        selectedIcon: Icon(Icons.event_note),
        label: 'シフト',
      ),
      NavigationDestination(
        icon: Icon(Icons.calculate_outlined),
        selectedIcon: Icon(Icons.calculate),
        label: '給料計算',
      ),
      NavigationDestination(
        icon: Icon(Icons.settings_outlined),
        selectedIcon: Icon(Icons.settings),
        label: '設定',
      ),
    ];

    // ─── 管理者画面リスト ──────────────────────────────────────
    final adminScreens = [
      HomeCalendarScreen(stores: _stores, isAdmin: true),
      const RecruitmentScreen(),
      const MemberManagementScreen(),
      const InviteScreen(),
      const StoreSettingsScreen(),
    ];

    // ─── スタッフ画面リスト ────────────────────────────────────
    final staffScreens = [
      HomeCalendarScreen(stores: _stores, isAdmin: false),
      const RecruitmentScreen(),
      StaffPayrollScreen(stores: _stores),
      StaffSettingsScreen(stores: _stores),
    ];

    final destinations = _isAdmin ? adminDestinations : staffDestinations;
    final screens      = _isAdmin ? adminScreens      : staffScreens;
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