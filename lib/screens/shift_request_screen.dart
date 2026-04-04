import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/shift_request_service.dart';
import '../services/store_settings_service.dart';

class ShiftRequestScreen extends StatefulWidget {
  final Map<String, dynamic> recruitment;
  final String storeId;
  final String storeName;

  const ShiftRequestScreen({
    super.key,
    required this.recruitment,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<ShiftRequestScreen> createState() => _ShiftRequestScreenState();
}

class _ShiftRequestScreenState extends State<ShiftRequestScreen> {
  final _service = ShiftRequestService();
  final _settingsService = StoreSettingsService();

  Map<String, dynamic> _shiftRequests = {};
  Map<String, dynamic> _dayOffRequests = {};
  Set<String> _holidayDates = {};
  List<Map<String, dynamic>> _specialPeriods = [];
  Map<String, String> _japaneseHolidays = {};

  bool _isLoading = true;
  bool _isSubmitted = false;
  bool _isSubmitting = false;
  late DateTime _workStart;
  late DateTime _workEnd;
  late DateTime _currentMonth;

  @override
  void initState() {
    super.initState();
    _workStart = DateTime.parse(widget.recruitment['work_start']);
    _workEnd = DateTime.parse(widget.recruitment['work_end']);
    _currentMonth = DateTime(_workStart.year, _workStart.month, 1);
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      final shifts = await _service.getMyShiftRequests(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final dayOffs = await _service.getMyDayOffRequests(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final isSubmitted = await _service.isSubmitted(
        recruitmentId: widget.recruitment['id'],
      );
      final holidays =
          await _settingsService.getShiftHolidays(widget.recruitment['id']);
      final specialPeriods =
          await _settingsService.getSpecialPeriods(widget.recruitment['id']);
      final japaneseHolidays =
          await StoreSettingsService.getJapaneseHolidays();

      setState(() {
        _shiftRequests = {for (var s in shifts) s['date']: s};
        _dayOffRequests = {for (var d in dayOffs) d['date']: d};
        _isSubmitted = isSubmitted;
        _holidayDates = holidays.map((h) => h['date'] as String).toSet();
        _specialPeriods = specialPeriods;
        _japaneseHolidays = japaneseHolidays;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  bool _isSpecialPeriod(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    for (final p in _specialPeriods) {
      final start = DateTime.parse(p['start_date'] as String);
      final end = DateTime.parse(p['end_date'] as String);
      if (!d.isBefore(start) && !d.isAfter(end)) return true;
    }
    return false;
  }

  bool _isJapaneseHoliday(DateTime date) {
    final key = date.toIso8601String().substring(0, 10);
    return _japaneseHolidays.containsKey(key);
  }

  Future<void> _submit() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_isSubmitted ? '希望シフトを再提出' : '希望シフトを提出'),
        content: Text(_isSubmitted
            ? '修正した内容で再提出します。\n\nよろしいですか？'
            : '入力内容を管理者に提出します。\n提出後も修正して再提出できます。\n\nよろしいですか？'),
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
            child: const Text('提出する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSubmitting = true);
    try {
      await _service.submitShiftRequests(
        storeId: widget.storeId,
        recruitmentId: widget.recruitment['id'],
        from: _workStart,
        to: _workEnd,
      );
      setState(() => _isSubmitted = true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('希望シフトを提出しました！'),
            backgroundColor: Colors.teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  bool _isInRange(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    final s = DateTime(_workStart.year, _workStart.month, _workStart.day);
    final e = DateTime(_workEnd.year, _workEnd.month, _workEnd.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  Future<void> _showDayDialog(DateTime date) async {
    final dateStr = date.toIso8601String().substring(0, 10);
    final existing = _shiftRequests[dateStr];
    final isDayOff = _dayOffRequests.containsKey(dateStr);

    String selectedType = isDayOff
        ? 'off'
        : existing != null
            ? 'work'
            : 'none';
    bool isLast = existing?['is_last'] ?? false;
    final startController = TextEditingController(
        text: existing?['preferred_start']
                ?.toString()
                .substring(0, 5) ??
            '');
    final endController = TextEditingController(
        text:
            existing?['preferred_end']?.toString().substring(0, 5) ??
                '');
    final noteController =
        TextEditingController(text: existing?['note'] ?? '');
    final fmt = DateFormat('M/d(E)', 'ja');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(fmt.format(date)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'none',
                        label: Text('未定'),
                        icon: Icon(Icons.remove)),
                    ButtonSegment(
                        value: 'work',
                        label: Text('出勤'),
                        icon: Icon(Icons.work)),
                    ButtonSegment(
                        value: 'off',
                        label: Text('希望休'),
                        icon: Icon(Icons.beach_access)),
                  ],
                  selected: {selectedType},
                  onSelectionChanged: (s) =>
                      setDialogState(() => selectedType = s.first),
                ),
                if (selectedType == 'work') ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          decoration: const InputDecoration(
                            labelText: '開始時間',
                            hintText: '例：9:00',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text('〜'),
                      ),
                      Expanded(
                        child: TextField(
                          controller: endController,
                          enabled: !isLast,
                          decoration: InputDecoration(
                            labelText: '終了時間',
                            hintText: isLast ? 'ラスト' : '例：17:00',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('ラストまで'),
                    value: isLast,
                    onChanged: (v) =>
                        setDialogState(() => isLast = v ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(
                    controller: noteController,
                    decoration: const InputDecoration(
                      labelText: 'メモ（任意）',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedType == 'none') {
                  await _service.deleteShiftRequest(
                    storeId: widget.storeId,
                    date: date,
                  );
                } else if (selectedType == 'off') {
                  await _service.saveShiftRequest(
                    storeId: widget.storeId,
                    recruitmentId: widget.recruitment['id'],
                    date: date,
                    isDayOff: true,
                    // ── 修正ポイント ──
                    // 提出済みの場合は保存と同時に submitted にする
                    alreadySubmitted: _isSubmitted,
                  );
                } else {
                  await _service.saveShiftRequest(
                    storeId: widget.storeId,
                    recruitmentId: widget.recruitment['id'],
                    date: date,
                    preferredStart:
                        startController.text.trim().isEmpty
                            ? null
                            : startController.text.trim(),
                    preferredEnd: isLast
                        ? null
                        : endController.text.trim().isEmpty
                            ? null
                            : endController.text.trim(),
                    isLast: isLast,
                    note: noteController.text.trim().isEmpty
                        ? null
                        : noteController.text.trim(),
                    // ── 修正ポイント ──
                    // 提出済みの場合は保存と同時に submitted にする
                    alreadySubmitted: _isSubmitted,
                  );
                }
                if (context.mounted) Navigator.pop(context);
                await _loadRequests();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCalendar() {
    final year = _currentMonth.year;
    final month = _currentMonth.month;
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final totalCells = startWeekday + lastDay.day;
    final totalRows = (totalCells / 7).ceil();
    final isOpen = widget.recruitment['status'] == 'open';

    return Column(
      children: [
        Container(
          color: Colors.grey[100],
          child: Row(
            children: ['日', '月', '火', '水', '木', '金', '土'].map((w) {
              final color = w == '日'
                  ? Colors.red
                  : w == '土'
                      ? Colors.blue
                      : Colors.black87;
              return Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8),
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
        ...List.generate(totalRows, (row) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(7, (col) {
              final dayNum = row * 7 + col - startWeekday + 1;
              if (dayNum < 1 || dayNum > lastDay.day) {
                return Expanded(
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Colors.grey[200]!, width: 0.5),
                      color: Colors.grey[50],
                    ),
                  ),
                );
              }

              final date = DateTime(year, month, dayNum);
              final dateStr =
                  date.toIso8601String().substring(0, 10);
              final inRange = _isInRange(date);
              final isStoreHoliday =
                  _holidayDates.contains(dateStr);
              final isSpecial = _isSpecialPeriod(date);
              final isJpHoliday = _isJapaneseHoliday(date);
              final isDayOff =
                  _dayOffRequests.containsKey(dateStr);
              final hasShift =
                  _shiftRequests.containsKey(dateStr);

              Color bgColor;
              if (!inRange) {
                bgColor = Colors.grey[100]!;
              } else if (isStoreHoliday) {
                bgColor = Colors.grey[300]!;
              } else if (isDayOff) {
                bgColor = Colors.red[50]!;
              } else if (hasShift) {
                bgColor = Colors.teal[50]!;
              } else if (isSpecial) {
                bgColor = Colors.pink[50]!;
              } else {
                bgColor = Colors.white;
              }

              Color dayColor;
              if (!inRange || isStoreHoliday) {
                dayColor = Colors.grey[400]!;
              } else if (date.weekday == DateTime.sunday ||
                  isJpHoliday) {
                dayColor = Colors.red;
              } else if (date.weekday == DateTime.saturday) {
                dayColor = Colors.blue;
              } else {
                dayColor = Colors.black87;
              }

              String cellText = '';
              String cellSubText = '';
              if (isStoreHoliday) {
                cellText = '休業';
              } else if (isDayOff) {
                cellText = '休';
              } else if (hasShift) {
                final shift = _shiftRequests[dateStr];
                final start = shift['preferred_start']
                        ?.toString()
                        .substring(0, 5) ??
                    '';
                if (shift['is_last'] == true) {
                  cellText = start.isEmpty ? 'L' : '$start\n〜L';
                } else {
                  final end = shift['preferred_end']
                          ?.toString()
                          .substring(0, 5) ??
                      '';
                  cellText =
                      start.isEmpty ? '出勤' : '$start\n〜$end';
                }
              } else if (isSpecial) {
                cellSubText = '★';
              }

              final showJpHolidayLabel =
                  isJpHoliday && inRange && !isStoreHoliday;
              final canTap =
                  inRange && isOpen && !isStoreHoliday;

              return Expanded(
                child: GestureDetector(
                  onTap: canTap ? () => _showDayDialog(date) : null,
                  child: Container(
                    height: 72,
                    decoration: BoxDecoration(
                      color: bgColor,
                      border: Border.all(
                          color: Colors.grey[200]!, width: 0.5),
                    ),
                    child: Stack(
                      children: [
                        if (showJpHolidayLabel)
                          Positioned(
                            top: 2,
                            right: 2,
                            child: Text(
                              '祝',
                              style: TextStyle(
                                  fontSize: 7,
                                  color: Colors.red[300]),
                            ),
                          ),
                        Column(
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              '$dayNum',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: dayColor,
                              ),
                            ),
                            if (cellText.isNotEmpty)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 2),
                                child: Text(
                                  cellText,
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: isStoreHoliday
                                        ? Colors.grey[500]
                                        : isDayOff
                                            ? Colors.red[400]
                                            : Colors.teal[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            if (cellSubText.isNotEmpty)
                              Text(
                                cellSubText,
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.pink[300]),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = widget.recruitment['status'] == 'open';
    final hasMultipleMonths = _workStart.month != _workEnd.month ||
        _workStart.year != _workEnd.year;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.recruitment['title']),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: _isSubmitted
                      ? Colors.green[50]
                      : Colors.teal[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '勤務期間：${DateFormat('yyyy/MM/dd').format(_workStart)} 〜 ${DateFormat('yyyy/MM/dd').format(_workEnd)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      Text(
                        '提出期限：${widget.recruitment['request_end']}',
                        style: TextStyle(
                            fontSize: 13,
                            color: isOpen
                                ? Colors.teal[700]
                                : Colors.grey),
                      ),
                      if (_isSubmitted)
                        Row(
                          children: [
                            Icon(Icons.check_circle,
                                size: 14,
                                color: Colors.green[600]),
                            const SizedBox(width: 4),
                            Text(
                              '提出済み（日付をタップして修正→管理者に即反映されます）',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.green[700]),
                            ),
                          ],
                        ),
                      if (!isOpen)
                        const Text('※ この募集は締め切られています',
                            style: TextStyle(
                                fontSize: 12, color: Colors.red)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 4,
                    children: [
                      _legend(Colors.teal[50]!, Colors.teal[700]!,
                          '出勤希望'),
                      _legend(Colors.red[50]!, Colors.red[400]!,
                          '希望休'),
                      _legend(Colors.pink[50]!, Colors.pink[400]!,
                          '繁忙期'),
                      _legend(Colors.grey[300]!, Colors.grey[500]!,
                          '休業日'),
                      _legend(Colors.grey[100]!, Colors.grey[400]!,
                          '対象外'),
                    ],
                  ),
                ),
                if (hasMultipleMonths)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: _currentMonth.isAfter(DateTime(
                                _workStart.year,
                                _workStart.month,
                                1))
                            ? () => setState(() =>
                                _currentMonth = DateTime(
                                    _currentMonth.year,
                                    _currentMonth.month - 1,
                                    1))
                            : null,
                      ),
                      Text(
                        DateFormat('yyyy年M月')
                            .format(_currentMonth),
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right),
                        onPressed: _currentMonth.isBefore(DateTime(
                                _workEnd.year, _workEnd.month, 1))
                            ? () => setState(() =>
                                _currentMonth = DateTime(
                                    _currentMonth.year,
                                    _currentMonth.month + 1,
                                    1))
                            : null,
                      ),
                    ],
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      DateFormat('yyyy年M月').format(_currentMonth),
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                Expanded(
                  child: SingleChildScrollView(
                    child: _buildCalendar(),
                  ),
                ),
                if (isOpen)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    child: ElevatedButton.icon(
                      onPressed: _isSubmitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isSubmitted
                            ? Colors.green
                            : Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: _isSubmitting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2),
                            )
                          : Icon(_isSubmitted
                              ? Icons.refresh
                              : Icons.send),
                      label: Text(_isSubmitting
                          ? '提出中...'
                          : _isSubmitted
                              ? '再提出する'
                              : '希望シフトを提出する'),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _legend(Color bg, Color textColor, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: Colors.grey[300]!),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style:
                TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}