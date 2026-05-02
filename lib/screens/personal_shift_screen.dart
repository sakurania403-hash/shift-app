import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalShiftScreen extends StatefulWidget {
  const PersonalShiftScreen({super.key});

  @override
  State<PersonalShiftScreen> createState() => _PersonalShiftScreenState();
}

class _PersonalShiftScreenState extends State<PersonalShiftScreen> {
  final _supabase = Supabase.instance.client;
  DateTime _focusedMonth = DateTime.now();
  List<Map<String, dynamic>> _shifts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadShifts();
  }

  Future<void> _loadShifts() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final firstDay =
          DateTime(_focusedMonth.year, _focusedMonth.month, 1);
      final lastDay =
          DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);

      final data = await _supabase
          .from('personal_shifts')
          .select()
          .eq('user_id', userId)
          .gte('date', firstDay.toIso8601String().substring(0, 10))
          .lte('date', lastDay.toIso8601String().substring(0, 10))
          .order('date');

      if (mounted) {
        setState(() {
          _shifts = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _prevMonth() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
    });
    _loadShifts();
  }

  void _nextMonth() {
    setState(() {
      _focusedMonth =
          DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
    });
    _loadShifts();
  }

  Future<void> _showShiftDialog({Map<String, dynamic>? existing}) async {
    final dateController = TextEditingController(
      text: existing?['date'] ?? '',
    );
    final startController = TextEditingController(
      text: existing?['start_time'] ?? '',
    );
    final endController = TextEditingController(
      text: existing?['end_time'] ?? '',
    );
    final memoController = TextEditingController(
      text: existing?['memo'] ?? '',
    );

    DateTime? selectedDate = existing != null
        ? DateTime.tryParse(existing['date'])
        : null;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? 'シフトを追加' : 'シフトを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 日付選択
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: selectedDate ?? DateTime.now(),
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                      locale: const Locale('ja', 'JP'),
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedDate = picked;
                        dateController.text =
                            picked.toIso8601String().substring(0, 10);
                      });
                    }
                  },
                  child: AbsorbPointer(
                    child: TextField(
                      controller: dateController,
                      decoration: const InputDecoration(
                        labelText: '日付',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.calendar_today),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // 開始時間
                TextField(
                  controller: startController,
                  decoration: const InputDecoration(
                    labelText: '開始時間（例: 09:00）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time),
                  ),
                  keyboardType: TextInputType.datetime,
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
                  readOnly: true,
                ),
                const SizedBox(height: 12),
                // 終了時間
                TextField(
                  controller: endController,
                  decoration: const InputDecoration(
                    labelText: '終了時間（例: 17:00）',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.access_time_filled),
                  ),
                  keyboardType: TextInputType.datetime,
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
                  readOnly: true,
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
                child: const Text('削除', style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (dateController.text.isEmpty ||
                    startController.text.isEmpty ||
                    endController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('日付・開始時間・終了時間は必須です')),
                  );
                  return;
                }
                await _saveShift(
                  id: existing?['id'],
                  date: dateController.text,
                  startTime: startController.text,
                  endTime: endController.text,
                  memo: memoController.text,
                );
                if (mounted) Navigator.pop(context);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveShift({
    String? id,
    required String date,
    required String startTime,
    required String endTime,
    String? memo,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final data = {
      'user_id': userId,
      'date': date,
      'start_time': startTime,
      'end_time': endTime,
      'memo': memo ?? '',
    };

    if (id == null) {
      await _supabase.from('personal_shifts').insert(data);
    } else {
      await _supabase.from('personal_shifts').update(data).eq('id', id);
    }
    await _loadShifts();
  }

  Future<void> _deleteShift(String id) async {
    await _supabase.from('personal_shifts').delete().eq('id', id);
    await _loadShifts();
  }

  double _calcHours(String start, String end) {
    try {
      final s = start.split(':');
      final e = end.split(':');
      final startMin = int.parse(s[0]) * 60 + int.parse(s[1]);
      var endMin = int.parse(e[0]) * 60 + int.parse(e[1]);
      if (endMin < startMin) endMin += 24 * 60; // 日をまたぐ場合
      return (endMin - startMin) / 60.0;
    } catch (_) {
      return 0;
    }
  }

  double get _totalHours {
    return _shifts.fold(0.0, (sum, s) {
      return sum + _calcHours(s['start_time'], s['end_time']);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 月切り替えヘッダー
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _prevMonth,
                      ),
                      Text(
                        '${_focusedMonth.year}年${_focusedMonth.month}月',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _nextMonth,
                      ),
                    ],
                  ),
                ),
                // 合計時間サマリー
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text(
                            '今月の勤務日数',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            '${_shifts.length}日',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        children: [
                          const Text(
                            '今月の合計時間',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          Text(
                            '${_totalHours.toStringAsFixed(1)}h',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // シフト一覧
                Expanded(
                  child: _shifts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 8),
                              Text(
                                'シフトがありません',
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: () => _showShiftDialog(),
                                icon: const Icon(Icons.add),
                                label: const Text('シフトを追加'),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _shifts.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final s = _shifts[i];
                            final date =
                                DateTime.tryParse(s['date'] ?? '');
                            final weekdays = [
                              '月', '火', '水', '木', '金', '土', '日'
                            ];
                            final weekday = date != null
                                ? weekdays[date.weekday - 1]
                                : '';
                            final hours = _calcHours(
                                s['start_time'], s['end_time']);
                            return Card(
                              elevation: 1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                onTap: () =>
                                    _showShiftDialog(existing: s),
                                leading: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color:
                                        const Color(0xFFE8F5F0),
                                    borderRadius:
                                        BorderRadius.circular(8),
                                  ),
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        date != null
                                            ? '${date.day}'
                                            : '-',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 16,
                                          color: Colors.teal,
                                        ),
                                      ),
                                      Text(
                                        weekday,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Colors.teal,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                title: Text(
                                  '${s['start_time']} 〜 ${s['end_time']}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                ),
                                subtitle: s['memo'] != null &&
                                        s['memo'].isNotEmpty
                                    ? Text(s['memo'])
                                    : null,
                                trailing: Text(
                                  '${hours.toStringAsFixed(1)}h',
                                  style: const TextStyle(
                                    color: Colors.teal,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      floatingActionButton: _shifts.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showShiftDialog(),
              backgroundColor: Colors.teal,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}