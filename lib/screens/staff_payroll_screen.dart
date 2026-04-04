import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_settings_service.dart';

final _supabase = Supabase.instance.client;

// ─── 給与計算方式 ───────────────────────────────────────────────
enum RoundingUnit { minute, min15, min30, hour }

extension RoundingUnitExt on RoundingUnit {
  String get label {
    switch (this) {
      case RoundingUnit.minute:
        return '1分単位';
      case RoundingUnit.min15:
        return '15分単位';
      case RoundingUnit.min30:
        return '30分単位';
      case RoundingUnit.hour:
        return '1時間単位';
    }
  }
}

enum RoundingDir { truncate, round, ceil }

extension RoundingDirExt on RoundingDir {
  String get label {
    switch (this) {
      case RoundingDir.truncate:
        return '切り捨て';
      case RoundingDir.round:
        return '四捨五入';
      case RoundingDir.ceil:
        return '切り上げ';
    }
  }
}

enum PaymentMonth { sameMonth, nextMonth }

extension PaymentMonthExt on PaymentMonth {
  String get label {
    switch (this) {
      case PaymentMonth.sameMonth:
        return '当月末払い';
      case PaymentMonth.nextMonth:
        return '翌月末払い';
    }
  }
}

// ─── データモデル ───────────────────────────────────────────────
class _ShiftRecord {
  final DateTime date;
  final String startTime;
  final String endTime;

  _ShiftRecord({
    required this.date,
    required this.startTime,
    required this.endTime,
  });

  int get rawMinutes {
    final sMin = _toMin(startTime);
    var eMin = _toMin(endTime);
    if (eMin <= sMin) eMin += 24 * 60;
    return eMin - sMin;
  }

  static int _toMin(String t) {
    final p = t.split(':');
    if (p.length < 2) return 0;
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }
}

// ─── 集計期間 ───────────────────────────────────────────────────
class _PayPeriod {
  final DateTime periodStart;
  final DateTime periodEnd;

  _PayPeriod({required this.periodStart, required this.periodEnd});

  String get label {
    String fmt(DateTime d) => '${d.month}/${d.day}';
    return '${fmt(periodStart)} 〜 ${fmt(periodEnd)}';
  }
}

// ─── メイン画面 ────────────────────────────────────────────────
class StaffPayrollScreen extends StatefulWidget {
  final String storeId;
  const StaffPayrollScreen({super.key, required this.storeId});

  @override
  State<StaffPayrollScreen> createState() => _StaffPayrollScreenState();
}

class _StaffPayrollScreenState extends State<StaffPayrollScreen> {
  late int _year;
  late int _month;

  List<_ShiftRecord> _shifts = [];
  bool _loading = false;
  String? _error;

  // 計算設定（SharedPreferences）
  int _hourlyWage = 0;
  RoundingUnit _roundingUnit = RoundingUnit.minute;
  RoundingDir _roundingDir = RoundingDir.truncate;
  int _closingDay = 0; // 0=末日締め、1〜28=N日締め
  PaymentMonth _paymentMonth = PaymentMonth.nextMonth;
  // 営業時間（ラスト計算用、スタッフがローカル設定）
  String _weekdayCloseTime = '22:00'; // 平日営業終了
  String _holidayCloseTime = '22:00'; // 休日営業終了

  // 店舗の休憩ルール（Supabaseから取得）
  List<Map<String, dynamic>> _breakRules = [];

  final _settingsService = StoreSettingsService();
  final _wageController = TextEditingController();
  final _weekdayCloseController = TextEditingController();
  final _holidayCloseController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _loadPrefs().then((_) => _loadAll());
  }

  @override
  void dispose() {
    _wageController.dispose();
    _weekdayCloseController.dispose();
    _holidayCloseController.dispose();
    super.dispose();
  }

  // ─── SharedPreferences ──────────────────────────────────────
  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hourlyWage = prefs.getInt('payroll_wage') ?? 0;
      _roundingUnit =
          RoundingUnit.values[prefs.getInt('payroll_unit') ?? 0];
      _roundingDir =
          RoundingDir.values[prefs.getInt('payroll_dir') ?? 0];
      _closingDay = prefs.getInt('payroll_closing_day') ?? 0;
      _paymentMonth = PaymentMonth
          .values[prefs.getInt('payroll_payment_month') ?? 1];
      _weekdayCloseTime =
          prefs.getString('payroll_weekday_close') ?? '22:00';
      _holidayCloseTime =
          prefs.getString('payroll_holiday_close') ?? '22:00';

      _wageController.text =
          _hourlyWage > 0 ? _hourlyWage.toString() : '';
      _weekdayCloseController.text = _weekdayCloseTime;
      _holidayCloseController.text = _holidayCloseTime;
    });
  }

  Future<void> _savePrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('payroll_wage', _hourlyWage);
    await prefs.setInt('payroll_unit', _roundingUnit.index);
    await prefs.setInt('payroll_dir', _roundingDir.index);
    await prefs.setInt('payroll_closing_day', _closingDay);
    await prefs.setInt(
        'payroll_payment_month', _paymentMonth.index);
    await prefs.setString(
        'payroll_weekday_close', _weekdayCloseTime);
    await prefs.setString(
        'payroll_holiday_close', _holidayCloseTime);
  }

  // ─── 集計期間計算（選んだ月＝支払い月として逆算）────────────────
  _PayPeriod _calcPayPeriod() {
    int closeYear = _year;
    int closeMonth = _month;
    if (_paymentMonth == PaymentMonth.nextMonth) {
      closeMonth -= 1;
      if (closeMonth == 0) {
        closeMonth = 12;
        closeYear -= 1;
      }
    }

    DateTime periodStart;
    DateTime periodEnd;

    if (_closingDay == 0) {
      periodStart = DateTime(closeYear, closeMonth, 1);
      periodEnd = DateTime(closeYear, closeMonth + 1, 0);
    } else {
      periodEnd = DateTime(closeYear, closeMonth, _closingDay);
      final prevMonth =
          closeMonth == 1 ? 12 : closeMonth - 1;
      final prevYear =
          closeMonth == 1 ? closeYear - 1 : closeYear;
      periodStart =
          DateTime(prevYear, prevMonth, _closingDay + 1);
    }

    return _PayPeriod(
        periodStart: periodStart, periodEnd: periodEnd);
  }

  // ─── データ一括取得 ──────────────────────────────────────────
  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _breakRules =
          await _settingsService.getBreakRules(widget.storeId);
      await _loadShifts();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ─── シフト取得 ──────────────────────────────────────────────
  Future<void> _loadShifts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('未ログイン');

    final period = _calcPayPeriod();
    final holidays =
        await StoreSettingsService.getJapaneseHolidays();

    final raw = await _supabase
        .from('shifts')
        .select('date, start_time, end_time')
        .eq('store_id', widget.storeId)
        .eq('user_id', userId)
        .gte('date',
            period.periodStart.toIso8601String().substring(0, 10))
        .lte('date',
            period.periodEnd.toIso8601String().substring(0, 10))
        .order('date');

    final records = <_ShiftRecord>[];
    for (final r in raw) {
      final m = Map<String, dynamic>.from(r as Map);
      final date = DateTime.parse(m['date'] as String);
      final startTime = m['start_time'] as String? ?? '00:00';
      var endTime = m['end_time'] as String? ?? '00:00';

      // ラスト判定：end_time が 00:00 → スタッフ設定の営業終了時間で置き換え
      if (endTime.startsWith('00:00')) {
        final isHol =
            await StoreSettingsService.isHoliday(date, holidays);
        final closeTime =
            isHol ? _holidayCloseTime : _weekdayCloseTime;
        if (closeTime.isNotEmpty) {
          endTime = closeTime;
        }
      }

      records.add(_ShiftRecord(
        date: date,
        startTime: startTime.substring(0, 5),
        endTime: endTime.substring(0, 5),
      ));
    }

    if (mounted) setState(() => _shifts = records);
  }

  // ─── 計算ロジック ────────────────────────────────────────────
  int _autoBreakMinutes(int rawMinutes) {
    if (_breakRules.isEmpty) return 0;
    final workHours = rawMinutes / 60.0;
    int breakMin = 0;
    for (final rule in _breakRules) {
      final threshold =
          (rule['work_hours_threshold'] as num).toDouble();
      if (workHours >= threshold) {
        breakMin = rule['break_minutes'] as int;
      }
    }
    return breakMin;
  }

  int _workedMinutes(int i) {
    final rawMin = _shifts[i].rawMinutes;
    final breakMin = _autoBreakMinutes(rawMin);
    final net = (rawMin - breakMin).clamp(0, rawMin);
    int unit;
    switch (_roundingUnit) {
      case RoundingUnit.minute:
        unit = 1;
        break;
      case RoundingUnit.min15:
        unit = 15;
        break;
      case RoundingUnit.min30:
        unit = 30;
        break;
      case RoundingUnit.hour:
        unit = 60;
        break;
    }
    switch (_roundingDir) {
      case RoundingDir.truncate:
        return (net ~/ unit) * unit;
      case RoundingDir.round:
        return ((net / unit).round()) * unit;
      case RoundingDir.ceil:
        return ((net / unit).ceil()) * unit;
    }
  }

  int _dailyWage(int i) =>
      (_hourlyWage * _workedMinutes(i) / 60).floor();

  int get _totalMinutes =>
      List.generate(_shifts.length, (i) => _workedMinutes(i))
          .fold(0, (a, b) => a + b);

  int get _totalWage =>
      List.generate(_shifts.length, (i) => _dailyWage(i))
          .fold(0, (a, b) => a + b);

  // ─── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('給料計算'),
        backgroundColor: const Color(0xFF2C7873),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildMonthSelector(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError()
                    : ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _buildSettingsCard(),
                          const SizedBox(height: 12),
                          _buildTotalCard(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // ─── 月選択（＝支払い月）────────────────────────────────────
  Widget _buildMonthSelector() {
    return Container(
      color: const Color(0xFFE8F4F3),
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left,
                color: Color(0xFF2C7873)),
            onPressed: () {
              setState(() {
                if (_month == 1) {
                  _year--;
                  _month = 12;
                } else {
                  _month--;
                }
              });
              _loadAll();
            },
          ),
          Column(
            children: [
              Text(
                '$_year年$_month月払い',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2C7873),
                ),
              ),
              Text(
                '集計期間: ${_calcPayPeriod().label}',
                style:
                    const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right,
                color: Color(0xFF2C7873)),
            onPressed: () {
              setState(() {
                if (_month == 12) {
                  _year++;
                  _month = 1;
                } else {
                  _month++;
                }
              });
              _loadAll();
            },
          ),
        ],
      ),
    );
  }

  // ─── 設定カード ───────────────────────────────────────────────
  Widget _buildSettingsCard() {
    final closingDayItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem(
          value: 0,
          child: Text('末日締め', style: TextStyle(fontSize: 13))),
      ...List.generate(28, (i) => i + 1).map((d) => DropdownMenuItem(
            value: d,
            child: Text('$d日締め',
                style: const TextStyle(fontSize: 13)),
          )),
    ];

    String breakRuleText;
    if (_breakRules.isEmpty) {
      breakRuleText = '未設定';
    } else {
      breakRuleText = _breakRules.map((r) {
        final h =
            (r['work_hours_threshold'] as num).toStringAsFixed(0);
        final m = r['break_minutes'];
        return '$h時間以上→${m}分';
      }).join('、');
    }

    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '計算設定',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF2C7873)),
            ),
            const SizedBox(height: 14),

            // 時給
            _settingRow(
              label: '時給',
              child: TextField(
                controller: _wageController,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly
                ],
                decoration: const InputDecoration(
                  prefixText: '¥ ',
                  hintText: '例: 1050',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
                onChanged: (v) {
                  setState(
                      () => _hourlyWage = int.tryParse(v) ?? 0);
                  _savePrefs();
                },
              ),
            ),
            const SizedBox(height: 12),

            // 締め日
            _settingRow(
              label: '締め日',
              child: DropdownButtonFormField<int>(
                value: _closingDay,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
                items: closingDayItems,
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _closingDay = v);
                  _savePrefs();
                  _loadShifts();
                },
              ),
            ),
            const SizedBox(height: 12),

            // 支払い
            _settingRow(
              label: '支払い',
              child: DropdownButtonFormField<PaymentMonth>(
                value: _paymentMonth,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
                items: PaymentMonth.values
                    .map((p) => DropdownMenuItem(
                        value: p,
                        child: Text(p.label,
                            style:
                                const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _paymentMonth = v);
                  _savePrefs();
                  _loadShifts();
                },
              ),
            ),
            const SizedBox(height: 12),

            // 計算単位
            _settingRow(
              label: '計算単位',
              child: DropdownButtonFormField<RoundingUnit>(
                value: _roundingUnit,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
                items: RoundingUnit.values
                    .map((u) => DropdownMenuItem(
                        value: u,
                        child: Text(u.label,
                            style:
                                const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _roundingUnit = v);
                  _savePrefs();
                },
              ),
            ),
            const SizedBox(height: 12),

            // 端数処理
            _settingRow(
              label: '端数処理',
              child: DropdownButtonFormField<RoundingDir>(
                value: _roundingDir,
                isDense: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
                items: RoundingDir.values
                    .map((d) => DropdownMenuItem(
                        value: d,
                        child: Text(d.label,
                            style:
                                const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _roundingDir = v);
                  _savePrefs();
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── 営業時間（ラスト計算用）──────────────────────
            const Divider(height: 1),
            const SizedBox(height: 12),
            const Text(
              '営業終了時間（「ラスト」シフトの退勤時間）',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF2C7873)),
            ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FAF8),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                'シフトで「ラスト」を選択した日は、ここで設定した営業終了時間を退勤時間として給料を計算します。',
                style:
                    TextStyle(fontSize: 11, color: Colors.teal),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('平日',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _weekdayCloseController,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          hintText: '22:00',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          suffixText: '終業',
                        ),
                        onChanged: (v) {
                          setState(
                              () => _weekdayCloseTime = v.trim());
                          _savePrefs();
                          _loadShifts();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('土日・祝日',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: _holidayCloseController,
                        keyboardType: TextInputType.text,
                        decoration: const InputDecoration(
                          hintText: '22:00',
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          suffixText: '終業',
                        ),
                        onChanged: (v) {
                          setState(
                              () => _holidayCloseTime = v.trim());
                          _savePrefs();
                          _loadShifts();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // 休憩ルール（読み取り専用）
            const Divider(height: 1),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FAF8),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: Colors.teal.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.coffee,
                      size: 15, color: Colors.teal),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '休憩ルール（店舗設定から自動適用）',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.teal,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(breakRuleText,
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black87)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 注意書き
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 14, color: Colors.orange),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '計算結果はあくまで概算です。実際の給与は店舗のルールや控除により異なる場合があります。',
                      style: TextStyle(
                          fontSize: 11, color: Colors.orange),
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

  Widget _settingRow(
      {required String label, required Widget child}) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child:
              Text(label, style: const TextStyle(fontSize: 13)),
        ),
        Expanded(child: child),
      ],
    );
  }

  // ─── 合計カード ───────────────────────────────────────────────
  Widget _buildTotalCard() {
    final period = _calcPayPeriod();
    final h = _totalMinutes ~/ 60;
    final m = _totalMinutes % 60;
    final hasWage = _hourlyWage > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F4F3),
            borderRadius: const BorderRadius.vertical(
                top: Radius.circular(10)),
            border: Border.all(
                color:
                    const Color(0xFF2C7873).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.date_range,
                      size: 14, color: Color(0xFF2C7873)),
                  const SizedBox(width: 4),
                  Text(
                    '集計期間：${period.label}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF2C7873),
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  const Icon(Icons.payment,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    '$_year年${_month}月末払い',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF2C7873), Color(0xFF52B69A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(10)),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF2C7873)
                      .withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3))
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text('総勤務時間（休憩除く）',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      _shifts.isEmpty
                          ? '--'
                          : '${h}時間${m}分',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    Text('${_shifts.length}日勤務',
                        style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 12)),
                  ],
                ),
              ),
              Container(
                  width: 1,
                  height: 60,
                  color: Colors.white30),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text('概算給与',
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12)),
                    const SizedBox(height: 6),
                    Text(
                      !hasWage
                          ? '時給を入力'
                          : _shifts.isEmpty
                              ? '¥0'
                              : '¥${_fmt(_totalWage)}',
                      style: TextStyle(
                          color: hasWage
                              ? Colors.white
                              : Colors.white54,
                          fontSize: hasWage ? 26 : 14,
                          fontWeight: FontWeight.bold),
                    ),
                    if (hasWage) ...[
                      const SizedBox(height: 2),
                      Text('時給 ¥${_fmt(_hourlyWage)}',
                          style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildError() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('エラー: $_error',
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(
                onPressed: _loadAll,
                child: const Text('再読み込み')),
          ],
        ),
      );

  String _fmt(int v) => v.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},');
}