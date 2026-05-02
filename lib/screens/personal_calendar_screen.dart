import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'personal_store_screen.dart';

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return const Color(0xFF2C7873);
  return Color(int.parse('FF$h', radix: 16));
}

class PersonalCalendarScreen extends StatefulWidget {
  const PersonalCalendarScreen({super.key});

  @override
  State<PersonalCalendarScreen> createState() =>
      PersonalCalendarScreenState();
}

class PersonalCalendarScreenState extends State<PersonalCalendarScreen> {
  final _supabase = Supabase.instance.client;
  late int _year;
  late int _month;
  bool _loading = true;
  List<Map<String, dynamic>> _shifts = [];
  List<Map<String, dynamic>> _stores = [];
  String? _selectedDateStr;
  String? _selectedStoreId; // 選択中の職場

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year  = now.year;
    _month = now.month;
    _loadAll();
  }

  Future<void> _loadAll() async {
    await _loadStores();
    await _loadShifts();
  }

  Future<void> _loadStores() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('personal_stores')
          .select()
          .eq('user_id', userId)
          .order('sort_order');
      if (mounted) {
        setState(() {
          _stores = List<Map<String, dynamic>>.from(data);
          // 職場が1つ以上あればデフォルト選択
          if (_stores.isNotEmpty && _selectedStoreId == null) {
            _selectedStoreId = _stores.first['id'] as String;
          }
        });
      }
    } catch (e) {
      debugPrint('loadStores error: $e');
    }
  }

  Future<void> _loadShifts() async {
    setState(() => _loading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final fromStr =
          DateTime(_year, _month, 1).toIso8601String().substring(0, 10);
      final toStr =
          DateTime(_year, _month + 1, 0).toIso8601String().substring(0, 10);

      var query = _supabase
          .from('personal_shifts')
          .select()
          .eq('user_id', userId)
          .gte('date', fromStr)
          .lte('date', toStr)
          .order('date');

      final data = await query;
      if (mounted) {
        setState(() {
          _shifts = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('loadShifts error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _selectedDateStr = null;
      if (_month == 1) { _year--; _month = 12; } else { _month--; }
    });
    _loadShifts();
  }

  void _nextMonth() {
    setState(() {
      _selectedDateStr = null;
      if (_month == 12) { _year++; _month = 1; } else { _month++; }
    });
    _loadShifts();
  }

  void _onDayTap(String dateStr) {
    if (_stores.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に職場を登録してください')),
      );
      return;
    }
    setState(() => _selectedDateStr = dateStr);
    final existing = _shifts.where((s) =>
        s['date'] == dateStr &&
        s['personal_store_id'] == _selectedStoreId).toList();
    _showShiftDialog(
      dateStr: dateStr,
      existing: existing.isNotEmpty ? existing.first : null,
    );
  }

  Future<void> _showShiftDialog({
    required String dateStr,
    Map<String, dynamic>? existing,
  }) async {
    final startController =
        TextEditingController(text: existing?['start_time'] ?? '');
    final endController =
        TextEditingController(text: existing?['end_time'] ?? '');
    final memoController =
        TextEditingController(text: existing?['memo'] ?? '');

    // ダイアログ内で職場選択
    String dialogStoreId = existing?['personal_store_id'] as String? ??
        _selectedStoreId ?? _stores.first['id'] as String;

    final date = DateTime.parse(dateStr);
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    final weekday = weekdays[date.weekday - 1];
    final title = '${date.month}月${date.day}日（$weekday）';

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '$title のシフトを追加' : '$title のシフトを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 職場選択
                if (_stores.length > 1)
                  DropdownButtonFormField<String>(
                    value: dialogStoreId,
                    decoration: const InputDecoration(
                      labelText: '職場',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.store),
                    ),
                    items: _stores.map((s) {
                      final color = _hexToColor(
                          s['color'] as String? ?? '#2C7873');
                      return DropdownMenuItem<String>(
                        value: s['id'] as String,
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: color, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 8),
                            Text(s['name'] as String),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (v) =>
                        setDialogState(() => dialogStoreId = v!),
                  ),
                if (_stores.length > 1) const SizedBox(height: 12),
                // 開始時間
                TextField(
                  controller: startController,
                  decoration: const InputDecoration(
                    labelText: '開始時間',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (picked != null) {
                      startController.text =
                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                    }
                  },
                ),
                const SizedBox(height: 12),
                // 終了時間
                TextField(
                  controller: endController,
                  decoration: const InputDecoration(
                    labelText: '終了時間',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time_filled),
                  ),
                  readOnly: true,
                  onTap: () async {
                    final picked = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.now(),
                    );
                    if (picked != null) {
                      endController.text =
                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                    }
                  },
                ),
                const SizedBox(height: 12),
                // メモ
                TextField(
                  controller: memoController,
                  decoration: const InputDecoration(
                    labelText: 'メモ（任意）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await _deleteShift(existing['id']);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('削除',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (startController.text.isEmpty ||
                    endController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('開始時間・終了時間は必須です')),
                  );
                  return;
                }
                await _saveShift(
                  id: existing?['id'],
                  date: dateStr,
                  storeId: dialogStoreId,
                  startTime: startController.text,
                  endTime: endController.text,
                  memo: memoController.text,
                );
                if (mounted) Navigator.pop(context);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: Colors.teal),
              child: const Text('保存',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveShift({
    String? id,
    required String date,
    required String storeId,
    required String startTime,
    required String endTime,
    String? memo,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = {
      'user_id':            userId,
      'personal_store_id':  storeId,
      'date':               date,
      'start_time':         startTime,
      'end_time':           endTime,
      'memo':               memo ?? '',
    };
    if (id == null) {
      await _supabase.from('personal_shifts').insert(data);
    } else {
      await _supabase
          .from('personal_shifts')
          .update(data)
          .eq('id', id);
    }
    await _loadShifts();
  }

  Future<void> _deleteShift(String id) async {
    await _supabase.from('personal_shifts').delete().eq('id', id);
    await _loadShifts();
  }

  Color _storeColor(String? storeId) {
    if (storeId == null) return Colors.teal;
    final store = _stores.where((s) => s['id'] == storeId).firstOrNull;
    if (store == null) return Colors.teal;
    return _hexToColor(store['color'] as String? ?? '#2C7873');
  }

  List<Widget> _buildChips(String dateStr) {
    final shifts = (_selectedStoreId == null
            ? _shifts
            : _shifts.where((s) =>
                s['personal_store_id'] == _selectedStoreId).toList())
        .where((s) => s['date'] == dateStr)
        .toList();
    return shifts.map((s) {
      final start = (s['start_time'] as String).substring(0, 5);
      final end   = (s['end_time']   as String).substring(0, 5);
      final isLast = end == '00:00';
      final color = _storeColor(s['personal_store_id'] as String?);
      return Container(
        margin: const EdgeInsets.only(bottom: 2),
        padding:
            const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(3),
          border:
              Border.all(color: color.withOpacity(0.5), width: 0.8),
        ),
        child: Text(
          '$start〜${isLast ? 'ラスト' : end}',
          style: TextStyle(
              fontSize: 9,
              color: color,
              fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();
  }

  double _calendarHeight(BuildContext context) {
    final firstDay    = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWd     = firstDay.weekday % 7;
    final rows        = ((startWd + daysInMonth) / 7).ceil();
    return rows * 60.0;
  }

  @override
  Widget build(BuildContext context) {
    final today      = DateTime.now();
    final isNowMonth = today.year == _year && today.month == _month;
    final firstDay    = DateTime(_year, _month, 1);
    final daysInMonth = DateTime(_year, _month + 1, 0).day;
    final startWd     = firstDay.weekday % 7;
    final rows        = ((startWd + daysInMonth) / 7).ceil();

    // 職場フィルター適用後のシフト
    final filteredShifts = _selectedStoreId == null
        ? _shifts
        : _shifts.where((s) => s['personal_store_id'] == _selectedStoreId).toList();

    double totalHours = 0;
    for (final s in filteredShifts) {
      try {
        final sp = (s['start_time'] as String).split(':');
        final ep = (s['end_time']   as String).split(':');
        final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
        var   em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
        if (em <= sm) em += 24 * 60;
        totalHours += (em - sm) / 60.0;
      } catch (_) {}
    }

    return Column(
      children: [
        // ヘッダー
        Container(
          color: const Color(0xFFE8F4F3),
          padding:
              const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left,
                    color: Color(0xFF2C7873)),
                onPressed: _prevMonth,
              ),
              Text('$_year年$_month月',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2C7873))),
              IconButton(
                icon: const Icon(Icons.chevron_right,
                    color: Color(0xFF2C7873)),
                onPressed: _nextMonth,
              ),
            ],
          ),
        ),
        // 職場選択タブ
        if (_stores.isNotEmpty)
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  // 全職場表示
                  GestureDetector(
                    onTap: () =>
                        setState(() => _selectedStoreId = null),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _selectedStoreId == null
                            ? Colors.teal
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text('すべて',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _selectedStoreId == null
                                  ? Colors.white
                                  : Colors.black54)),
                    ),
                  ),
                  ..._stores.map((s) {
                    final id    = s['id'] as String;
                    final name  = s['name'] as String;
                    final color = _hexToColor(
                        s['color'] as String? ?? '#2C7873');
                    final isSelected = _selectedStoreId == id;
                    return GestureDetector(
                      onTap: () =>
                          setState(() => _selectedStoreId = id),
                      child: Container(
                        margin: const EdgeInsets.only(right: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? color
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(name,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black54)),
                      ),
                    );
                  }),
                  // 職場追加ボタン
                  GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PersonalStoreScreen(
                              onChanged: _loadAll,
                            ),
                          ),
                        );
                        await _loadAll();
                      },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.grey.shade300),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.add,
                              size: 14, color: Colors.grey),
                          SizedBox(width: 4),
                          Text('職場を追加',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
       // 合計サマリー
        Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                const Text('勤務日数',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey)),
                Text('${filteredShifts.length}日',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
              ]),
              Column(children: [
                const Text('合計時間',
                    style:
                        TextStyle(fontSize: 11, color: Colors.grey)),
                Text('${totalHours.toStringAsFixed(1)}h',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal)),
              ]),
            ],
          ),
        ),
        // 曜日行
        Container(
          color: const Color(0xFFF5F7FA),
          child: Row(
            children: ['日', '月', '火', '水', '木', '金', '土']
                .asMap()
                .entries
                .map((e) => Expanded(
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(vertical: 4),
                        alignment: Alignment.center,
                        child: Text(e.value,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: e.key == 0
                                    ? const Color(0xFFE53935)
                                    : e.key == 6
                                        ? const Color(0xFF1565C0)
                                        : Colors.black87)),
                      ),
                    ))
                .toList(),
          ),
        ),
        // カレンダーグリッド
        SizedBox(
          height: _calendarHeight(context),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    childAspectRatio:
                        MediaQuery.of(context).size.width / 7 / 60.0,
                  ),
                  itemCount: rows * 7,
                  itemBuilder: (context, index) {
                    final dayNum = index - startWd + 1;
                    if (dayNum < 1 || dayNum > daysInMonth) {
                      return Container(
                          decoration: BoxDecoration(
                              border: Border.all(
                                  color: Colors.grey.shade100)));
                    }
                    final date =
                        DateTime(_year, _month, dayNum);
                    final dateStr = date
                        .toIso8601String()
                        .substring(0, 10);
                    final wd      = date.weekday % 7;
                    final isToday =
                        isNowMonth && today.day == dayNum;
                    final isSelected =
                        _selectedDateStr == dateStr;
                    final isSunday   = wd == 0;
                    final isSaturday = wd == 6;
                    final chips = _buildChips(dateStr);

                    return GestureDetector(
                      onTap: () => _onDayTap(dateStr),
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFD0EFEB)
                              : isToday
                                  ? const Color(0xFFE8F4F3)
                                  : Colors.white,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF2C7873)
                                : Colors.grey.shade200,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              alignment: Alignment.center,
                              decoration: isToday
                                  ? const BoxDecoration(
                                      color: Color(0xFF2C7873),
                                      shape: BoxShape.circle)
                                  : null,
                              child: Text('$dayNum',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isToday
                                        ? Colors.white
                                        : isSunday
                                            ? const Color(
                                                0xFFE53935)
                                            : isSaturday
                                                ? const Color(
                                                    0xFF1565C0)
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
                ),
        ),
        // 下部プレースホルダー
        Expanded(
          child: Container(
            color: const Color(0xFFF5F7FA),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app_outlined,
                      size: 36, color: Colors.grey[400]),
                  const SizedBox(height: 8),
                  Text(
                    _stores.isEmpty
                        ? '職場を登録してからシフトを入力できます'
                        : '日付をタップしてシフトを登録',
                    style: TextStyle(
                        color: Colors.grey[500], fontSize: 13),
                  ),
                  if (_stores.isEmpty) ...[
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                const PersonalStoreScreen(),
                          ),
                        );
                        await _loadAll();
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('職場を追加'),
                      style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}