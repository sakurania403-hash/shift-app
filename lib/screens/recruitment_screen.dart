import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/recruitment_service.dart';
import '../services/store_service.dart';
import '../services/store_settings_service.dart';
import 'shift_request_screen.dart';
import 'admin_shift_overview_screen.dart';
import 'staff_confirmed_shift_screen.dart';

class RecruitmentScreen extends StatefulWidget {
  const RecruitmentScreen({super.key});

  @override
  State<RecruitmentScreen> createState() => _RecruitmentScreenState();
}

class _RecruitmentScreenState extends State<RecruitmentScreen> {
  final _recruitmentService = RecruitmentService();
  final _storeService = StoreService();
  final _settingsService = StoreSettingsService();
  List<Map<String, dynamic>> _recruitments = [];
  List<Map<String, dynamic>> _stores = [];
  String? _selectedStoreId;
  String? _selectedRole;
  String? _selectedStoreName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Map<String, dynamic> _toMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    return Map<String, dynamic>.from(value as Map);
  }

  Future<void> _loadStores() async {
    // ① stores取得 と 祝日キャッシュウォームアップ を並列実行
    final results = await Future.wait([
      _storeService.getMyStores(),
      StoreSettingsService.getJapaneseHolidays(), // 戻り値は使わないがキャッシュに乗せる
    ]);

    final stores = results[0] as List<Map<String, dynamic>>;

    String? storeId;
    String? storeName;
    String? role;

    if (stores.isNotEmpty) {
      final firstStore = _toMap(stores.first['stores']);
      storeId = firstStore['id'] as String?;
      storeName = firstStore['name'] as String?;
      role = stores.first['role'] as String?;
    }

    setState(() {
      _stores = stores;
      _selectedStoreId = storeId;
      _selectedStoreName = storeName;
      _selectedRole = role;
    });

    // ② storeIdが必要なので recruitments はここで取得（依存関係あり）
    if (storeId != null) await _loadRecruitments();

    setState(() => _isLoading = false);
  }

  Future<void> _loadRecruitments() async {
    if (_selectedStoreId == null) return;
    final result =
        await _recruitmentService.getRecruitments(_selectedStoreId!);
    setState(() => _recruitments = result);
  }

  Future<void> _showCreateDialog() async {
    final holidays = await StoreSettingsService.getJapaneseHolidays();

    final titleController = TextEditingController();
    DateTime? workStart;
    DateTime? workEnd;
    DateTime? requestStart;
    DateTime? requestEnd;
    final fmt = DateFormat('yyyy/MM/dd');

    if (!mounted) return;

    final step1Ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('シフト募集を作成 (1/2)'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'タイトル',
                    hintText: '例：5月前半シフト',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('勤務期間',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: context,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: workStart ?? DateTime.now(),
                              holidays: holidays,
                              title: '勤務開始日',
                            ),
                          );
                          if (d != null) setDialogState(() => workStart = d);
                        },
                        child: Text(workStart != null
                            ? fmt.format(workStart!)
                            : '開始日'),
                      ),
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('〜')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: context,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: workEnd ?? DateTime.now(),
                              holidays: holidays,
                              title: '勤務終了日',
                            ),
                          );
                          if (d != null) setDialogState(() => workEnd = d);
                        },
                        child: Text(
                            workEnd != null ? fmt.format(workEnd!) : '終了日'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('希望提出期間',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: context,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: requestStart ?? DateTime.now(),
                              holidays: holidays,
                              title: '提出開始日',
                            ),
                          );
                          if (d != null) {
                            setDialogState(() => requestStart = d);
                          }
                        },
                        child: Text(requestStart != null
                            ? fmt.format(requestStart!)
                            : '開始日'),
                      ),
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('〜')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: context,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: requestEnd ?? DateTime.now(),
                              holidays: holidays,
                              title: '提出締切日',
                            ),
                          );
                          if (d != null) {
                            setDialogState(() => requestEnd = d);
                          }
                        },
                        child: Text(requestEnd != null
                            ? fmt.format(requestEnd!)
                            : '締切日'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                if (titleController.text.trim().isEmpty ||
                    workStart == null ||
                    workEnd == null ||
                    requestStart == null ||
                    requestEnd == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('すべての項目を入力してください')),
                  );
                  return;
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('次へ'),
            ),
          ],
        ),
      ),
    );

    if (step1Ok != true) return;

    final Set<DateTime> selectedHolidays = {};
    final List<Map<String, dynamic>> specialPeriods = [];

    if (!mounted) return;
    final step2Ok = await showDialog<bool>(
      context: context,
      builder: (context) => _Step2Dialog(
        workStart: workStart!,
        workEnd: workEnd!,
        selectedHolidays: selectedHolidays,
        specialPeriods: specialPeriods,
        japaneseHolidays: holidays,
      ),
    );

    if (step2Ok != true) return;

    final recruitment = await _recruitmentService.createRecruitment(
      storeId: _selectedStoreId!,
      title: titleController.text.trim(),
      workStart: workStart!,
      workEnd: workEnd!,
      requestStart: requestStart!,
      requestEnd: requestEnd!,
    );

    final recruitmentId = recruitment['id'] as String;

    for (final date in selectedHolidays) {
      await _settingsService.addShiftHoliday(
        recruitmentId: recruitmentId,
        storeId: _selectedStoreId!,
        date: date,
      );
    }

    for (final period in specialPeriods) {
      await _settingsService.addSpecialPeriod(
        recruitmentId: recruitmentId,
        storeId: _selectedStoreId!,
        label: period['label'] as String,
        startDate: period['start_date'] as DateTime,
        endDate: period['end_date'] as DateTime,
        minStaffOverride: period['min_staff_override'] as int,
      );
    }

    await _loadRecruitments();
  }

  // 再募集確認ダイアログ
  Future<void> _showReopenDialog(Map<String, dynamic> r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('再募集する'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${r['title']}」を再募集状態に戻します。'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'スタッフは再度希望シフトを編集・提出できるようになります。\n確定済みのシフトはそのまま残ります。',
                style: TextStyle(fontSize: 12, color: Colors.teal),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('再募集する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    await _recruitmentService.reopenRecruitment(r['id']);
    await _loadRecruitments();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('再募集に戻しました'),
          backgroundColor: Colors.teal,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('yyyy/MM/dd');
    final isAdmin = _selectedRole == 'admin';

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      body: Column(
        children: [
          if (_stores.length > 1)
            Padding(
              padding: const EdgeInsets.all(12),
              child: DropdownButtonFormField<String>(
                value: _selectedStoreId,
                decoration: const InputDecoration(
                  labelText: '店舗',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: _stores.map((m) {
                  final store = _toMap(m['stores']);
                  return DropdownMenuItem(
                    value: store['id'] as String,
                    child: Text(store['name'] ?? ''),
                  );
                }).toList(),
                onChanged: (v) async {
                  final matched = _stores.firstWhere((m) {
                    final store = _toMap(m['stores']);
                    return store['id'] == v;
                  });
                  final store = _toMap(matched['stores']);
                  setState(() {
                    _selectedStoreId = v;
                    _selectedStoreName = store['name'] as String?;
                    _selectedRole = matched['role'] as String?;
                  });
                  await _loadRecruitments();
                },
              ),
            ),
          Expanded(
            child: _recruitments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.event_note,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          isAdmin
                              ? 'シフト募集を作成してください'
                              : '現在募集中のシフトはありません',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _recruitments.length,
                    itemBuilder: (context, index) {
                      final r = _recruitments[index];
                      final isOpen = r['status'] == 'open';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isOpen ? Colors.teal : Colors.grey,
                            width: 0.5,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      r['title'],
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isOpen
                                          ? Colors.teal[50]
                                          : Colors.grey[100],
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      isOpen ? '募集中' : '締切',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isOpen
                                            ? Colors.teal[700]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.work_outline,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    '勤務期間：${fmt.format(DateTime.parse(r['work_start']))} 〜 ${fmt.format(DateTime.parse(r['work_end']))}',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.schedule,
                                      size: 14, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    '提出期限：${fmt.format(DateTime.parse(r['request_start']))} 〜 ${fmt.format(DateTime.parse(r['request_end']))}',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.grey),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (isAdmin) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                AdminShiftOverviewScreen(
                                              recruitment: r,
                                              storeId: _selectedStoreId!,
                                            ),
                                          ),
                                        );
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.teal,
                                        foregroundColor: Colors.white,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 8),
                                      ),
                                      icon: const Icon(Icons.people,
                                          size: 14),
                                      label: const Text('希望確認・シフト確定',
                                          style:
                                              TextStyle(fontSize: 12)),
                                    ),
                                    Row(
                                      children: [
                                        // 募集中 → 締め切るボタン
                                        if (isOpen)
                                          TextButton(
                                            onPressed: () async {
                                              await _recruitmentService
                                                  .closeRecruitment(
                                                      r['id']);
                                              await _loadRecruitments();
                                            },
                                            child: const Text('締め切る',
                                                style: TextStyle(
                                                    color:
                                                        Colors.orange)),
                                          ),
                                        // 締切済み → 再募集ボタン
                                        if (!isOpen)
                                          TextButton.icon(
                                            onPressed: () =>
                                                _showReopenDialog(r),
                                            icon: const Icon(
                                                Icons.refresh,
                                                size: 14,
                                                color: Colors.teal),
                                            label: const Text('再募集',
                                                style: TextStyle(
                                                    color:
                                                        Colors.teal)),
                                          ),
                                        TextButton(
                                          onPressed: () async {
                                            await _recruitmentService
                                                .deleteRecruitment(
                                                    r['id']);
                                            await _loadRecruitments();
                                          },
                                          child: const Text('削除',
                                              style: TextStyle(
                                                  color: Colors.red)),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Row(
                                  children: [
                                    if (isOpen)
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ShiftRequestScreen(
                                                  recruitment: r,
                                                  storeId:
                                                      _selectedStoreId!,
                                                  storeName:
                                                      _selectedStoreName!,
                                                ),
                                              ),
                                            );
                                          },
                                          style:
                                              OutlinedButton.styleFrom(
                                            foregroundColor: Colors.teal,
                                            side: const BorderSide(
                                                color: Colors.teal),
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    vertical: 8),
                                          ),
                                          icon: const Icon(
                                              Icons.edit_calendar,
                                              size: 14),
                                          label: const Text('希望を入力',
                                              style: TextStyle(
                                                  fontSize: 12)),
                                        ),
                                      ),
                                    if (isOpen) const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  StaffConfirmedShiftScreen(
                                                recruitment: r,
                                                storeId:
                                                    _selectedStoreId!,
                                                storeName:
                                                    _selectedStoreName!,
                                              ),
                                            ),
                                          );
                                        },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.teal,
                                          foregroundColor: Colors.white,
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 8),
                                        ),
                                        icon: const Icon(
                                            Icons.calendar_month,
                                            size: 14),
                                        label: const Text('確定シフトを見る',
                                            style: TextStyle(
                                                fontSize: 12)),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: isAdmin
          ? FloatingActionButton.extended(
              onPressed: _showCreateDialog,
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('募集を作成'),
            )
          : null,
    );
  }
}

// ─── カスタム日付ピッカーダイアログ ──────────────────────────────────────
class _CustomDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final Map<String, String> holidays;
  final String title;

  const _CustomDatePickerDialog({
    required this.initialDate,
    required this.holidays,
    required this.title,
  });

  @override
  State<_CustomDatePickerDialog> createState() =>
      _CustomDatePickerDialogState();
}

class _CustomDatePickerDialogState
    extends State<_CustomDatePickerDialog> {
  late DateTime _displayMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayMonth = DateTime(
        widget.initialDate.year, widget.initialDate.month, 1);
  }

  bool _isJapaneseHoliday(DateTime date) {
    final key = date.toIso8601String().substring(0, 10);
    return widget.holidays.containsKey(key);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Color _dayColor(DateTime date, {bool selected = false}) {
    if (selected) return Colors.white;
    if (date.weekday == DateTime.sunday || _isJapaneseHoliday(date)) {
      return Colors.red;
    }
    if (date.weekday == DateTime.saturday) return Colors.blue;
    return Colors.black87;
  }

  @override
  Widget build(BuildContext context) {
    final year = _displayMonth.year;
    final month = _displayMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final totalCells = startWeekday + lastDay.day;
    final totalRows = (totalCells / 7).ceil();
    final fmt = DateFormat('yyyy/MM/dd');

    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
              child: Row(
                children: [
                  Text(widget.title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(() => _displayMonth =
                        DateTime(_displayMonth.year,
                            _displayMonth.month - 1, 1)),
                  ),
                  Text(
                      DateFormat('yyyy年M月').format(_displayMonth),
                      style: const TextStyle(
                          fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => setState(() => _displayMonth =
                        DateTime(_displayMonth.year,
                            _displayMonth.month + 1, 1)),
                  ),
                ],
              ),
            ),
            if (_selectedDate != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 2),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    fmt.format(_selectedDate!),
                    style:
                        TextStyle(fontSize: 13, color: Colors.teal[700]),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: ['日', '月', '火', '水', '木', '金', '土']
                    .map((w) {
                  final color = w == '日'
                      ? Colors.red
                      : w == '土'
                          ? Colors.blue
                          : Colors.black54;
                  return Expanded(
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(vertical: 6),
                      alignment: Alignment.center,
                      child: Text(w,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: color)),
                    ),
                  );
                }).toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: List.generate(totalRows, (row) {
                  return Row(
                    children: List.generate(7, (col) {
                      final dayNum =
                          row * 7 + col - startWeekday + 1;
                      if (dayNum < 1 || dayNum > lastDay.day) {
                        return const Expanded(
                            child: SizedBox(height: 40));
                      }
                      final date = DateTime(year, month, dayNum);
                      final isSelected = _selectedDate != null &&
                          _isSameDay(date, _selectedDate!);
                      final isToday =
                          _isSameDay(date, DateTime.now());
                      final isHoliday = _isJapaneseHoliday(date);

                      return Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _selectedDate = date),
                          child: Container(
                            height: 40,
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.teal
                                  : isToday
                                      ? Colors.teal[50]
                                      : Colors.transparent,
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: isToday && !isSelected
                                  ? Border.all(
                                      color: Colors.teal,
                                      width: 1)
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Text(
                                  '$dayNum',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: isSelected || isToday
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: _dayColor(date,
                                        selected: isSelected),
                                  ),
                                ),
                                if (isHoliday && !isSelected)
                                  Text(
                                    '祝',
                                    style: TextStyle(
                                        fontSize: 7,
                                        color: Colors.red[300]),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _selectedDate == null
                        ? null
                        : () =>
                            Navigator.pop(context, _selectedDate),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Step2 ダイアログ：休業日・繁忙期設定 ─────────────────────────────────
class _Step2Dialog extends StatefulWidget {
  final DateTime workStart;
  final DateTime workEnd;
  final Set<DateTime> selectedHolidays;
  final List<Map<String, dynamic>> specialPeriods;
  final Map<String, String> japaneseHolidays;

  const _Step2Dialog({
    required this.workStart,
    required this.workEnd,
    required this.selectedHolidays,
    required this.specialPeriods,
    required this.japaneseHolidays,
  });

  @override
  State<_Step2Dialog> createState() => _Step2DialogState();
}

class _Step2DialogState extends State<_Step2Dialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final fmt = DateFormat('yyyy/MM/dd');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<DateTime> get _allDates {
    final dates = <DateTime>[];
    var cur = widget.workStart;
    while (!cur.isAfter(widget.workEnd)) {
      dates.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return dates;
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isHolidaySelected(DateTime d) =>
      widget.selectedHolidays.any((h) => _isSameDay(h, d));

  bool _isJapaneseHoliday(DateTime d) {
    final key = d.toIso8601String().substring(0, 10);
    return widget.japaneseHolidays.containsKey(key);
  }

  void _toggleHoliday(DateTime d) {
    setState(() {
      if (widget.selectedHolidays.any((h) => _isSameDay(h, d))) {
        widget.selectedHolidays.removeWhere((h) => _isSameDay(h, d));
      } else {
        widget.selectedHolidays.add(d);
      }
    });
  }

  Color _dayTextColor(DateTime d, {bool selected = false}) {
    if (selected) return Colors.white;
    if (d.weekday == DateTime.sunday || _isJapaneseHoliday(d)) {
      return Colors.red;
    }
    if (d.weekday == DateTime.saturday) return Colors.blue;
    return Colors.black87;
  }

  Future<void> _showAddSpecialPeriodDialog() async {
    final labelController = TextEditingController();
    final minStaffController = TextEditingController(text: '3');
    DateTime? start;
    DateTime? end;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          title: const Text('繁忙期を追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'ラベル',
                    hintText: '例：年末年始',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('期間',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: ctx,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: start ?? widget.workStart,
                              holidays: widget.japaneseHolidays,
                              title: '繁忙期 開始日',
                            ),
                          );
                          if (d != null) setInner(() => start = d);
                        },
                        child: Text(start != null
                            ? fmt.format(start!)
                            : '開始日'),
                      ),
                    ),
                    const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('〜')),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDialog<DateTime>(
                            context: ctx,
                            builder: (_) => _CustomDatePickerDialog(
                              initialDate: end ?? widget.workStart,
                              holidays: widget.japaneseHolidays,
                              title: '繁忙期 終了日',
                            ),
                          );
                          if (d != null) setInner(() => end = d);
                        },
                        child: Text(end != null
                            ? fmt.format(end!)
                            : '終了日'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minStaffController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '必要人数',
                    suffixText: '名',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () {
                if (labelController.text.trim().isEmpty ||
                    start == null ||
                    end == null) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                        content: Text('すべての項目を入力してください')),
                  );
                  return;
                }
                setState(() {
                  widget.specialPeriods.add({
                    'label': labelController.text.trim(),
                    'start_date': start!,
                    'end_date': end!,
                    'min_staff_override':
                        int.tryParse(minStaffController.text.trim()) ??
                            3,
                  });
                });
                Navigator.pop(ctx);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHolidayTab() {
    final dates = _allDates;
    final Map<String, List<DateTime>> byMonth = {};
    for (final d in dates) {
      final key = DateFormat('yyyy年M月').format(d);
      byMonth.putIfAbsent(key, () => []).add(d);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '店舗の休業日をタップして選択してください。\n休業日はスタッフの希望入力カレンダーに表示されません。',
            style: TextStyle(fontSize: 12, color: Colors.blue),
          ),
        ),
        const SizedBox(height: 12),
        for (final entry in byMonth.entries) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(entry.key,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: entry.value.map((d) {
              final selected = _isHolidaySelected(d);
              final weekday = ['月', '火', '水', '木', '金', '土', '日']
                  [d.weekday - 1];
              final isJpHoliday = _isJapaneseHoliday(d);
              final textColor =
                  _dayTextColor(d, selected: selected);

              Color bgColor;
              if (selected) {
                bgColor = Colors.red[400]!;
              } else if (d.weekday == DateTime.sunday ||
                  isJpHoliday) {
                bgColor = Colors.red[50]!;
              } else if (d.weekday == DateTime.saturday) {
                bgColor = Colors.blue[50]!;
              } else {
                bgColor = Colors.grey[100]!;
              }

              return GestureDetector(
                onTap: () => _toggleHoliday(d),
                child: Container(
                  width: 48,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: selected
                            ? Colors.red
                            : Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '${d.day}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textColor,
                        ),
                      ),
                      Text(weekday,
                          style: TextStyle(
                              fontSize: 10, color: textColor)),
                      if (isJpHoliday && !selected)
                        Text('祝',
                            style: TextStyle(
                                fontSize: 8,
                                color: Colors.red[300])),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        if (widget.selectedHolidays.isNotEmpty) ...[
          const Divider(),
          Text('選択中：${widget.selectedHolidays.length}日',
              style:
                  const TextStyle(color: Colors.red, fontSize: 13)),
        ],
      ],
    );
  }

  Widget _buildSpecialPeriodTab() {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            '繁忙期は通常より多くの人員が必要な期間です。\n設定した必要人数がタイムライン上に反映されます。',
            style: TextStyle(fontSize: 12, color: Colors.orange),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.specialPeriods.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Text('繁忙期が設定されていません',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
          )
        else
          ...widget.specialPeriods.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.trending_up,
                      size: 20, color: Colors.orange[700]),
                ),
                title: Text(p['label'] as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold)),
                subtitle: Text(
                  '${fmt.format(p['start_date'] as DateTime)} 〜 ${fmt.format(p['end_date'] as DateTime)}'
                  '\n必要人数：${p['min_staff_override']}名',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.delete,
                      size: 18, color: Colors.red),
                  onPressed: () => setState(
                      () => widget.specialPeriods.removeAt(i)),
                ),
              ),
            );
          }),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _showAddSpecialPeriodDialog,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.orange[700],
              side: BorderSide(color: Colors.orange[300]!),
            ),
            icon: const Icon(Icons.add),
            label: const Text('繁忙期を追加'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SizedBox(
        width: 480,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'シフト募集を作成 (2/2)',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  Text(
                    '${DateFormat('M/d').format(widget.workStart)} 〜 ${DateFormat('M/d').format(widget.workEnd)}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            TabBar(
              controller: _tabController,
              labelColor: Colors.teal,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.teal,
              tabs: [
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.block, size: 14),
                      const SizedBox(width: 4),
                      const Text('休業日'),
                      if (widget.selectedHolidays.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius:
                                  BorderRadius.circular(10)),
                          child: Text(
                              '${widget.selectedHolidays.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.trending_up, size: 14),
                      const SizedBox(width: 4),
                      const Text('繁忙期'),
                      if (widget.specialPeriods.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                              color: Colors.orange,
                              borderRadius:
                                  BorderRadius.circular(10)),
                          child: Text(
                              '${widget.specialPeriods.length}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHolidayTab(),
                  _buildSpecialPeriodTab(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('キャンセル'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('作成'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}