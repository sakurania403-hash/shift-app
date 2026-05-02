import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/store_service.dart';
import '../services/store_settings_service.dart';
import '../services/notification_service.dart';
import 'login_screen.dart';
import 'store_setup_screen.dart';
import 'recruitment_screen.dart';
import 'invite_screen.dart';
import 'store_settings_screen.dart';
import 'member_management_screen.dart';
import 'staff_payroll_screen.dart';
import 'staff_settings_screen.dart';
import 'home_calendar_screen.dart';
import 'personal_calendar_screen.dart';

class MainScreen extends StatefulWidget {
  final String mode;
  const MainScreen({super.key, this.mode = 'store'});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  final _authService         = AuthService();
  final _storeService        = StoreService();
  final _notificationService = NotificationService();

  final _calendarKey = GlobalKey<HomeCalendarScreenState>();
  final _payrollKey  = GlobalKey<StaffPayrollScreenState>();
  final _settingsKey = GlobalKey<StaffSettingsScreenState>();

  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  bool _isAdmin   = false;
  int  _selectedIndex = 0;
  int  _screenKey = 0;

  List<Widget>? _screens;

  int _unreadCount = 0;
  Timer? _pollingTimer;

  bool get _isPersonal => widget.mode == 'personal';

  @override
  void initState() {
    super.initState();
    if (!_isPersonal) {
      StoreSettingsService.getJapaneseHolidays();
      _loadStores().then((_) => _startNotificationPolling());
    } else {
      _loadPersonalStores();
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStores() async {
    try {
      final stores  = await _storeService.getMyStores();
      final isAdmin = stores.any((m) => m['role'] == 'admin');

      List<Map<String, dynamic>> allStores = List.from(stores);
      if (!isAdmin) {
        try {
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (userId != null) {
            final personalStores = await Supabase.instance.client
                .from('personal_stores')
                .select()
                .eq('user_id', userId)
                .order('sort_order');
            final personalList =
                (personalStores as List).map((s) => <String, dynamic>{
                  'stores': {
                    'id': s['id'],
                    'name': s['name'],
                  },
                  'display_color': s['color'],
                  'role': 'personal',
                }).toList();
            debugPrint('personalList colors: ${personalList.map((s) => s['display_color']).toList()}');
            allStores = [...stores, ...personalList];
          }
        } catch (e) {
          debugPrint('loadPersonalStores error: $e');
        }
      }

      if (mounted) {
        setState(() {
          _stores    = allStores;
          _isAdmin   = isAdmin;
          _isLoading = false;
          _screens   = null;
          _screenKey++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPersonalStores() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final data = await Supabase.instance.client
          .from('personal_stores')
          .select()
          .eq('user_id', userId)
          .order('sort_order');
      if (mounted) {
        setState(() {
          _stores = (data as List).map((s) => <String, dynamic>{
            'stores': {
              'id': s['id'],
              'name': s['name'],
            },
            'display_color': s['color'],
          }).toList();
          _isLoading = false;
          _screens   = null;
          _screenKey++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startNotificationPolling() {
    _fetchUnreadCount();
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _fetchUnreadCount(),
    );
  }

  Future<void> _fetchUnreadCount() async {
    final count = await _notificationService.getUnreadCount();
    if (mounted) {
      setState(() => _unreadCount = count);
    }
  }

  Future<void> _reloadAfterSettingsSaved() async {
    if (_isPersonal) {
      await _loadPersonalStores();
    } else {
      await _loadStores();
    }
  }

  Future<void> _signOut() async {
    _pollingTimer?.cancel();
    await _authService.signOut();
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  void _openNotificationDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NotificationDrawer(
        notificationService: _notificationService,
        onRead: _fetchUnreadCount,
        onTapNotification: (n) {
          Navigator.pop(context);
          setState(() => _selectedIndex = 1);
        },
      ),
    );
  }

  List<Widget> _buildScreens() {
    // 個人モード
    if (_isPersonal) {
      return [
        const PersonalCalendarScreen(),
        StaffPayrollScreen(stores: _stores),
        StaffSettingsScreen(
          key: _settingsKey,
          stores: _stores,
          onSaved: _reloadAfterSettingsSaved,
        ),
      ];
    }
    // 店舗モード（管理者）
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
    }
    // 店舗モード（スタッフ）
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
        onSaved: _reloadAfterSettingsSaved,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (!_isPersonal && _stores.isEmpty) {
      return const StoreSetupScreen();
    }

    _screens ??= _buildScreens();

    const personalDestinations = [
      NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'ホーム',
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

    final destinations = _isPersonal
        ? personalDestinations
        : _isAdmin
            ? adminDestinations
            : staffDestinations;

    final screens      = _screens!;
    final currentIndex =
        _selectedIndex >= screens.length ? 0 : _selectedIndex;

    return Scaffold(
      appBar: AppBar(
        title: const Text('シフトチェック'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (!_isPersonal) ...[
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(Icons.notifications_outlined),
                  onPressed: _openNotificationDrawer,
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: 6,
                    top: 6,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        child: Text(
                          _unreadCount > 99 ? '99+' : '$_unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: IndexedStack(
        key: ValueKey(_screenKey),
        index: currentIndex,
        children: screens,
      ),
      bottomNavigationBar: destinations.length > 1
          ? NavigationBar(
              selectedIndex: currentIndex,
              onDestinationSelected: (i) =>
                  setState(() => _selectedIndex = i),
              destinations: destinations,
            )
          : null,
    );
  }
}

// -------- 通知ドロワー --------

class NotificationDrawer extends StatefulWidget {
  final NotificationService notificationService;
  final VoidCallback onRead;
  final void Function(NotificationItem n) onTapNotification;

  const NotificationDrawer({
    super.key,
    required this.notificationService,
    required this.onRead,
    required this.onTapNotification,
  });

  @override
  State<NotificationDrawer> createState() => _NotificationDrawerState();
}

class _NotificationDrawerState extends State<NotificationDrawer> {
  List<NotificationItem> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await widget.notificationService.getNotifications();
    if (list.any((n) => !n.isRead)) {
      await widget.notificationService.markAllAsRead();
      widget.onRead();
    }
    if (mounted) {
      setState(() {
        _notifications = list;
        _isLoading     = false;
      });
    }
  }

  Future<void> _deleteNotification(int index) async {
    final n = _notifications[index];
    setState(() => _notifications.removeAt(index));
    try {
      await widget.notificationService.deleteNotification(n.id);
    } catch (_) {
      if (mounted) {
        setState(() => _notifications.insert(index, n));
      }
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'shift_confirmed':
        return Icons.check_circle_outline;
      case 'recruitment_started':
        return Icons.event_note_outlined;
      case 'shift_request_submitted':
        return Icons.assignment_outlined;
      default:
        return Icons.notifications_outlined;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'shift_confirmed':
        return Colors.green;
      case 'recruitment_started':
        return Colors.blue;
      case 'shift_request_submitted':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime dt) {
    final now  = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'たった今';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分前';
    if (diff.inHours < 24) return '${diff.inHours}時間前';
    if (diff.inDays < 7) return '${diff.inDays}日前';
    return '${dt.month}/${dt.day}';
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.notifications, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '通知',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる'),
                ),
              ],
            ),
          ),
          if (!_isLoading && _notifications.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16, bottom: 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '← スワイプで削除',
                  style: TextStyle(fontSize: 11, color: Colors.grey[400]),
                ),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _notifications.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.notifications_none,
                                size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text(
                              '通知はありません',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: _notifications.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, indent: 60),
                        itemBuilder: (_, i) {
                          final n = _notifications[i];
                          return Dismissible(
                            key: ValueKey(n.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 20),
                              color: Colors.red,
                              child: const Icon(Icons.delete,
                                  color: Colors.white),
                            ),
                            onDismissed: (_) => _deleteNotification(i),
                            child: ListTile(
                              onTap: () => widget.onTapNotification(n),
                              leading: CircleAvatar(
                                backgroundColor:
                                    _colorForType(n.type).withOpacity(0.15),
                                child: Icon(
                                  _iconForType(n.type),
                                  color: _colorForType(n.type),
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                n.title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 2),
                                  Text(
                                    n.body,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDate(n.createdAt),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                              isThreeLine: true,
                              trailing: Icon(
                                Icons.chevron_right,
                                size: 16,
                                color: Colors.grey[400],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}