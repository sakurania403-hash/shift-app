import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_settings_service.dart';

final _supabase = Supabase.instance.client;

// ─── 列挙型（payroll_screen と同じ定義）────────────────────────
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

// ─── 店舗ごとの設定モデル ────────────────────────────────────────
class _StoreSettings {
  final String storeId;
  final String storeName;
  int          hourlyWage;
  RoundingUnit roundingUnit;
  RoundingDir  roundingDir;
  int          closingDay;
  PaymentMonth paymentMonth;
  String       weekdayClose;
  String       holidayClose;
  List<Map<String, dynamic>> breakRules = [];
  bool saving = false;

  late TextEditingController wageCtrl;
  late TextEditingController weekdayCloseCtrl;
  late TextEditingController holidayCloseCtrl;

  _StoreSettings({
    required this.storeId,
    required this.storeName,
    this.hourlyWage   = 0,
    this.roundingUnit = RoundingUnit.minute,
    this.roundingDir  = RoundingDir.truncate,
    this.closingDay   = 0,
    this.paymentMonth = PaymentMonth.nextMonth,
    this.weekdayClose = '22:00',
    this.holidayClose = '22:00',
  }) {
    wageCtrl         = TextEditingController(
        text: hourlyWage > 0 ? hourlyWage.toString() : '');
    weekdayCloseCtrl = TextEditingController(text: weekdayClose);
    holidayCloseCtrl = TextEditingController(text: holidayClose);
  }

  void dispose() {
    wageCtrl.dispose();
    weekdayCloseCtrl.dispose();
    holidayCloseCtrl.dispose();
  }
}

// ─── メイン画面 ────────────────────────────────────────────────
class StaffSettingsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  const StaffSettingsScreen({super.key, required this.stores});

  @override
  State<StaffSettingsScreen> createState() => _StaffSettingsScreenState();
}

class _StaffSettingsScreenState extends State<StaffSettingsScreen> {
  bool _loading = true;
  List<_StoreSettings> _settings = [];
  String? _expandedStoreId;
  final _settingsService = StoreSettingsService();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final s in _settings) s.dispose();
    super.dispose();
  }

  Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    return Map<String, dynamic>.from(v as Map);
  }

  Future<void> _init() async {
    final userId = _supabase.auth.currentUser?.id;
    Map<String, Map<String, dynamic>> savedMap = {};

    if (userId != null) {
      final storeIds = widget.stores
          .map((m) => _toMap(m['stores'])['id'] as String)
          .toList();
      try {
        final rows = await _supabase
            .from('staff_payroll_settings')
            .select()
            .eq('user_id', userId)
            .inFilter('store_id', storeIds);
        for (final r in rows) {
          final m = Map<String, dynamic>.from(r as Map);
          savedMap[m['store_id'] as String] = m;
        }
      } catch (_) {}
    }

    final list = <_StoreSettings>[];
    for (final m in widget.stores) {
      final store   = _toMap(m['stores']);
      final storeId = store['id'] as String;
      final name    = store['name'] as String? ?? '';
      final saved   = savedMap[storeId];

      final s = _StoreSettings(
        storeId:      storeId,
        storeName:    name,
        hourlyWage:   saved?['hourly_wage']   as int?    ?? 0,
        closingDay:   saved?['closing_day']   as int?    ?? 0,
        paymentMonth: PaymentMonth.values[saved?['payment_month'] as int? ?? 1],
        roundingUnit: RoundingUnit.values[saved?['rounding_unit'] as int? ?? 0],
        roundingDir:  RoundingDir.values[saved?['rounding_dir']   as int? ?? 0],
        weekdayClose: saved?['weekday_close'] as String? ?? '22:00',
        holidayClose: saved?['holiday_close'] as String? ?? '22:00',
      );
      try { s.breakRules = await _settingsService.getBreakRules(storeId); }
      catch (_) {}
      list.add(s);
    }

    if (mounted) {
      setState(() {
        _settings = list;
        _loading  = false;
      });
    }
  }

  // ─── 保存 ────────────────────────────────────────────────────
  Future<void> _save(_StoreSettings s) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => s.saving = true);
    try {
      await _supabase.from('staff_payroll_settings').upsert(
        {
          'user_id':       userId,
          'store_id':      s.storeId,
          'hourly_wage':   s.hourlyWage,
          'closing_day':   s.closingDay,
          'payment_month': s.paymentMonth.index,
          'rounding_unit': s.roundingUnit.index,
          'rounding_dir':  s.roundingDir.index,
          'weekday_close': s.weekdayClose,
          'holiday_close': s.holidayClose,
          'updated_at':    DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,store_id',
      );
      if (mounted) {
        setState(() => _expandedStoreId = null);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${s.storeName} の設定を保存しました'),
          backgroundColor: const Color(0xFF2C7873),
          duration: const Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('保存失敗: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => s.saving = false);
    }
  }

  // ─── UI ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                // セクションタイトル
                const Padding(
                  padding: EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Icon(Icons.calculate_outlined,
                          size: 18, color: Color(0xFF2C7873)),
                      SizedBox(width: 8),
                      Text('給料計算設定',
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF2C7873))),
                    ],
                  ),
                ),
                ..._settings.map((s) => _buildAccordion(s)),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  // ─── アコーディオン ───────────────────────────────────────────
  Widget _buildAccordion(_StoreSettings s) {
    final isExpanded = _expandedStoreId == s.storeId;
    final hasWage    = s.hourlyWage > 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ─── ヘッダー行 ────────────────────────────────────
          InkWell(
            onTap: () => setState(() =>
                _expandedStoreId = isExpanded ? null : s.storeId),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isExpanded
                    ? const Color(0xFF2C7873)
                    : Colors.white,
              ),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(
                      color: isExpanded
                          ? Colors.white
                          : const Color(0xFF2C7873),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(s.storeName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: isExpanded
                              ? Colors.white
                              : const Color(0xFF2C7873),
                        )),
                  ),
                  // 設定済みサマリー
                  if (!isExpanded)
                    Text(
                      hasWage
                          ? '時給 ¥${s.hourlyWage}　${_closingLabel(s.closingDay)}　${s.paymentMonth.label}'
                          : '未設定',
                      style: TextStyle(
                        fontSize: 11,
                        color: hasWage ? Colors.grey : Colors.orange,
                      ),
                    ),
                  const SizedBox(width: 8),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isExpanded ? Colors.white : Colors.grey,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ─── 展開時: 設定フォーム ─────────────────────────
          if (isExpanded) _buildForm(s),
        ],
      ),
    );
  }

  String _closingLabel(int day) => day == 0 ? '末日締め' : '$day日締め';

  // ─── 設定フォーム ─────────────────────────────────────────────
  Widget _buildForm(_StoreSettings s) {
    final closingItems = <DropdownMenuItem<int>>[
      const DropdownMenuItem(
          value: 0,
          child: Text('末日締め', style: TextStyle(fontSize: 13))),
      ...List.generate(28, (i) => i + 1).map((d) => DropdownMenuItem(
            value: d,
            child: Text('$d日締め', style: const TextStyle(fontSize: 13)),
          )),
    ];

    String breakText = s.breakRules.isEmpty
        ? '未設定'
        : s.breakRules.map((r) {
            final h = (r['work_hours_threshold'] as num).toStringAsFixed(0);
            return '$h時間以上→${r['break_minutes']}分';
          }).join('、');

    return Container(
      color: const Color(0xFFF9FFFE),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 時給
          _row('時給', TextField(
            controller: s.wageCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              prefixText: '¥ ', hintText: '例: 1050', isDense: true,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            onChanged: (v) =>
                setState(() => s.hourlyWage = int.tryParse(v) ?? 0),
          )),
          const SizedBox(height: 12),

          // 締め日
          _row('締め日', DropdownButtonFormField<int>(
            value: s.closingDay,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: closingItems,
            onChanged: (v) {
              if (v != null) setState(() => s.closingDay = v);
            },
          )),
          const SizedBox(height: 12),

          // 支払い
          _row('支払い', DropdownButtonFormField<PaymentMonth>(
            value: s.paymentMonth,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: PaymentMonth.values
                .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(p.label,
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => s.paymentMonth = v);
            },
          )),
          const SizedBox(height: 12),

          // 計算単位
          _row('計算単位', DropdownButtonFormField<RoundingUnit>(
            value: s.roundingUnit,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: RoundingUnit.values
                .map((u) => DropdownMenuItem(
                      value: u,
                      child: Text(u.label,
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => s.roundingUnit = v);
            },
          )),
          const SizedBox(height: 12),

          // 端数処理
          _row('端数処理', DropdownButtonFormField<RoundingDir>(
            value: s.roundingDir,
            isDense: true,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            items: RoundingDir.values
                .map((d) => DropdownMenuItem(
                      value: d,
                      child: Text(d.label,
                          style: const TextStyle(fontSize: 13)),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) setState(() => s.roundingDir = v);
            },
          )),
          const SizedBox(height: 16),

          // 営業終了時間
          const Divider(height: 1),
          const SizedBox(height: 12),
          const Text('営業終了時間（「ラスト」シフトの退勤時間）',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Color(0xFF2C7873))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('平日',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: s.weekdayCloseCtrl,
                  decoration: const InputDecoration(
                    hintText: '22:00', isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    suffixText: '終業',
                  ),
                  onChanged: (v) =>
                      setState(() => s.weekdayClose = v.trim()),
                ),
              ],
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('土日・祝日',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 4),
                TextField(
                  controller: s.holidayCloseCtrl,
                  decoration: const InputDecoration(
                    hintText: '22:00', isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    suffixText: '終業',
                  ),
                  onChanged: (v) =>
                      setState(() => s.holidayClose = v.trim()),
                ),
              ],
            )),
          ]),
          const SizedBox(height: 12),

          // 休憩ルール（読み取り専用）
          const Divider(height: 1),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF8),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.teal.withOpacity(0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.coffee, size: 15, color: Colors.teal),
                const SizedBox(width: 6),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('休憩ルール（店舗設定から自動適用）',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.teal,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text(breakText,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black87)),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 12),

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
                Icon(Icons.info_outline, size: 14, color: Colors.orange),
                SizedBox(width: 6),
                Expanded(child: Text(
                  '計算結果はあくまで概算です。実際の給与は店舗のルールや控除により異なる場合があります。',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                )),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 完了ボタン
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: s.saving ? null : () => _save(s),
              icon: s.saving
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check, size: 18),
              label: Text(s.saving ? '保存中...' : '完了（設定を保存）'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C7873),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, Widget child) {
    return Row(
      children: [
        SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 13))),
        Expanded(child: child),
      ],
    );
  }
}