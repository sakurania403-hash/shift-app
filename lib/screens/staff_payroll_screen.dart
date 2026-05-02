import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_settings_service.dart';

final _supabase = Supabase.instance.client;

// ─── 列挙型 ────────────────────────────────────────────────────
enum RoundingUnit { minute, min15, min30, hour }
extension RoundingUnitExt on RoundingUnit {
  String get label {
    switch (this) {
      case RoundingUnit.minute: return '1分単位';
      case RoundingUnit.min15:  return '15分単位';
      case RoundingUnit.min30:  return '30分単位';
      case RoundingUnit.hour:   return '1時間単位';
    }
  }
}

enum RoundingDir { truncate, round, ceil }
extension RoundingDirExt on RoundingDir {
  String get label {
    switch (this) {
      case RoundingDir.truncate: return '切り捨て';
      case RoundingDir.round:    return '四捨五入';
      case RoundingDir.ceil:     return '切り上げ';
    }
  }
}

enum PaymentMonth { sameMonth, nextMonth }
extension PaymentMonthExt on PaymentMonth {
  String get label {
    switch (this) {
      case PaymentMonth.sameMonth: return '当月末払い';
      case PaymentMonth.nextMonth: return '翌月末払い';
    }
  }
}

// ─── 色ユーティリティ ──────────────────────────────────────────
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

// ─── 給料内訳 ──────────────────────────────────────────────────
class _WageBreakdown {
  final int baseWage;       // 平日給料
  final int holidayWage;    // 休日給料（休日時給設定あり時のみ）
  final int lateNightWage;  // 深夜給料
  final int commuteFee;     // 交通費
  _WageBreakdown({
    required this.baseWage,
    required this.holidayWage,
    required this.lateNightWage,
    required this.commuteFee,
  });
  int get total => baseWage + holidayWage + lateNightWage + commuteFee;
}

// ─── データモデル ───────────────────────────────────────────────
class _ShiftRecord {
  final DateTime date;
  final String startTime;
  final String endTime;
  final bool isHoliday;
  _ShiftRecord({
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.isHoliday,
  });

  int get rawMinutes {
    final sMin = _toMin(startTime);
    var   eMin = _toMin(endTime);
    if (eMin <= sMin) eMin += 24 * 60;
    return eMin - sMin;
  }

  static int _toMin(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  int lateNightMinutes(String lateStart, String lateEnd) {
    if (lateStart.isEmpty || lateEnd.isEmpty) return 0;
    final workS = _toMin(startTime);
    var   workE = _toMin(endTime);
    if (workE <= workS) workE += 24 * 60;

    final lnS = _toMin(lateStart);
    var   lnE = _toMin(lateEnd);
    if (lnE <= lnS) lnE += 24 * 60;

    final overlapS = workS > lnS ? workS : lnS;
    final overlapE = workE < lnE ? workE : lnE;
    if (overlapE <= overlapS) return 0;
    return overlapE - overlapS;
  }
}

class _PayPeriod {
  final DateTime periodStart;
  final DateTime periodEnd;
  _PayPeriod({required this.periodStart, required this.periodEnd});
  String get label {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(periodStart)} 〜 ${fmt(periodEnd)}';
  }
}

// ─── 店舗ごとのデータ ────────────────────────────────────────────
class _StoreData {
  final String storeId;
  final String storeName;
  Color displayColor;

  int          hourlyWage    = 0;
  RoundingUnit roundingUnit  = RoundingUnit.minute;
  RoundingDir  roundingDir   = RoundingDir.truncate;
  int          closingDay    = 0;
  PaymentMonth paymentMonth  = PaymentMonth.nextMonth;
  String       weekdayClose  = '22:00';
  String       holidayClose  = '22:00';

  int       commuteFee      = 0;
  int       holidayWageRate = 0;   // 0 = 未設定（基本時給を使う）
  List<int> holidayWeekdays = [];
  int       lateNightWage   = 0;
  String    lateNightStart  = '22:00';
  String    lateNightEnd    = '05:00';

  List<Map<String, dynamic>> breakRules = [];

  List<_ShiftRecord> shifts = [];
  bool shiftsLoading = false;

  int? actualPay;
  bool actualSaving = false;
  late TextEditingController actualCtrl;

  bool breakdownExpanded = false;

  _StoreData({
    required this.storeId,
    required this.storeName,
    required this.displayColor,
  }) {
    actualCtrl = TextEditingController();
  }

  void dispose() => actualCtrl.dispose();

  /// 休日時給が設定されているか（= 平日と異なる給料体系か）
  bool get hasHolidayWageRate => holidayWageRate > 0;

  _PayPeriod calcPayPeriod(int year, int month) {
    int cy = year, cm = month;
    if (paymentMonth == PaymentMonth.nextMonth) {
      cm--;
      if (cm == 0) { cm = 12; cy--; }
    }
    if (closingDay == 0) {
      return _PayPeriod(
        periodStart: DateTime(cy, cm, 1),
        periodEnd:   DateTime(cy, cm + 1, 0),
      );
    } else {
      final prevM = cm == 1 ? 12 : cm - 1;
      final prevY = cm == 1 ? cy - 1 : cy;
      return _PayPeriod(
        periodStart: DateTime(prevY, prevM, closingDay + 1),
        periodEnd:   DateTime(cy, cm, closingDay),
      );
    }
  }

  int autoBreakMinutes(int rawMin) {
    if (breakRules.isEmpty) return 0;
    final wh = rawMin / 60.0;
    int bMin = 0;
    for (final r in breakRules) {
      if (wh >= (r['work_hours_threshold'] as num).toDouble()) {
        bMin = r['break_minutes'] as int;
      }
    }
    return bMin;
  }

  int workedMinutes(int i) {
    final raw  = shifts[i].rawMinutes;
    final brk  = autoBreakMinutes(raw);
    final net  = (raw - brk).clamp(0, raw);
    int unit;
    switch (roundingUnit) {
      case RoundingUnit.minute: unit = 1;  break;
      case RoundingUnit.min15:  unit = 15; break;
      case RoundingUnit.min30:  unit = 30; break;
      case RoundingUnit.hour:   unit = 60; break;
    }
    switch (roundingDir) {
      case RoundingDir.truncate: return (net ~/ unit) * unit;
      case RoundingDir.round:    return ((net / unit).round()) * unit;
      case RoundingDir.ceil:     return ((net / unit).ceil()) * unit;
    }
  }

  /// 給料内訳を計算
  /// ・休日時給未設定 → 休日も基本時給で計算。内訳は「基本給料」にまとめる
  /// ・休日時給設定済 → 平日は基本時給、休日は休日時給で分けて表示
  _WageBreakdown dailyBreakdown(int i) {
    final shift = shifts[i];
    final wMin  = workedMinutes(i);

    int base    = 0;
    int holiday = 0;

    if (shift.isHoliday && hasHolidayWageRate) {
      // 休日時給設定あり → 休日給料として計上
      holiday = (holidayWageRate * wMin / 60).floor();
    } else {
      // 休日時給未設定 or 平日 → 基本時給で計算
      base = (hourlyWage * wMin / 60).floor();
    }

    // 深夜給料
    int lateNight = 0;
    if (lateNightWage > 0 && lateNightStart.isNotEmpty && lateNightEnd.isNotEmpty) {
      final lnMin = shift.lateNightMinutes(lateNightStart, lateNightEnd);
      lateNight = (lateNightWage * lnMin / 60).floor();
    }

    return _WageBreakdown(
      baseWage:      base,
      holidayWage:   holiday,
      lateNightWage: lateNight,
      commuteFee:    commuteFee,
    );
  }

  int get totalMinutes =>
      List.generate(shifts.length, (i) => workedMinutes(i)).fold(0, (a, b) => a + b);

  int get totalWage {
    int total = 0;
    for (var i = 0; i < shifts.length; i++) {
      total += dailyBreakdown(i).total;
    }
    return total;
  }

  // 基本給料の集計（平日 + 休日時給未設定の休日）
  int get totalBaseMinutes => List.generate(shifts.length, (i) {
    if (shifts[i].isHoliday && hasHolidayWageRate) return 0;
    return workedMinutes(i);
  }).fold(0, (a, b) => a + b);
  int get totalBaseWage    => List.generate(shifts.length, (i) => dailyBreakdown(i).baseWage).fold(0, (a, b) => a + b);

  // 休日給料の集計（休日時給設定あり時のみ）
  int get holidayMinutes   => List.generate(shifts.length, (i) => (shifts[i].isHoliday && hasHolidayWageRate) ? workedMinutes(i) : 0).fold(0, (a, b) => a + b);
  int get totalHolidayWage => List.generate(shifts.length, (i) => dailyBreakdown(i).holidayWage).fold(0, (a, b) => a + b);

  // 深夜・交通費
  int get totalLateNightMinutes => shifts.fold(0, (a, s) => a + s.lateNightMinutes(lateNightStart, lateNightEnd));
  int get totalLateNight        => List.generate(shifts.length, (i) => dailyBreakdown(i).lateNightWage).fold(0, (a, b) => a + b);
  int get totalCommute          => List.generate(shifts.length, (i) => dailyBreakdown(i).commuteFee).fold(0, (a, b) => a + b);
}

// ─── メイン画面 ────────────────────────────────────────────────
class StaffPayrollScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? stores;
  final String? storeId;
  const StaffPayrollScreen({super.key, this.stores, this.storeId});

  @override
  State<StaffPayrollScreen> createState() => StaffPayrollScreenState();
}

class StaffPayrollScreenState extends State<StaffPayrollScreen> {
  late int _year;
  late int _month;
  bool _initialLoading = true;
  List<_StoreData> _storeData = [];
  final _settingsService = StoreSettingsService();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year  = now.year;
    _month = now.month;
    _init();
  }

  @override
  void dispose() {
    for (final d in _storeData) d.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    return Map<String, dynamic>.from(v as Map);
  }

  List<int> _parseHolidayWeekdays(dynamic raw) {
    if (raw == null) return [];
    const jpMap = {
      '日': 0, '月': 1, '火': 2, '水': 3, '木': 4, '金': 5, '土': 6,
    };
    List<dynamic> items = [];
    if (raw is List) {
      items = raw;
    } else if (raw is String && raw.isNotEmpty) {
      final cleaned = raw.replaceAll(RegExp(r'[\[\]\s""]'), '');
      items = cleaned.split(',').where((s) => s.isNotEmpty).toList();
    }
    final result = <int>[];
    for (final item in items) {
      final s = item.toString().trim();
      if (jpMap.containsKey(s)) {
        result.add(jpMap[s]!);
      } else {
        final n = int.tryParse(s);
        if (n != null && n >= 0 && n <= 6) result.add(n);
      }
    }
    return result;
  }

  Future<void> reloadColors() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final storeIds = _storeData.map((d) => d.storeId).toList();
      final rows = await _supabase
          .from('store_memberships')
          .select('store_id, display_color')
          .eq('user_id', userId)
          .inFilter('store_id', storeIds);
      if (mounted) {
        setState(() {
          for (var i = 0; i < _storeData.length; i++) {
            final d = _storeData[i];
            final matching = rows
                .where((r) => (r as Map)['store_id'] == d.storeId)
                .toList();
            if (matching.isNotEmpty) {
              final hex = (matching.first as Map)['display_color'] as String?;
              if (hex != null && hex.isNotEmpty) {
                d.displayColor = _hexToColor(hex);
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('payroll reloadColors error: $e');
    }
  }

  Future<void> _init() async {
    List<Map<String, dynamic>> storeList = [];
    if (widget.stores != null && widget.stores!.isNotEmpty) {
      storeList = widget.stores!;
    } else if (widget.storeId != null) {
      storeList = [{'stores': {'id': widget.storeId, 'name': '店舗'}}];
    }

    final userId = _supabase.auth.currentUser?.id;
    Map<String, Map<String, dynamic>> savedSettings = {};
    Map<String, String?> colorMap = {};

    if (userId != null && storeList.isNotEmpty) {
      final storeIds = storeList
          .map((m) => (_toMap(m['stores'])['id'] as String))
          .toList();
      try {
        final rows = await _supabase
            .from('staff_payroll_settings')
            .select()
            .eq('user_id', userId)
            .inFilter('store_id', storeIds);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          savedSettings[m['store_id'] as String] = m;
        }
      } catch (_) {}

      try {
        final rows = await _supabase
            .from('store_memberships')
            .select('store_id, display_color')
            .eq('user_id', userId)
            .inFilter('store_id', storeIds);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          colorMap[m['store_id'] as String] = m['display_color'] as String?;
        }
      } catch (_) {}
    }

    final dataList = <_StoreData>[];
    for (var i = 0; i < storeList.length; i++) {
      final m       = storeList[i];
      final store   = _toMap(m['stores']);
      final storeId = store['id'] as String;
      final name    = store['name'] as String? ?? '';
      final saved   = savedSettings[storeId];

      Color resolvedColor;
      final hex = colorMap[storeId];
      if (hex != null && hex.isNotEmpty) {
        resolvedColor = _hexToColor(hex);
      } else {
        resolvedColor = _defaultStoreColors[i % _defaultStoreColors.length];
      }

      final d = _StoreData(
        storeId:      storeId,
        storeName:    name,
        displayColor: resolvedColor,
      );
      d.hourlyWage      = saved?['hourly_wage']      as int?    ?? 0;
      d.closingDay      = saved?['closing_day']      as int?    ?? 0;
      d.paymentMonth    = PaymentMonth.values[saved?['payment_month'] as int? ?? 1];
      d.roundingUnit    = RoundingUnit.values[saved?['rounding_unit'] as int? ?? 0];
      d.roundingDir     = RoundingDir.values[saved?['rounding_dir']   as int? ?? 0];
      d.weekdayClose    = saved?['weekday_close']    as String? ?? '22:00';
      d.holidayClose    = saved?['holiday_close']    as String? ?? '22:00';
      d.commuteFee      = saved?['commute_fee']      as int?    ?? 0;
      d.holidayWageRate = saved?['holiday_wage']     as int?    ?? 0;
      d.holidayWeekdays = _parseHolidayWeekdays(saved?['holiday_weekdays']);
      d.lateNightWage   = saved?['late_night_wage']  as int?    ?? 0;
      d.lateNightStart  = saved?['late_night_start'] as String? ?? '22:00';
      d.lateNightEnd    = saved?['late_night_end']   as String? ?? '05:00';

      try { d.breakRules = await _settingsService.getBreakRules(storeId); } catch (_) {}
      dataList.add(d);
    }

    if (mounted) {
      setState(() {
        _storeData      = dataList;
        _initialLoading = false;
      });
    }

    await Future.wait([
      for (final d in dataList) _loadShifts(d),
      _loadActuals(),
    ]);
  }

  Future<void> _loadShifts(_StoreData d) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => d.shiftsLoading = true);
    try {
      final period   = d.calcPayPeriod(_year, _month);
      final holidays = await StoreSettingsService.getJapaneseHolidays();

      List<Map<String, dynamic>> raw;

      // 個人モード（personal_storesのIDを使用）
      final isPersonal = await _isPersonalStore(d.storeId);
      if (isPersonal) {
        final data = await _supabase
            .from('personal_shifts')
            .select('date, start_time, end_time')
            .eq('user_id', userId)
            .eq('personal_store_id', d.storeId)
            .gte('date', period.periodStart.toIso8601String().substring(0, 10))
            .lte('date', period.periodEnd.toIso8601String().substring(0, 10))
            .order('date');
        raw = data.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      } else {
        final data = await _supabase
            .from('shifts')
            .select('date, start_time, end_time')
            .eq('store_id', d.storeId)
            .eq('user_id', userId)
            .gte('date', period.periodStart.toIso8601String().substring(0, 10))
            .lte('date', period.periodEnd.toIso8601String().substring(0, 10))
            .order('date');
        raw = data.map((r) => Map<String, dynamic>.from(r as Map)).toList();
      }

      final records = <_ShiftRecord>[];
      for (final mm in raw) {
        final date     = DateTime.parse(mm['date'] as String);
        final startRaw = mm['start_time'] as String?;
        final endRaw   = mm['end_time']   as String?;
        final start    = startRaw != null ? startRaw.substring(0, 5) : '09:00';
        final end      = endRaw   != null ? endRaw.substring(0, 5)   : '00:00';
        final isJpHol   = StoreSettingsService.isHoliday(date, holidays);
        final isHoliday = isJpHol || d.holidayWeekdays.contains(date.weekday % 7);
        records.add(_ShiftRecord(
          date:      date,
          startTime: start,
          endTime:   end,
          isHoliday: isHoliday,
        ));
      }
      if (mounted) setState(() => d.shifts = records);
    } catch (e) {
      debugPrint('_loadShifts error: $e');
    } finally {
      if (mounted) setState(() => d.shiftsLoading = false);
    }
  }

  Future<bool> _isPersonalStore(String storeId) async {
    try {
      final data = await _supabase
          .from('personal_stores')
          .select('id')
          .eq('id', storeId)
          .maybeSingle();
      return data != null;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadActuals() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final rows = await _supabase
          .from('staff_payroll_actuals')
          .select()
          .eq('user_id', userId)
          .eq('year', _year)
          .eq('month', _month);
      for (final r in rows) {
        final m       = Map<String, dynamic>.from(r as Map);
        final storeId = m['store_id'] as String;
        final pay     = m['actual_pay'] as int?;
        final d = _storeData.where((d) => d.storeId == storeId).firstOrNull;
        if (d != null && mounted) {
          setState(() {
            d.actualPay       = pay;
            d.actualCtrl.text = pay != null ? pay.toString() : '';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _saveActual(_StoreData d, String value) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final pay = int.tryParse(value.replaceAll(',', ''));
    setState(() => d.actualSaving = true);
    try {
      await _supabase.from('staff_payroll_actuals').upsert(
        {
          'user_id':    userId,
          'store_id':   d.storeId,
          'year':       _year,
          'month':      _month,
          'actual_pay': pay,
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,store_id,year,month',
      );
      if (mounted) setState(() => d.actualPay = pay);
    } catch (_) {
    } finally {
      if (mounted) setState(() => d.actualSaving = false);
    }
  }

  Future<void> _reloadAll() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final storeIds = _storeData.map((d) => d.storeId).toList();
    try {
      final rows = await _supabase
          .from('staff_payroll_settings')
          .select()
          .eq('user_id', userId)
          .inFilter('store_id', storeIds);
      for (final r in rows) {
        final m       = Map<String, dynamic>.from(r as Map);
        final storeId = m['store_id'] as String;
        final d = _storeData.where((d) => d.storeId == storeId).firstOrNull;
        if (d != null) {
          setState(() {
            d.hourlyWage      = m['hourly_wage']      as int?    ?? 0;
            d.closingDay      = m['closing_day']      as int?    ?? 0;
            d.paymentMonth    = PaymentMonth.values[m['payment_month'] as int? ?? 1];
            d.roundingUnit    = RoundingUnit.values[m['rounding_unit'] as int? ?? 0];
            d.roundingDir     = RoundingDir.values[m['rounding_dir']   as int? ?? 0];
            d.weekdayClose    = m['weekday_close']    as String? ?? '22:00';
            d.holidayClose    = m['holiday_close']    as String? ?? '22:00';
            d.commuteFee      = m['commute_fee']      as int?    ?? 0;
            d.holidayWageRate = m['holiday_wage']     as int?    ?? 0;
            d.holidayWeekdays = _parseHolidayWeekdays(m['holiday_weekdays']);
            d.lateNightWage   = m['late_night_wage']  as int?    ?? 0;
            d.lateNightStart  = m['late_night_start'] as String? ?? '22:00';
            d.lateNightEnd    = m['late_night_end']   as String? ?? '05:00';
          });
        }
      }
    } catch (_) {}
    await Future.wait([
      for (final d in _storeData) _loadShifts(d),
      _loadActuals(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('給料計算'),
        backgroundColor: const Color(0xFF2C7873),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reloadAll,
            tooltip: '再読み込み',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildMonthSelector(),
          Expanded(
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator())
                : _storeData.isEmpty
                    ? const Center(child: Text('店舗情報が取得できませんでした'))
                    : _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final totalMin    = _storeData.fold(0, (a, d) => a + d.totalMinutes);
    final totalEst    = _storeData.fold(0, (a, d) => a + d.totalWage);
    final totalAct    = _storeData.every((d) => d.actualPay != null)
        ? _storeData.fold(0, (a, d) => a + (d.actualPay ?? 0))
        : null;
    final allHaveWage = _storeData.every((d) => d.hourlyWage > 0);
    final h = totalMin ~/ 60;
    final m = totalMin % 60;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C7873), Color(0xFF52B69A)],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(
              color: const Color(0xFF2C7873).withOpacity(0.3),
              blurRadius: 8, offset: const Offset(0, 3),
            )],
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.functions, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Text('$_year年$_month月払い 合計',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('総勤務時間',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text('${h}時間${m}分',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 22,
                              fontWeight: FontWeight.bold)),
                    ],
                  )),
                  Container(width: 1, height: 50, color: Colors.white24),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('概算給与',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        allHaveWage ? '¥${_fmt(totalEst)}' : '—',
                        style: TextStyle(
                          color: allHaveWage ? Colors.white : Colors.white38,
                          fontSize: allHaveWage ? 22 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )),
                  Container(width: 1, height: 50, color: Colors.white24),
                  const SizedBox(width: 16),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('実績合計',
                          style: TextStyle(color: Colors.white60, fontSize: 11)),
                      const SizedBox(height: 4),
                      Text(
                        totalAct != null ? '¥${_fmt(totalAct)}' : '—',
                        style: TextStyle(
                          color: totalAct != null ? Colors.white : Colors.white38,
                          fontSize: totalAct != null ? 22 : 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  )),
                ],
              ),
            ],
          ),
        ),

        ...(_storeData.map((d) => _buildStoreCard(d))),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildStoreCard(_StoreData d) {
    final period  = d.calcPayPeriod(_year, _month);
    final h       = d.totalMinutes ~/ 60;
    final m       = d.totalMinutes % 60;
    final hasWage = d.hourlyWage > 0;

    final hasBase      = d.totalBaseWage > 0;
    final hasHoliday   = d.totalHolidayWage > 0;
    final hasLateNight = d.totalLateNight > 0;
    final hasCommute   = d.totalCommute > 0;
    final hasBreakdown = hasWage && (hasBase || hasHoliday || hasLateNight || hasCommute);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        width: 14, height: 14,
                        decoration: BoxDecoration(
                          color: d.displayColor,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(d.storeName,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black87)),
                            Text(period.label,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: d.shiftsLoading
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('勤務時間',
                                style: TextStyle(fontSize: 10, color: Colors.grey)),
                            const SizedBox(height: 2),
                            Text(
                              d.shifts.isEmpty ? '--' : '${h}h${m}m',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                ),
                Expanded(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('給料見込',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            !hasWage ? '未設定' : '¥${_fmt(d.totalWage)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: hasWage ? Colors.black87 : Colors.orange,
                            ),
                          ),
                          if (hasBreakdown) ...[
                            const SizedBox(width: 2),
                            GestureDetector(
                              onTap: () => setState(
                                  () => d.breakdownExpanded = !d.breakdownExpanded),
                              child: Icon(
                                d.breakdownExpanded
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Text('給料実績',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                      const SizedBox(height: 2),
                      SizedBox(
                        height: 32,
                        child: TextField(
                          controller: d.actualCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            hintText: '未入力',
                            hintStyle: const TextStyle(
                                fontSize: 12, color: Colors.grey),
                            isDense: true,
                            prefixText:
                                d.actualCtrl.text.isNotEmpty ? '¥' : null,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            border: const OutlineInputBorder(),
                            suffixIcon: d.actualSaving
                                ? const SizedBox(
                                    width: 14, height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : null,
                          ),
                          onSubmitted: (v) => _saveActual(d, v),
                          onTapOutside: (_) =>
                              _saveActual(d, d.actualCtrl.text),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          if (hasBreakdown && d.breakdownExpanded)
            Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: const BorderRadius.only(
                  bottomLeft:  Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: const [
                        Expanded(flex: 3, child: Text('項目',
                            style: TextStyle(fontSize: 10, color: Colors.grey))),
                        Expanded(flex: 3, child: Text('時給/金額',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey))),
                        Expanded(flex: 3, child: Text('時間/日数',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 10, color: Colors.grey))),
                        Expanded(flex: 2, child: Text('小計',
                            textAlign: TextAlign.right,
                            style: TextStyle(fontSize: 10, color: Colors.grey))),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  const SizedBox(height: 4),

                  // 基本給料（平日 + 休日時給未設定の休日をまとめて表示）
                  if (hasBase)
                    _breakdownDetailRow(
                      label:    '基本給料',
                      wage:     d.hourlyWage,
                      duration: _fmtMin(d.totalBaseMinutes),
                      amount:   d.totalBaseWage,
                      color:    d.displayColor,
                    ),

                  // 休日給料（休日時給設定あり時のみ表示）
                  if (hasHoliday)
                    _breakdownDetailRow(
                      label:    '休日給料',
                      wage:     d.holidayWageRate,
                      duration: _fmtMin(d.holidayMinutes),
                      amount:   d.totalHolidayWage,
                      color:    Colors.orange,
                    ),

                  if (hasLateNight)
                    _breakdownDetailRow(
                      label:    '深夜給料',
                      wage:     d.lateNightWage,
                      duration: _fmtMin(d.totalLateNightMinutes),
                      amount:   d.totalLateNight,
                      color:    Colors.indigo,
                    ),

                  if (hasCommute)
                    _breakdownDetailRow(
                      label:    '交通費',
                      wage:     d.commuteFee,
                      duration: '${d.shifts.length}日',
                      amount:   d.totalCommute,
                      color:    Colors.teal,
                    ),

                  const Divider(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      const Text('合計',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                      const SizedBox(width: 12),
                      Text('¥${_fmt(d.totalWage)}',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _breakdownDetailRow({
    required String label,
    required int    wage,
    required String duration,
    required int    amount,
    required Color  color,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.8),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.black87)),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Text('¥${_fmt(wage)}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('×  ', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text(duration,
                    style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text('¥${_fmt(amount)}',
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87)),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Container(
      color: const Color(0xFFE8F4F3),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, color: Color(0xFF2C7873)),
            onPressed: () {
              setState(() {
                if (_month == 1) { _year--; _month = 12; }
                else { _month--; }
              });
              _reloadAll();
            },
          ),
          Text('$_year年$_month月払い',
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7873))),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF2C7873)),
            onPressed: () {
              setState(() {
                if (_month == 12) { _year++; _month = 1; }
                else { _month++; }
              });
              _reloadAll();
            },
          ),
        ],
      ),
    );
  }

  String _fmt(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  String _fmtMin(int totalMin) {
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    return '${h}h${m.toString().padLeft(2, '0')}m';
  }
}