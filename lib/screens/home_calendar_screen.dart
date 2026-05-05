import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_settings_service.dart';
import 'personal_store_screen.dart';

final _supabase = Supabase.instance.client;

const _defaultStoreColors = [
  Color(0xFF2C7873),
  Color(0xFFE07B39),
  Color(0xFF6C5CE7),
  Color(0xFFE84393),
  Color(0xFF00B894),
  Color(0xFFE17055),
];

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return const Color(0xFF2C7873);
  return Color(int.parse('FF$h', radix: 16));
}

class HomeCalendarScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final bool isAdmin;
  const HomeCalendarScreen({
    super.key,
    required this.stores,
    required this.isAdmin,
  });

  @override
  State<HomeCalendarScreen> createState() => HomeCalendarScreenState();
}

class HomeCalendarScreenState extends State<HomeCalendarScreen> {
  late int _year;
  late int _month;
  bool _loading = true;

  Map<String, List<Map<String, dynamic>>> _myShiftsByStore = {};
  String? _selectedDateStr;
  Map<String, Map<String, List<Map<String, dynamic>>>> _timelineByStore = {};
  bool _timelineLoading = false;
  String? _expandedStoreId;
  bool _storeTimelineLoading = false;
  String? _selectedStoreId;

  late Map<String, Color>  _colorMap;
  late Map<String, String> _nameMap;

  // 個人追加職場
  List<Map<String, dynamic>> _personalStores = [];
  Map<String, Color> _personalColorMap = {};
  Map<String, String> _personalNameMap = {};
  List<Map<String, dynamic>> _personalShifts = [];

  // 終業時間マップ（storeId → 時間文字列）
  Map<String, String> _weekdayCloseMap = {};
  Map<String, String> _holidayCloseMap = {};

  // 休憩ルールマップ（storeId → ルールリスト）
  Map<String, List<Map<String, dynamic>>> _breakRulesMap = {};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year  = now.year;
    _month = now.month;
    _buildMaps();
    _loadMyShifts();
  }

  void _buildMaps() {
    _colorMap = {};
    _nameMap  = {};
    for (var i = 0; i < widget.stores.length; i++) {
      final m       = widget.stores[i];
      final store   = _toMap(m['stores']);
      final id      = store['id'] as String;
      _nameMap[id]  = store['name'] as String? ?? '';
      final role    = m['role'] as String? ?? 'staff';
      if (role == 'personal') continue;
      final displayColorHex = m['display_color'] as String?;
      if (displayColorHex != null && displayColorHex.isNotEmpty) {
        _colorMap[id] = _hexToColor(displayColorHex);
      } else {
        _colorMap[id] = _defaultStoreColors[i % _defaultStoreColors.length];
      }
    }
  }

  Future<void> _loadPersonalShifts() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final storesData = await _supabase
          .from('personal_stores')
          .select()
          .eq('user_id', userId)
          .order('sort_order');

      final stores = List<Map<String, dynamic>>.from(storesData);

      final colorMap = <String, Color>{};
      final nameMap  = <String, String>{};
      for (final s in stores) {
        final id    = s['id'] as String;
        final name  = s['name'] as String;
        final hex   = s['color'] as String? ?? '#2C7873';
        nameMap[id]  = name;
        colorMap[id] = _hexToColor(hex);
      }

      final fromStr = DateTime(_year, _month, 1)
          .toIso8601String().substring(0, 10);
      final toStr = DateTime(_year, _month + 1, 0)
          .toIso8601String().substring(0, 10);

      final shiftsData = await _supabase
          .from('personal_shifts')
          .select()
          .eq('user_id', userId)
          .gte('date', fromStr)
          .lte('date', toStr)
          .order('date');

      if (mounted) {
        setState(() {
          _personalStores   = stores;
          _personalColorMap = colorMap;
          _personalNameMap  = nameMap;
          _personalShifts   = List<Map<String, dynamic>>.from(shiftsData);
        });
      }
    } catch (e) {
      debugPrint('loadPersonalShifts error: $e');
    }
  }

  Future<void> reloadColors() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final storeIds = widget.stores
          .map((m) => _toMap(m['stores'])['id'] as String)
          .toList();
      final rows = await _supabase
          .from('store_memberships')
          .select('store_id, display_color')
          .eq('user_id', userId)
          .inFilter('store_id', storeIds);

      final colorMap = <String, String?>{};
      for (final r in rows) {
        final m       = Map<String, dynamic>.from(r as Map);
        final storeId = m['store_id'] as String;
        colorMap[storeId] = m['display_color'] as String?;
      }

      if (mounted) {
        setState(() {
          for (var i = 0; i < widget.stores.length; i++) {
            final store = _toMap(widget.stores[i]['stores']);
            final id    = store['id'] as String;
            final hex   = colorMap[id];
            if (hex != null && hex.isNotEmpty) {
              _colorMap[id] = _hexToColor(hex);
            } else {
              _colorMap[id] =
                  _defaultStoreColors[i % _defaultStoreColors.length];
            }
          }
        });
      }
    } catch (e) {
      debugPrint('reloadColors error: $e');
    }
  }

  Future<void> reloadShifts() async {
    await _loadMyShifts();
  }

  Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    return Map<String, dynamic>.from(v as Map);
  }

  bool _isPersonalStore(String storeId) {
    return _personalStores.any((s) => s['id'] == storeId);
  }

  Future<void> _loadMyShifts() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final fromStr = DateTime(_year, _month, 1)
          .toIso8601String().substring(0, 10);
      final toStr = DateTime(_year, _month + 1, 0)
          .toIso8601String().substring(0, 10);

      // 終業時間設定を取得
      try {
        final storeIds = widget.stores
            .where((m) => (m['role'] as String? ?? 'staff') != 'personal')
            .map((m) => _toMap(m['stores'])['id'] as String)
            .toList();
        if (storeIds.isNotEmpty) {
          final settings = await _supabase
              .from('staff_payroll_settings')
              .select('store_id, weekday_close, holiday_close')
              .eq('user_id', userId)
              .inFilter('store_id', storeIds);
          final weekdayMap = <String, String>{};
          final holidayMap = <String, String>{};
          for (final s in settings) {
            final sm  = Map<String, dynamic>.from(s as Map);
            final sid = sm['store_id'] as String;
            weekdayMap[sid] = sm['weekday_close'] as String? ?? '22:00';
            holidayMap[sid] = sm['holiday_close'] as String? ?? '22:00';
          }
          _weekdayCloseMap = weekdayMap;
          _holidayCloseMap = holidayMap;
        }

        // 休憩ルールを取得
        final breakMap = <String, List<Map<String, dynamic>>>{};
        for (final sid in storeIds) {
          try {
            final rules = await _supabase
                .from('store_break_rules')
                .select()
                .eq('store_id', sid)
                .order('work_hours_threshold');
            breakMap[sid] = rules
                .map((r) => Map<String, dynamic>.from(r as Map))
                .toList();
          } catch (_) {
            breakMap[sid] = [];
          }
        }
        _breakRulesMap = breakMap;
      } catch (e) {
        debugPrint('loadCloseSettings error: $e');
      }

      final newMap = <String, List<Map<String, dynamic>>>{};
      for (final m in widget.stores) {
        final store   = _toMap(m['stores']);
        final storeId = store['id'] as String;
        final role    = m['role'] as String? ?? 'staff';
        if (role == 'personal') continue;
        final raw = await _supabase
            .from('shifts')
            .select('date, start_time, end_time')
            .eq('store_id', storeId)
            .eq('user_id', userId)
            .gte('date', fromStr)
            .lte('date', toStr)
            .order('date');
        newMap[storeId] =
            raw.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }
      if (mounted) setState(() => _myShiftsByStore = newMap);
    } catch (e) {
      debugPrint('loadMyShifts error: $e');
    } finally {
      await _loadPersonalShifts();
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadAdminTimeline(String dateStr) async {
    setState(() => _timelineLoading = true);
    try {
      final newMap = <String, Map<String, List<Map<String, dynamic>>>>{};
      for (final m in widget.stores) {
        final store   = _toMap(m['stores']);
        final storeId = store['id'] as String;
        final raw = await _supabase
            .from('shifts')
            .select('start_time, end_time, user_id')
            .eq('store_id', storeId)
            .eq('date', dateStr)
            .order('start_time');
        if (raw.isEmpty) { newMap[storeId] = {}; continue; }

        final userIds = raw
            .map((r) => (r as Map)['user_id'] as String?)
            .where((id) => id != null).cast<String>()
            .toSet().toList();

        final nameMap = <String, String>{};
        if (userIds.isNotEmpty) {
          final profiles = await _supabase
              .from('user_profiles').select('id, name')
              .inFilter('id', userIds);
          for (final p in profiles) {
            final pm  = Map<String, dynamic>.from(p as Map);
            final pid = pm['id'] as String?;
            if (pid != null) nameMap[pid] = pm['name'] as String? ?? '不明';
          }
        }

        final sortOrderMap = <String, int>{};
        if (userIds.isNotEmpty) {
          final memberships = await _supabase
              .from('store_memberships')
              .select('user_id, sort_order')
              .eq('store_id', storeId)
              .inFilter('user_id', userIds);
          for (final mm in memberships) {
            final mem   = Map<String, dynamic>.from(mm as Map);
            final uid   = mem['user_id'] as String?;
            final order = mem['sort_order'] as int? ?? 9999;
            if (uid != null) sortOrderMap[uid] = order;
          }
        }

        final list = <Map<String, dynamic>>[];
        for (final r in raw) {
          final rec      = Map<String, dynamic>.from(r as Map);
          final uid      = rec['user_id'] as String?;
          final startRaw = rec['start_time'] as String?;
          final endRaw   = rec['end_time']   as String?;
          final name     = uid != null ? (nameMap[uid] ?? '不明') : 'ヘルプ';
          final start    = startRaw != null ? startRaw.substring(0, 5) : '09:00';
          final end      = endRaw   != null ? endRaw.substring(0, 5)   : '00:00';
          final order    = uid != null ? (sortOrderMap[uid] ?? 9999) : 9999;
          list.add({'name': name, 'start': start, 'end': end, 'order': order});
        }
        list.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));
        newMap[storeId] = {dateStr: list};
      }
      if (mounted) setState(() => _timelineByStore = newMap);
    } catch (e) {
      debugPrint('timeline error: $e');
    } finally {
      if (mounted) setState(() => _timelineLoading = false);
    }
  }

  Future<void> _loadStoreTimeline(String storeId, String dateStr) async {
    setState(() => _storeTimelineLoading = true);
    try {
      final raw = await _supabase
          .from('shifts')
          .select('start_time, end_time, user_id')
          .eq('store_id', storeId)
          .eq('date', dateStr)
          .order('start_time');

      final userIds = raw
          .map((r) => (r as Map)['user_id'] as String?)
          .where((id) => id != null).cast<String>()
          .toSet().toList();

      final nameMap = <String, String>{};
      if (userIds.isNotEmpty) {
        final profiles = await _supabase
            .from('user_profiles').select('id, name')
            .inFilter('id', userIds);
        for (final p in profiles) {
          final pm  = Map<String, dynamic>.from(p as Map);
          final pid = pm['id'] as String?;
          if (pid != null) nameMap[pid] = pm['name'] as String? ?? '不明';
        }
      }

      final sortOrderMap = <String, int>{};
      if (userIds.isNotEmpty) {
        final memberships = await _supabase
            .from('store_memberships')
            .select('user_id, sort_order')
            .eq('store_id', storeId)
            .inFilter('user_id', userIds);
        for (final mm in memberships) {
          final mem   = Map<String, dynamic>.from(mm as Map);
          final uid   = mem['user_id'] as String?;
          final order = mem['sort_order'] as int? ?? 9999;
          if (uid != null) sortOrderMap[uid] = order;
        }
      }

      final list = <Map<String, dynamic>>[];
      for (final r in raw) {
        final rec      = Map<String, dynamic>.from(r as Map);
        final uid      = rec['user_id'] as String?;
        final startRaw = rec['start_time'] as String?;
        final endRaw   = rec['end_time']   as String?;
        final name     = uid != null ? (nameMap[uid] ?? '不明') : 'ヘルプ';
        final start    = startRaw != null ? startRaw.substring(0, 5) : '09:00';
        final end      = endRaw   != null ? endRaw.substring(0, 5)   : '00:00';
        final order    = uid != null ? (sortOrderMap[uid] ?? 9999) : 9999;
        list.add({'name': name, 'start': start, 'end': end, 'order': order});
      }
      list.sort((a, b) => (a['order'] as int).compareTo(b['order'] as int));

      if (mounted) {
        setState(() {
          _timelineByStore[storeId] = {dateStr: list};
        });
      }
    } catch (e) {
      debugPrint('storeTimeline error: $e');
    } finally {
      if (mounted) setState(() => _storeTimelineLoading = false);
    }
  }

  void _onDayTap(String dateStr) {
    if (_selectedDateStr == dateStr) {
      setState(() {
        _selectedDateStr = null;
        _expandedStoreId = null;
      });
    } else {
      setState(() {
        _selectedDateStr = dateStr;
        _expandedStoreId = null;
        _timelineByStore = {};
      });
      if (widget.isAdmin) _loadAdminTimeline(dateStr);
    }
  }

  void _onStoreTap(String storeId, String dateStr) {
    if (_expandedStoreId == storeId) {
      setState(() => _expandedStoreId = null);
    } else {
      setState(() => _expandedStoreId = storeId);
      _loadStoreTimeline(storeId, dateStr);
    }
  }

  void _prevMonth() {
    setState(() {
      _selectedDateStr = null;
      _expandedStoreId = null;
      if (_month == 1) { _year--; _month = 12; } else { _month--; }
    });
    _loadMyShifts();
  }

  void _nextMonth() {
    setState(() {
      _selectedDateStr = null;
      _expandedStoreId = null;
      if (_month == 12) { _year++; _month = 1; } else { _month++; }
    });
    _loadMyShifts();
  }

  List<MapEntry<String, String>> get _allStoreEntries {
    final entries = <MapEntry<String, String>>[];
    for (final m in widget.stores) {
      final store = _toMap(m['stores']);
      final id    = store['id'] as String;
      entries.add(MapEntry(id, _nameMap[id] ?? ''));
    }
    for (final s in _personalStores) {
      final id = s['id'] as String;
      if (!entries.any((e) => e.key == id)) {
        entries.add(MapEntry(id, _personalNameMap[id] ?? ''));
      }
    }
    return entries;
  }

  Color _storeColor(String id) {
    return _colorMap[id] ?? _personalColorMap[id] ?? Colors.grey;
  }

  int get _filteredShiftCount {
    if (_selectedStoreId == null) {
      int count = 0;
      for (final shifts in _myShiftsByStore.values) {
        count += shifts.length;
      }
      count += _personalShifts.length;
      return count;
    }
    if (_isPersonalStore(_selectedStoreId!)) {
      return _personalShifts
          .where((s) => s['personal_store_id'] == _selectedStoreId)
          .length;
    }
    return (_myShiftsByStore[_selectedStoreId] ?? []).length;
  }

  // 休憩時間を計算（分）
  int _calcBreakMinutes(String storeId, int rawMinutes) {
    final rules = _breakRulesMap[storeId] ?? [];
    if (rules.isEmpty) return 0;
    final wh = rawMinutes / 60.0;
    int bMin = 0;
    for (final r in rules) {
      if (wh > (r['work_hours_threshold'] as num).toDouble()) {
        bMin = r['break_minutes'] as int;
      }
    }
    return bMin;
  }

  // ラスト（end_time=NULL or 00:00始まり）を終業時間に変換して合計時間を計算
  double get _filteredTotalHours {
    double total = 0;

    // 店舗シフト
    final storeEntries = _selectedStoreId == null
        ? _myShiftsByStore.entries.toList()
        : _myShiftsByStore.entries
            .where((e) => e.key == _selectedStoreId)
            .toList();

    for (final entry in storeEntries) {
      final storeId = entry.key;
      for (final s in entry.value) {
        try {
          final startRaw = s['start_time'] as String?;
          final endRaw   = s['end_time']   as String?;
          if (startRaw == null) continue;

          final sp = startRaw.substring(0, 5).split(':');
          final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);

          // ラスト判定：end_timeがNULLまたは00:00始まり
          final isLast = endRaw == null || endRaw.startsWith('00:00');
          final String endStr;
          if (isLast) {
            endStr = _weekdayCloseMap[storeId] ?? '22:00';
          } else {
            endStr = endRaw!.substring(0, 5);
          }

          final ep = endStr.split(':');
          var em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
          if (em <= sm) em += 24 * 60;
          final rawMin = em - sm;
          final breakMin = _calcBreakMinutes(storeId, rawMin);
          final workedMin = (rawMin - breakMin).clamp(0, rawMin);
          total += workedMin / 60.0;
        } catch (_) {}
      }
    }

    // 個人追加職場シフト
    if (_selectedStoreId == null || _isPersonalStore(_selectedStoreId!)) {
      final personalShifts = _selectedStoreId == null
          ? _personalShifts
          : _personalShifts
              .where((s) => s['personal_store_id'] == _selectedStoreId)
              .toList();

      for (final s in personalShifts) {
        try {
          final startRaw = s['start_time'] as String?;
          final endRaw   = s['end_time']   as String?;
          if (startRaw == null) continue;

          final sp = startRaw.substring(0, 5).split(':');
          final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);

          final isLast = endRaw == null || endRaw.startsWith('00:00');
          final String endStr = isLast ? '22:00' : endRaw!.substring(0, 5);

          final ep = endStr.split(':');
          var em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
          if (em <= sm) em += 24 * 60;
          total += (em - sm) / 60.0;
        } catch (_) {}
      }
    }

    return total;
  }

  List<Widget> _buildMyChips(String dateStr) {
    final chips = <Widget>[];

    for (final entry in _myShiftsByStore.entries) {
      final storeId = entry.key;
      if (_selectedStoreId != null && _selectedStoreId != storeId) continue;
      final shifts = entry.value
          .where((s) => s['date'] == dateStr).toList();
      if (shifts.isEmpty) continue;
      final color = _storeColor(storeId);
      for (final s in shifts) {
        final startRaw = s['start_time'] as String?;
        final endRaw   = s['end_time']   as String?;
        final start    = startRaw != null ? startRaw.substring(0, 5) : '?';
        final endLabel = (endRaw == null || endRaw.startsWith('00:00'))
            ? 'ラスト' : endRaw.substring(0, 5);
        chips.add(_buildChip('$start〜$endLabel', color));
      }
    }

    final personalForDate = _personalShifts
        .where((s) => s['date'] == dateStr).toList();
    for (final s in personalForDate) {
      final storeId = s['personal_store_id'] as String?;
      if (_selectedStoreId != null && _selectedStoreId != storeId) continue;
      final color    = storeId != null
          ? (_personalColorMap[storeId] ?? Colors.teal) : Colors.teal;
      final startRaw = s['start_time'] as String?;
      final endRaw   = s['end_time']   as String?;
      final start    = startRaw != null ? startRaw.substring(0, 5) : '?';
      final endLabel = (endRaw == null || endRaw.startsWith('00:00'))
          ? 'ラスト' : endRaw.substring(0, 5);
      chips.add(_buildChip('$start〜$endLabel', color));
    }

    return chips;
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withOpacity(0.5), width: 0.8),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        if (!widget.isAdmin) _buildStoreFilterTabs(),
        if (!widget.isAdmin) _buildSummary(),
        _buildLegend(),
        _buildWeekdayRow(),
        SizedBox(
          height: _calendarHeight(context),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildCalendarGrid(),
        ),
        Expanded(
          child: _selectedDateStr == null
              ? _buildPlaceholder()
              : widget.isAdmin
                  ? _buildAdminTimelinePanel(_selectedDateStr!)
                  : _buildStaffTimelinePanel(_selectedDateStr!),
        ),
      ],
    );
  }

  double _calendarHeight(BuildContext context) {
    final firstDay    = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWd     = firstDay.weekday % 7;
    final rows        = ((startWd + daysInMonth) / 7).ceil();
    return rows * 60.0;
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFFE8F4F3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF2C7873)),
            onPressed: _prevMonth,
          ),
          Text('$_year年$_month月',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7873))),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF2C7873)),
            onPressed: _nextMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildStoreFilterTabs() {
    final allEntries = _allStoreEntries;
    if (allEntries.isEmpty) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            GestureDetector(
              onTap: () => setState(() => _selectedStoreId = null),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _selectedStoreId == null
                      ? Colors.teal : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('すべて',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _selectedStoreId == null
                            ? Colors.white : Colors.black54)),
              ),
            ),
            ...allEntries
                .where((entry) => entry.value.isNotEmpty)
                .map((entry) {
              final id      = entry.key;
              final name    = entry.value;
              final color   = _storeColor(id);
              final isSelected = _selectedStoreId == id;
              return GestureDetector(
                onTap: () => setState(() => _selectedStoreId = id),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: isSelected ? color : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(name,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? Colors.white : Colors.black54)),
                ),
              );
            }),
            GestureDetector(
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const PersonalStoreScreen(),
                  ),
                );
                await _loadMyShifts();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.add, size: 14, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('職場を追加',
                        style:
                            TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(children: [
            const Text('勤務日数',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text('${_filteredShiftCount}日',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
          ]),
          Column(children: [
            const Text('合計時間',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            Text('${_filteredTotalHours.toStringAsFixed(1)}h',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal)),
          ]),
        ],
      ),
    );
  }

  Widget _buildLegend() {
    final allEntries = _allStoreEntries;
    if (allEntries.length <= 1 && widget.isAdmin) {
      return const SizedBox.shrink();
    }
    if (!widget.isAdmin) return const SizedBox.shrink();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Wrap(
        spacing: 12, runSpacing: 4,
        children: allEntries.map((entry) {
          final id    = entry.key;
          final name  = entry.value;
          final color = _storeColor(id);
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 10, height: 10,
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(width: 4),
              Text(name, style: const TextStyle(fontSize: 11)),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildWeekdayRow() {
    const days   = ['日', '月', '火', '水', '木', '金', '土'];
    const colors = [
      Color(0xFFE53935), Colors.black87, Colors.black87,
      Colors.black87,   Colors.black87, Colors.black87,
      Color(0xFF1565C0),
    ];
    return Container(
      color: const Color(0xFFF5F7FA),
      child: Row(
        children: List.generate(7, (i) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            alignment: Alignment.center,
            child: Text(days[i],
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colors[i])),
          ),
        )),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay    = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWd     = firstDay.weekday % 7;
    final rows        = ((startWd + daysInMonth) / 7).ceil();
    final today       = DateTime.now();
    final isNowMonth  = today.year == _year && today.month == _month;

    return GridView.builder(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        childAspectRatio: MediaQuery.of(context).size.width / 7 / 60.0,
      ),
      itemCount: rows * 7,
      itemBuilder: (context, index) {
        final dayNum = index - startWd + 1;
        if (dayNum < 1 || dayNum > daysInMonth) {
          return Container(
              decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade100)));
        }
        final date       = DateTime(_year, _month, dayNum);
        final dateStr    = date.toIso8601String().substring(0, 10);
        final wd         = date.weekday % 7;
        final isToday    = isNowMonth && today.day == dayNum;
        final isSelected = _selectedDateStr == dateStr;
        final isSunday   = wd == 0;
        final isSaturday = wd == 6;
        final chips      = _buildMyChips(dateStr);

        return GestureDetector(
          onTap: () => _onDayTap(dateStr),
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFD0EFEB)
                  : isToday ? const Color(0xFFE8F4F3) : Colors.white,
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF2C7873) : Colors.grey.shade200,
                width: isSelected ? 1.5 : 1.0,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20, height: 20,
                  alignment: Alignment.center,
                  decoration: isToday
                      ? const BoxDecoration(
                          color: Color(0xFF2C7873), shape: BoxShape.circle)
                      : null,
                  child: Text('$dayNum',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        color: isToday ? Colors.white
                            : isSunday  ? const Color(0xFFE53935)
                            : isSaturday ? const Color(0xFF1565C0)
                            : Colors.black87,
                      )),
                ),
                const SizedBox(height: 1),
                ...chips,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: const Color(0xFFF5F7FA),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.touch_app_outlined, size: 36, color: Colors.grey),
            SizedBox(height: 8),
            Text('日付をタップするとシフトを表示',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildPanelHeader(String dateStr) {
    final date     = DateTime.parse(dateStr);
    const weekdays = ['日', '月', '火', '水', '木', '金', '土'];
    final wd       = date.weekday % 7;
    final label =
        '${date.year}年${date.month}月${date.day}日（${weekdays[wd]}）';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFFE8F4F3),
        border: Border(top: BorderSide(color: Color(0xFF2C7873), width: 2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, size: 14, color: Color(0xFF2C7873)),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7873))),
          const Spacer(),
          GestureDetector(
            onTap: () => setState(() {
              _selectedDateStr = null;
              _expandedStoreId = null;
            }),
            child: const Icon(Icons.close, size: 18, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminTimelinePanel(String dateStr) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader(dateStr),
          Expanded(
            child: _timelineLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildGantt(dateStr),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffTimelinePanel(String dateStr) {
    final allEntries = _allStoreEntries;
    final filteredEntries = _selectedStoreId == null
        ? allEntries
        : allEntries.where((e) => e.key == _selectedStoreId).toList();

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildPanelHeader(dateStr),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: filteredEntries.map((entry) {
                  final storeId = entry.key;
                  final name    = entry.value;
                  final color   = _storeColor(storeId);
                  final isPersonal = _isPersonalStore(storeId);

                  List<Map<String, dynamic>> myShifts;
                  if (isPersonal) {
                    myShifts = _personalShifts
                        .where((s) =>
                            s['date'] == dateStr &&
                            s['personal_store_id'] == storeId)
                        .toList();
                  } else {
                    myShifts = (_myShiftsByStore[storeId] ?? [])
                        .where((s) => s['date'] == dateStr)
                        .toList();
                  }

                  final shiftLabel = myShifts.isEmpty
                      ? 'シフトなし'
                      : myShifts.map((s) {
                          final startRaw = s['start_time'] as String?;
                          final endRaw   = s['end_time']   as String?;
                          final start    = startRaw != null
                              ? startRaw.substring(0, 5) : '?';
                          final end = (endRaw == null ||
                                  endRaw.startsWith('00:00'))
                              ? 'ラスト' : endRaw.substring(0, 5);
                          return '$start〜$end';
                        }).join(' / ');

                  final isExpanded = _expandedStoreId == storeId;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      InkWell(
                        onTap: isPersonal
                            ? null
                            : () => _onStoreTap(storeId, dateStr),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          decoration: BoxDecoration(
                            color: isExpanded
                                ? color.withOpacity(0.08) : Colors.white,
                            border: Border(
                              bottom: BorderSide(
                                  color: Colors.grey.shade200, width: 1),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 10, height: 10,
                                decoration: BoxDecoration(
                                    color: color, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(name,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: color)),
                              ),
                              Text(shiftLabel,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: myShifts.isEmpty
                                          ? Colors.grey : Colors.black87)),
                              if (!isPersonal) ...[
                                const SizedBox(width: 8),
                                Icon(
                                  isExpanded
                                      ? Icons.expand_less : Icons.expand_more,
                                  color: Colors.grey, size: 18,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (isExpanded && !isPersonal)
                        Container(
                          color: const Color(0xFFF9FFFE),
                          child: _storeTimelineLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Center(
                                      child: CircularProgressIndicator()),
                                )
                              : _buildGanttForStore(storeId, dateStr),
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGantt(String dateStr) {
    final allShifts = <Map<String, dynamic>>[];
    for (final entry in _timelineByStore.entries) {
      final storeId = entry.key;
      final list    = entry.value[dateStr] ?? [];
      for (final s in list) {
        allShifts.add({...s, 'storeId': storeId});
      }
    }
    if (allShifts.isEmpty) {
      return const Center(
        child: Text('この日のシフトはありません',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }
    int minHour = 24, maxHour = 0;
    for (final s in allShifts) {
      final sh = _parseHour(s['start'] as String);
      var   eh = _parseHour(s['end']   as String);
      if (eh == 0 || eh <= sh) eh = 24;
      if (sh < minHour) minHour = sh;
      if (eh > maxHour) maxHour = eh;
    }
    minHour  = (minHour - 1).clamp(0, 23);
    maxHour  = (maxHour + 1).clamp(1, 25);
    final totalHours = maxHour - minHour;
    const rowHeight  = 36.0;
    const labelWidth = 72.0;
    const hourWidth  = 52.0;
    final chartWidth = totalHours * hourWidth;

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.stores.length == 1)
            _buildGanttRows(allShifts, minHour, totalHours,
                labelWidth, hourWidth, chartWidth, rowHeight)
          else
            ...widget.stores.map((m) {
              final store       = _toMap(m['stores']);
              final storeId     = store['id'] as String;
              final color       = _storeColor(storeId);
              final storeName   = _nameMap[storeId] ?? '';
              final storeShifts = allShifts
                  .where((s) => s['storeId'] == storeId).toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                    child: Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2))),
                      const SizedBox(width: 6),
                      Text(storeName,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ]),
                  ),
                  storeShifts.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.only(left: 16, bottom: 8),
                          child: Text('シフトなし',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)))
                      : _buildGanttRows(storeShifts, minHour, totalHours,
                          labelWidth, hourWidth, chartWidth, rowHeight),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _buildGanttForStore(String storeId, String dateStr) {
    final list = (_timelineByStore[storeId] ?? {})[dateStr] ?? [];
    final allShifts = list.map((s) => {...s, 'storeId': storeId}).toList();

    if (allShifts.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('この日のシフトはありません',
            style: TextStyle(color: Colors.grey, fontSize: 13)),
      );
    }

    int minHour = 24, maxHour = 0;
    for (final s in allShifts) {
      final sh = _parseHour(s['start'] as String);
      var   eh = _parseHour(s['end']   as String);
      if (eh == 0 || eh <= sh) eh = 24;
      if (sh < minHour) minHour = sh;
      if (eh > maxHour) maxHour = eh;
    }
    minHour  = (minHour - 1).clamp(0, 23);
    maxHour  = (maxHour + 1).clamp(1, 25);
    final totalHours = maxHour - minHour;
    const rowHeight  = 36.0;
    const labelWidth = 72.0;
    const hourWidth  = 52.0;
    final chartWidth = totalHours * hourWidth;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: _buildGanttRows(allShifts, minHour, totalHours,
          labelWidth, hourWidth, chartWidth, rowHeight),
    );
  }

  Widget _buildGanttRows(
    List<Map<String, dynamic>> shifts,
    int minHour, int totalHours,
    double labelWidth, double hourWidth,
    double chartWidth, double rowHeight,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(width: labelWidth),
            ...List.generate(totalHours, (i) {
              final h = minHour + i;
              return SizedBox(
                width: hourWidth,
                child: Text('${h % 24}:00',
                    style: const TextStyle(fontSize: 9, color: Colors.grey),
                    textAlign: TextAlign.left),
              );
            }),
          ]),
          ...shifts.map((s) {
            final storeId  = s['storeId'] as String;
            final color    = _storeColor(storeId);
            final name     = s['name']  as String;
            final startStr = s['start'] as String;
            final endStr   = s['end']   as String;
            final sh       = _parseMinute(startStr);
            var   eh       = _parseMinute(endStr);
            if (eh <= sh) eh += 24 * 60;
            final isLast   = endStr.startsWith('00:00');
            final startOffset =
                (sh / 60.0 - minHour).clamp(0.0, totalHours.toDouble()) *
                    hourWidth;
            final barWidth =
                ((eh - sh) / 60.0).clamp(0.5, totalHours.toDouble()) *
                    hourWidth;

            return SizedBox(
              height: rowHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Text(name,
                          style: const TextStyle(fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.right),
                    ),
                  ),
                  SizedBox(
                    width: chartWidth,
                    child: Stack(children: [
                      Row(children: List.generate(
                          totalHours,
                          (i) => Container(
                                width: hourWidth,
                                height: rowHeight,
                                decoration: BoxDecoration(
                                  border: Border(
                                      left: BorderSide(
                                          color: Colors.grey.shade200,
                                          width: 1)),
                                ),
                              ))),
                      Positioned(
                        left: startOffset,
                        top: (rowHeight - 22) / 2,
                        child: Container(
                          width: barWidth,
                          height: 22,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.85),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            isLast
                                ? '$startStr〜ラスト'
                                : '$startStr〜$endStr',
                            style: const TextStyle(
                                fontSize: 9,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  int _parseHour(String t) {
    final p = t.split(':');
    if (p.isEmpty) return 0;
    return int.tryParse(p[0]) ?? 0;
  }

  int _parseMinute(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return (int.tryParse(p[0]) ?? 0) * 60 + (int.tryParse(p[1]) ?? 0);
  }
}