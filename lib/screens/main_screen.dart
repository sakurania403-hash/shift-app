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

  final _calendarKey = GlobalKey<HomeCalendarScreenState>();
  final _payrollKey  = GlobalKey<StaffPayrollScreenState>();
  final _settingsKey = GlobalKey<StaffSettingsScreenState>();

  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  bool _isAdmin   = false;
  int  _selectedIndex = 0;

  List<Widget>? _screens;

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
        _screens   = null;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // 設定保存後：カレンダー・給料計算・設定画面の色を即時更新
  Future<void> _onSettingsSaved() async {
    await Future.wait([
      _calendarKey.currentState?.reloadColors() ?? Future.value(),
      _payrollKey.currentState?.reloadColors()  ?? Future.value(),
      _settingsKey.currentState?.reloadColors() ?? Future.value(),
    ]);
  }

  Future<void> _signOut() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  List<Widget> _buildScreens() {
    if (_isAdmin) {
      return [
        HomeCalendarScreen(
          key: _calendarKey,
          stores: _stores,
          isAdmin: true,
        ),
        const RecruitmentScreen(),
        const MemberManagementScreen(),
        const InviteScreen(),
        StoreSettingsScreen(),
      ];
    } else {
      return [
        HomeCalendarScreen(
          key: _calendarKey,
          stores: _stores,
          isAdmin: false,
        ),
        const RecruitmentScreen(),
        StaffPayrollScreen(
          key: _payrollKey,
          stores: _stores,
        ),
        StaffSettingsScreen(
          key: _settingsKey,
          stores: _stores,
          onSaved: _onSettingsSaved,
        ),
      ];
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

    _screens ??= _buildScreens();

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

    final destinations = _isAdmin ? adminDestinations : staffDestinations;
    final screens      = _screens!;
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