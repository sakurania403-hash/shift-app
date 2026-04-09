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

// ─── データモデル ───────────────────────────────────────────────
class _ShiftRecord {
  final DateTime date;
  final String startTime;
  final String endTime;
  _ShiftRecord({required this.date, required this.startTime, required this.endTime});

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

  // 設定（staff_payroll_settings から）
  int          hourlyWage   = 0;
  RoundingUnit roundingUnit = RoundingUnit.minute;
  RoundingDir  roundingDir  = RoundingDir.truncate;
  int          closingDay   = 0;
  PaymentMonth paymentMonth = PaymentMonth.nextMonth;
  String       weekdayClose = '22:00';
  String       holidayClose = '22:00';
  List<Map<String, dynamic>> breakRules = [];

  // シフト
  List<_ShiftRecord> shifts = [];
  bool shiftsLoading = false;

  // 給料実績
  int? actualPay;
  bool actualSaving = false;
  late TextEditingController actualCtrl;

  _StoreData({required this.storeId, required this.storeName}) {
    actualCtrl = TextEditingController();
  }

  void dispose() => actualCtrl.dispose();

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

  int dailyWage(int i) => (hourlyWage * workedMinutes(i) / 60).floor();

  int get totalMinutes =>
      List.generate(shifts.length, (i) => workedMinutes(i)).fold(0, (a, b) => a + b);
  int get totalWage =>
      List.generate(shifts.length, (i) => dailyWage(i)).fold(0, (a, b) => a + b);
}

// ─── メイン画面 ────────────────────────────────────────────────
class StaffPayrollScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? stores;
  final String? storeId;
  const StaffPayrollScreen({super.key, this.stores, this.storeId});

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> {
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

  // ─── 初期化 ──────────────────────────────────────────────────
  Future<void> _init() async {
    List<Map<String, dynamic>> storeList = [];
    if (widget.stores != null && widget.stores!.isNotEmpty) {
      storeList = widget.stores!;
    } else if (widget.storeId != null) {
      storeList = [{'stores': {'id': widget.storeId, 'name': '店舗'}}];
    }

    final userId = _supabase.auth.currentUser?.id;

    // 設定一括取得
    Map<String, Map<String, dynamic>> savedSettings = {};
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
    }

    final dataList = <_StoreData>[];
    for (final m in storeList) {
      final store   = _toMap(m['stores']);
      final storeId = store['id'] as String;
      final name    = store['name'] as String? ?? '';
      final saved   = savedSettings[storeId];

      final d = _StoreData(storeId: storeId, storeName: name);
      d.hourlyWage   = saved?['hourly_wage']   as int?    ?? 0;
      d.closingDay   = saved?['closing_day']   as int?    ?? 0;
      d.paymentMonth = PaymentMonth.values[saved?['payment_month'] as int? ?? 1];
      d.roundingUnit = RoundingUnit.values[saved?['rounding_unit'] as int? ?? 0];
      d.roundingDir  = RoundingDir.values[saved?['rounding_dir']   as int? ?? 0];
      d.weekdayClose = saved?['weekday_close'] as String? ?? '22:00';
      d.holidayClose = saved?['holiday_close'] as String? ?? '22:00';

      try { d.breakRules = await _settingsService.getBreakRules(storeId); } catch (_) {}
      dataList.add(d);
    }

    if (mounted) {
      setState(() {
        _storeData      = dataList;
        _initialLoading = false;
      });
    }

    // シフト・実績を並行取得
    await Future.wait([
      for (final d in dataList) _loadShifts(d),
      _loadActuals(),
    ]);
  }

  // ─── シフト取得 ──────────────────────────────────────────────
  Future<void> _loadShifts(_StoreData d) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => d.shiftsLoading = true);
    try {
      final period   = d.calcPayPeriod(_year, _month);
      final holidays = await StoreSettingsService.getJapaneseHolidays();
      final raw = await _supabase
          .from('shifts')
          .select('date, start_time, end_time')
          .eq('store_id', d.storeId)
          .eq('user_id', userId)
          .gte('date', period.periodStart.toIso8601String().substring(0, 10))
          .lte('date', period.periodEnd.toIso8601String().substring(0, 10))
          .order('date');

      final records = <_ShiftRecord>[];
      for (final r in raw) {
        final mm       = Map<String, dynamic>.from(r as Map);
        final date     = DateTime.parse(mm['date'] as String);
        final startRaw = mm['start_time'] as String?;
        final endRaw   = mm['end_time']   as String?;
        final start    = startRaw != null ? startRaw.substring(0, 5) : '09:00';
        var   end      = endRaw   != null ? endRaw.substring(0, 5)   : '00:00';
        if (end.startsWith('00:00')) {
          final isHol = await StoreSettingsService.isHoliday(date, holidays);
          final close = isHol ? d.holidayClose : d.weekdayClose;
          if (close.isNotEmpty) end = close;
        }
        records.add(_ShiftRecord(date: date, startTime: start, endTime: end));
      }
      if (mounted) setState(() => d.shifts = records);
    } catch (_) {
    } finally {
      if (mounted) setState(() => d.shiftsLoading = false);
    }
  }

  // ─── 給料実績取得 ────────────────────────────────────────────
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
            d.actualPay  = pay;
            d.actualCtrl.text = pay != null ? pay.toString() : '';
          });
        }
      }
    } catch (_) {}
  }

  // ─── 給料実績保存 ────────────────────────────────────────────
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
    // 設定を再読み込み（設定画面で変更された可能性）
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
            d.hourlyWage   = m['hourly_wage']   as int?    ?? 0;
            d.closingDay   = m['closing_day']   as int?    ?? 0;
            d.paymentMonth = PaymentMonth.values[m['payment_month'] as int? ?? 1];
            d.roundingUnit = RoundingUnit.values[m['rounding_unit'] as int? ?? 0];
            d.roundingDir  = RoundingDir.values[m['rounding_dir']   as int? ?? 0];
            d.weekdayClose = m['weekday_close'] as String? ?? '22:00';
            d.holidayClose = m['holiday_close'] as String? ?? '22:00';
          });
        }
      }
    } catch (_) {}
    await Future.wait([
      for (final d in _storeData) _loadShifts(d),
      _loadActuals(),
    ]);
  }

  // ─── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('給料計算'),
        backgroundColor: const Color(0xFF2C7873),
        foregroundColor: Colors.white,
        actions: [
          // 設定画面から戻ったとき再読み込み
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
    // 合計
    final totalMin  = _storeData.fold(0, (a, d) => a + d.totalMinutes);
    final totalEst  = _storeData.fold(0, (a, d) => a + d.totalWage);
    final totalAct  = _storeData.every((d) => d.actualPay != null)
        ? _storeData.fold(0, (a, d) => a + (d.actualPay ?? 0))
        : null;
    final allHaveWage = _storeData.every((d) => d.hourlyWage > 0);
    final h = totalMin ~/ 60;
    final m = totalMin % 60;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // ─── 合計サマリーカード ───────────────────────────────
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

        // ─── 店舗ごと行 ───────────────────────────────────────
        ...(_storeData.map((d) => _buildStoreRow(d))),
        const SizedBox(height: 24),
      ],
    );
  }

  // ─── 店舗行 ──────────────────────────────────────────────────
  Widget _buildStoreRow(_StoreData d) {
    final period  = d.calcPayPeriod(_year, _month);
    final h       = d.totalMinutes ~/ 60;
    final m       = d.totalMinutes % 60;
    final hasWage = d.hourlyWage > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 店舗名
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  const Icon(Icons.store, size: 16, color: Color(0xFF2C7873)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.storeName,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold,
                                color: Color(0xFF2C7873))),
                        Text(period.label,
                            style: const TextStyle(
                                fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // 勤務時間
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
            // 給料見込
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Text('給料見込',
                      style: TextStyle(fontSize: 10, color: Colors.grey)),
                  const SizedBox(height: 2),
                  Text(
                    !hasWage ? '未設定' : '¥${_fmt(d.totalWage)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: hasWage ? Colors.black87 : Colors.orange,
                    ),
                  ),
                ],
              ),
            ),
            // 給料実績
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
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: '未入力',
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                        isDense: true,
                        prefixText: d.actualCtrl.text.isNotEmpty ? '¥' : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        border: const OutlineInputBorder(),
                        suffixIcon: d.actualSaving
                            ? const SizedBox(
                                width: 14, height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : null,
                      ),
                      onSubmitted: (v) => _saveActual(d, v),
                      onTapOutside: (_) => _saveActual(d, d.actualCtrl.text),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 月選択 ──────────────────────────────────────────────────
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
                if (_month == 1) { _year--; _month = 12; } else { _month--; }
              });
              _reloadAll();
            },
          ),
          Text('$_year年$_month月払い',
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7873))),
          IconButton(
            icon: const Icon(Icons.chevron_right, color: Color(0xFF2C7873)),
            onPressed: () {
              setState(() {
                if (_month == 12) { _year++; _month = 1; } else { _month++; }
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
}