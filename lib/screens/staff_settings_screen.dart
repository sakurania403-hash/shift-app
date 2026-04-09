import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/store_settings_service.dart';

final _supabase = Supabase.instance.client;

// ─── カラーパレット ────────────────────────────────────────────
const kStoreColorPalette = [
  Color(0xFF2C7873),
  Color(0xFFE07B39),
  Color(0xFF6C5CE7),
  Color(0xFFE84393),
  Color(0xFF00B894),
  Color(0xFFE17055),
  Color(0xFF0984E3),
  Color(0xFFD63031),
  Color(0xFFFDAB4D),
  Color(0xFF55EFC4),
  Color(0xFF74B9FF),
  Color(0xFFB2BEC3),
  Color(0xFF636E72),
  Color(0xFFA29BFE),
  Color(0xFFFD79A8),
  Color(0xFF00CEC9),
];

String _colorToHex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}'
    '${c.green.toRadixString(16).padLeft(2, '0')}'
    '${c.blue.toRadixString(16).padLeft(2, '0')}';

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return const Color(0xFF2C7873);
  return Color(int.parse('FF$h', radix: 16));
}

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

const kWeekdayLabels = ['月', '火', '水', '木', '金', '土', '日', '祝'];

// ─── メイン設定画面 ────────────────────────────────────────────
class StaffSettingsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> stores;
  final VoidCallback? onSaved;
  const StaffSettingsScreen({super.key, required this.stores, this.onSaved});

  @override
  State<StaffSettingsScreen> createState() => StaffSettingsScreenState();
}

class StaffSettingsScreenState extends State<StaffSettingsScreen> {
  String _email = '';

  // storeId → 表示色（リロード後に更新）
  Map<String, Color> _colorMap = {};

  @override
  void initState() {
    super.initState();
    _email = _supabase.auth.currentUser?.email ?? '';
    _buildColorMap();
  }

  void _buildColorMap() {
    _colorMap = {};
    for (var i = 0; i < widget.stores.length; i++) {
      final m        = widget.stores[i];
      final store    = _toMap(m['stores']);
      final id       = store['id'] as String;
      final colorHex = m['display_color'] as String?;
      _colorMap[id]  = (colorHex != null && colorHex.isNotEmpty)
          ? _hexToColor(colorHex)
          : kStoreColorPalette[i % kStoreColorPalette.length];
    }
  }

  // ─── 外から呼べる色リロードメソッド ──────────────────────────
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

      if (mounted) {
        setState(() {
          for (var i = 0; i < widget.stores.length; i++) {
            final store = _toMap(widget.stores[i]['stores']);
            final id    = store['id'] as String;
            final matching = rows
                .where((r) => (r as Map)['store_id'] == id)
                .toList();
            if (matching.isNotEmpty) {
              final hex = (matching.first as Map)['display_color'] as String?;
              if (hex != null && hex.isNotEmpty) {
                _colorMap[id] = _hexToColor(hex);
              } else {
                _colorMap[id] = kStoreColorPalette[i % kStoreColorPalette.length];
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('settings reloadColors error: $e');
    }
  }

  Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    return Map<String, dynamic>.from(v as Map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      body: ListView(
        children: [
          _sectionHeader('アカウント'),
          Container(
            color: Colors.white,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFE0E0E0),
                child: Icon(Icons.person, color: Colors.white, size: 28),
              ),
              title: Text(
                _email.isNotEmpty ? _email : '未ログイン',
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ),

          _sectionHeader('勤務先'),
          Container(
            color: Colors.white,
            child: Column(
              children: [
                for (var i = 0; i < widget.stores.length; i++) ...[
                  _buildStoreRow(widget.stores[i], i),
                  if (i < widget.stores.length - 1)
                    const Divider(height: 1, indent: 16),
                ],
              ],
            ),
          ),

          _sectionHeader('設定'),
          Container(
            color: Colors.white,
            child: ListTile(
              leading: const Icon(Icons.notifications_outlined,
                  color: Color(0xFF2C7873), size: 22),
              title: const Text('通知の設定', style: TextStyle(fontSize: 15)),
              trailing: const Icon(Icons.chevron_right,
                  color: Colors.grey, size: 20),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('通知設定は今後実装予定です')),
                );
              },
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(title,
          style: const TextStyle(
              fontSize: 13,
              color: Colors.grey,
              fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildStoreRow(Map<String, dynamic> m, int index) {
    final store = _toMap(m['stores']);
    final id    = store['id'] as String;
    final name  = store['name'] as String? ?? '';
    final color = _colorMap[id] ??
        kStoreColorPalette[index % kStoreColorPalette.length];

    return ListTile(
      leading: Container(
        width: 12, height: 12,
        margin: const EdgeInsets.only(left: 4),
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      title: Text(name, style: const TextStyle(fontSize: 15)),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _StoreDetailScreen(
              storeData: m,
              colorIndex: index,
              onSaved: widget.onSaved,
            ),
          ),
        );
        // 詳細画面から戻ったら色を再取得
        await reloadColors();
      },
    );
  }
}

// ─── 店舗詳細・編集画面 ────────────────────────────────────────
class _StoreDetailScreen extends StatefulWidget {
  final Map<String, dynamic> storeData;
  final int colorIndex;
  final VoidCallback? onSaved;
  const _StoreDetailScreen({
    required this.storeData,
    required this.colorIndex,
    this.onSaved,
  });

  @override
  State<_StoreDetailScreen> createState() => _StoreDetailScreenState();
}

class _StoreDetailScreenState extends State<_StoreDetailScreen> {
  final _settingsService = StoreSettingsService();
  bool _loading = true;
  bool _saving  = false;

  late String storeId;
  late String storeName;
  late Color  displayColor;

  int    hourlyWage     = 0;
  int    commuteFee     = 0;
  int    holidayWage    = 0;
  List<String> holidayWeekdays = [];
  int    lateNightWage  = 0;
  String lateNightStart = '22:00';
  String lateNightEnd   = '05:00';

  int          closingDay   = 0;
  PaymentMonth paymentMonth = PaymentMonth.nextMonth;

  RoundingUnit roundingUnit = RoundingUnit.minute;
  RoundingDir  roundingDir  = RoundingDir.truncate;
  String       weekdayClose = '22:00';
  String       holidayClose = '22:00';

  late TextEditingController _wageCtrl;
  late TextEditingController _commuteCtrl;
  late TextEditingController _holidayWageCtrl;
  late TextEditingController _lateNightWageCtrl;
  late TextEditingController _lateNightStartCtrl;
  late TextEditingController _lateNightEndCtrl;
  late TextEditingController _weekdayCloseCtrl;
  late TextEditingController _holidayCloseCtrl;

  Map<String, dynamic> _toMap(dynamic v) {
    if (v == null) return {};
    if (v is Map<String, dynamic>) return v;
    return Map<String, dynamic>.from(v as Map);
  }

  @override
  void initState() {
    super.initState();
    final store    = _toMap(widget.storeData['stores']);
    storeId        = store['id'] as String;
    storeName      = store['name'] as String? ?? '';
    final colorHex = widget.storeData['display_color'] as String?;
    displayColor   = (colorHex != null && colorHex.isNotEmpty)
        ? _hexToColor(colorHex)
        : kStoreColorPalette[widget.colorIndex % kStoreColorPalette.length];

    _wageCtrl           = TextEditingController();
    _commuteCtrl        = TextEditingController();
    _holidayWageCtrl    = TextEditingController();
    _lateNightWageCtrl  = TextEditingController();
    _lateNightStartCtrl = TextEditingController(text: '22:00');
    _lateNightEndCtrl   = TextEditingController(text: '05:00');
    _weekdayCloseCtrl   = TextEditingController(text: '22:00');
    _holidayCloseCtrl   = TextEditingController(text: '22:00');

    _loadSettings();
  }

  @override
  void dispose() {
    _wageCtrl.dispose();
    _commuteCtrl.dispose();
    _holidayWageCtrl.dispose();
    _lateNightWageCtrl.dispose();
    _lateNightStartCtrl.dispose();
    _lateNightEndCtrl.dispose();
    _weekdayCloseCtrl.dispose();
    _holidayCloseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) { setState(() => _loading = false); return; }

    try {
      final row = await _supabase
          .from('staff_payroll_settings')
          .select()
          .eq('user_id', userId)
          .eq('store_id', storeId)
          .maybeSingle();

      if (row != null) {
        final s = Map<String, dynamic>.from(row as Map);
        hourlyWage     = s['hourly_wage']      as int?    ?? 0;
        commuteFee     = s['commute_fee']      as int?    ?? 0;
        holidayWage    = s['holiday_wage']     as int?    ?? 0;
        lateNightWage  = s['late_night_wage']  as int?    ?? 0;
        lateNightStart = s['late_night_start'] as String? ?? '22:00';
        lateNightEnd   = s['late_night_end']   as String? ?? '05:00';
        closingDay     = s['closing_day']      as int?    ?? 0;
        paymentMonth   = PaymentMonth.values[s['payment_month'] as int? ?? 1];
        roundingUnit   = RoundingUnit.values[s['rounding_unit'] as int? ?? 0];
        roundingDir    = RoundingDir.values[s['rounding_dir']   as int? ?? 0];
        weekdayClose   = s['weekday_close']    as String? ?? '22:00';
        holidayClose   = s['holiday_close']    as String? ?? '22:00';

        final raw = s['holiday_weekdays'];
        if (raw is List) {
          holidayWeekdays = raw.map((e) => e.toString()).toList();
        }

        _wageCtrl.text           = hourlyWage > 0    ? hourlyWage.toString()    : '';
        _commuteCtrl.text        = commuteFee > 0    ? commuteFee.toString()    : '';
        _holidayWageCtrl.text    = holidayWage > 0   ? holidayWage.toString()   : '';
        _lateNightWageCtrl.text  = lateNightWage > 0 ? lateNightWage.toString() : '';
        _lateNightStartCtrl.text = lateNightStart;
        _lateNightEndCtrl.text   = lateNightEnd;
        _weekdayCloseCtrl.text   = weekdayClose;
        _holidayCloseCtrl.text   = holidayClose;
      }
    } catch (e) {
      debugPrint('loadSettings error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _saving = true);
    try {
      await _supabase.from('staff_payroll_settings').upsert(
        {
          'user_id':          userId,
          'store_id':         storeId,
          'hourly_wage':      hourlyWage,
          'commute_fee':      commuteFee,
          'holiday_wage':     holidayWage,
          'holiday_weekdays': holidayWeekdays,
          'late_night_wage':  lateNightWage,
          'late_night_start': lateNightStart,
          'late_night_end':   lateNightEnd,
          'closing_day':      closingDay,
          'payment_month':    paymentMonth.index,
          'rounding_unit':    roundingUnit.index,
          'rounding_dir':     roundingDir.index,
          'weekday_close':    weekdayClose,
          'holiday_close':    holidayClose,
          'updated_at':       DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,store_id',
      );
      if (mounted) {
        widget.onSaved?.call();
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$storeName の設定を保存しました'),
          backgroundColor: const Color(0xFF2C7873),
          duration: const Duration(seconds: 2),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('保存失敗: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveColor(Color color) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('store_memberships')
          .update({'display_color': _colorToHex(color)})
          .eq('user_id', userId)
          .eq('store_id', storeId);
      setState(() => displayColor = color);
    } catch (e) {
      debugPrint('saveColor error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: Text(storeName),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C7873),
        elevation: 0.5,
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('保存',
                    style: TextStyle(
                        color: Color(0xFF2C7873),
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _sectionHeader('表示色'),
                _buildColorSection(),
                _sectionHeader('給料情報'),
                _buildPaySection(),
                _sectionHeader('締日・給料日'),
                _buildClosingSection(),
                _sectionHeader('計算設定'),
                _buildCalcSection(),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(title,
          style: const TextStyle(
              fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildColorSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24, height: 24,
                decoration: BoxDecoration(
                    color: displayColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 10),
              Text(_colorName(displayColor),
                  style: const TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: kStoreColorPalette.map((color) {
              final isSelected = displayColor.value == color.value;
              return GestureDetector(
                onTap: () => _saveColor(color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 2.5)
                        : null,
                    boxShadow: isSelected
                        ? [BoxShadow(
                            color: color.withOpacity(0.6),
                            blurRadius: 6, spreadRadius: 1)]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  String _colorName(Color c) {
    final hex = _colorToHex(c).toUpperCase();
    const names = {
      '#2C7873': 'ダークティール',
      '#E07B39': 'オレンジ',
      '#6C5CE7': 'パープル',
      '#E84393': 'ピンク',
      '#00B894': 'グリーン',
      '#E17055': 'コーラル',
      '#0984E3': 'ブルー',
      '#D63031': 'レッド',
      '#FDAB4D': 'イエロー',
      '#55EFC4': 'ミント',
      '#74B9FF': 'ライトブルー',
      '#B2BEC3': 'シルバー',
      '#636E72': 'グレー',
      '#A29BFE': 'ラベンダー',
      '#FD79A8': 'ライトピンク',
      '#00CEC9': 'シアン',
    };
    return names[hex] ?? hex;
  }

  Widget _buildPaySection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildInputRow(
            label: '基本時給',
            controller: _wageCtrl,
            suffix: '円',
            onChanged: (v) => hourlyWage = int.tryParse(v) ?? 0,
          ),
          const Divider(height: 1, indent: 16),
          _buildInputRow(
            label: '交通費',
            controller: _commuteCtrl,
            suffix: '円/日',
            onChanged: (v) => commuteFee = int.tryParse(v) ?? 0,
          ),
          const Divider(height: 1, indent: 16),
          _buildExpandable(
            label: '休日給料',
            summary: holidayWage > 0 ? '¥$holidayWage/時' : '未設定',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInputRow(
                  label: '休日時給',
                  controller: _holidayWageCtrl,
                  suffix: '円',
                  onChanged: (v) => holidayWage = int.tryParse(v) ?? 0,
                  isIndented: true,
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text('対象日',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Wrap(
                    spacing: 8, runSpacing: 8,
                    children: kWeekdayLabels.map((wd) {
                      final selected = holidayWeekdays.contains(wd);
                      return GestureDetector(
                        onTap: () => setState(() {
                          if (selected) {
                            holidayWeekdays.remove(wd);
                          } else {
                            holidayWeekdays.add(wd);
                          }
                        }),
                        child: Container(
                          width: 40, height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? const Color(0xFF2C7873)
                                : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(wd,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: selected
                                      ? Colors.white
                                      : Colors.black54)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, indent: 16),
          _buildExpandable(
            label: '深夜手当',
            summary: lateNightWage > 0 ? '¥$lateNightWage/時' : '未設定',
            child: Column(
              children: [
                _buildInputRow(
                  label: '深夜時給',
                  controller: _lateNightWageCtrl,
                  suffix: '円',
                  onChanged: (v) => lateNightWage = int.tryParse(v) ?? 0,
                  isIndented: true,
                ),
                const Divider(height: 1, indent: 32),
                _buildInputRow(
                  label: '開始時間',
                  controller: _lateNightStartCtrl,
                  suffix: '',
                  hintText: '22:00',
                  onChanged: (v) => lateNightStart = v.trim(),
                  isIndented: true,
                ),
                const Divider(height: 1, indent: 32),
                _buildInputRow(
                  label: '終了時間',
                  controller: _lateNightEndCtrl,
                  suffix: '',
                  hintText: '05:00',
                  onChanged: (v) => lateNightEnd = v.trim(),
                  isIndented: true,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClosingSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          ListTile(
            title: const Text('締日', style: TextStyle(fontSize: 15)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(closingDay == 0 ? '末日' : '毎月$closingDay日',
                    style: const TextStyle(
                        fontSize: 14, color: Colors.grey)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
              ],
            ),
            onTap: _showClosingDayPicker,
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            title: const Text('給料日', style: TextStyle(fontSize: 15)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(paymentMonth.label,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.grey)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
              ],
            ),
            onTap: _showPaymentMonthPicker,
          ),
        ],
      ),
    );
  }

  Widget _buildCalcSection() {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          ListTile(
            title: const Text('計算単位', style: TextStyle(fontSize: 15)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(roundingUnit.label,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.grey)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
              ],
            ),
            onTap: () => _showPicker(
              title: '計算単位',
              items: RoundingUnit.values.map((u) => u.label).toList(),
              selectedIndex: roundingUnit.index,
              onSelected: (i) =>
                  setState(() => roundingUnit = RoundingUnit.values[i]),
            ),
          ),
          const Divider(height: 1, indent: 16),
          ListTile(
            title: const Text('端数処理', style: TextStyle(fontSize: 15)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(roundingDir.label,
                    style: const TextStyle(
                        fontSize: 14, color: Colors.grey)),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: Colors.grey, size: 20),
              ],
            ),
            onTap: () => _showPicker(
              title: '端数処理',
              items: RoundingDir.values.map((d) => d.label).toList(),
              selectedIndex: roundingDir.index,
              onSelected: (i) =>
                  setState(() => roundingDir = RoundingDir.values[i]),
            ),
          ),
          const Divider(height: 1, indent: 16),
          _buildInputRow(
            label: '平日終業',
            controller: _weekdayCloseCtrl,
            suffix: '',
            hintText: '22:00',
            onChanged: (v) => weekdayClose = v.trim(),
          ),
          const Divider(height: 1, indent: 16),
          _buildInputRow(
            label: '土日祝終業',
            controller: _holidayCloseCtrl,
            suffix: '',
            hintText: '22:00',
            onChanged: (v) => holidayClose = v.trim(),
          ),
        ],
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    required String suffix,
    String? hintText,
    required Function(String) onChanged,
    bool isIndented = false,
  }) {
    final isNumeric = suffix == '円' || suffix == '円/日';
    return Padding(
      padding: EdgeInsets.symmetric(
          horizontal: isIndented ? 32.0 : 16.0, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 15, color: Colors.black87)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType:
                  isNumeric ? TextInputType.number : TextInputType.text,
              inputFormatters: isNumeric
                  ? [FilteringTextInputFormatter.digitsOnly]
                  : [],
              textAlign: TextAlign.right,
              decoration: InputDecoration(
                hintText: hintText,
                suffixText: suffix.isNotEmpty ? suffix : null,
                border: InputBorder.none,
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14),
              ),
              style: const TextStyle(
                  fontSize: 15, color: Colors.black87),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandable({
    required String label,
    required String summary,
    required Widget child,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: EdgeInsets.zero,
        title: Text(label, style: const TextStyle(fontSize: 15)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(summary,
                style: const TextStyle(
                    fontSize: 14, color: Colors.grey)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right,
                color: Colors.grey, size: 20),
          ],
        ),
        children: [
          Container(
            color: const Color(0xFFF9FFFE),
            child: child,
          ),
        ],
      ),
    );
  }

  void _showClosingDayPicker() {
    final items = ['末日締め',
      ...List.generate(28, (i) => '${i + 1}日締め')];
    _showPicker(
      title: '締日',
      items: items,
      selectedIndex: closingDay == 0 ? 0 : closingDay,
      onSelected: (i) => setState(() => closingDay = i == 0 ? 0 : i),
    );
  }

  void _showPaymentMonthPicker() {
    _showPicker(
      title: '給料日',
      items: PaymentMonth.values.map((p) => p.label).toList(),
      selectedIndex: paymentMonth.index,
      onSelected: (i) =>
          setState(() => paymentMonth = PaymentMonth.values[i]),
    );
  }

  void _showPicker({
    required String title,
    required List<String> items,
    required int selectedIndex,
    required Function(int) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('閉じる',
                      style: TextStyle(color: Color(0xFF2C7873))),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 280,
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(items[i]),
                trailing: i == selectedIndex
                    ? const Icon(Icons.check,
                        color: Color(0xFF2C7873))
                    : null,
                onTap: () {
                  onSelected(i);
                  Navigator.pop(context);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}