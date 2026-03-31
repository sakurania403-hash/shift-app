import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/store_settings_service.dart';
import '../services/shift_service.dart';

class ShiftTimelineScreen extends StatefulWidget {
  final DateTime date;
  final String storeId;
  final List<Map<String, dynamic>> confirmedShifts;
  final List<Map<String, dynamic>> staff;
  final List<Map<String, dynamic>> shiftRequests;
  final List<Map<String, dynamic>> dayOffRequests;
  final List<DateTime> allDates;

  const ShiftTimelineScreen({
    super.key,
    required this.date,
    required this.storeId,
    required this.confirmedShifts,
    required this.staff,
    required this.shiftRequests,
    required this.dayOffRequests,
    required this.allDates,
  });

  @override
  State<ShiftTimelineScreen> createState() => _ShiftTimelineScreenState();
}

class _ShiftTimelineScreenState extends State<ShiftTimelineScreen> {
  final _settingsService = StoreSettingsService();
  final _shiftService = ShiftService();
  List<Map<String, dynamic>> _workHours = [];
  List<Map<String, dynamic>> _staffingSlots = [];
  List<Map<String, dynamic>> _tempShifts = [];
  List<Map<String, dynamic>> _confirmedShifts = [];
  bool _isLoading = true;
  bool _isHoliday = false;
  late DateTime _currentDate;

  @override
  void initState() {
    super.initState();
    _currentDate = widget.date;
    _confirmedShifts = List.from(widget.confirmedShifts);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final workHours =
        await _settingsService.getWorkHours(widget.storeId);
    final staffingSlots =
        await _settingsService.getStaffingSlots(widget.storeId);
    final holidays = await StoreSettingsService.getJapaneseHolidays();
    final isHoliday =
        await StoreSettingsService.isHoliday(_currentDate, holidays);

    final dateStr = _currentDate.toIso8601String().substring(0, 10);
    final allConfirmed = await _shiftService.getConfirmedShifts(
      storeId: widget.storeId,
      from: _currentDate,
      to: _currentDate,
    );
    final temps = allConfirmed
        .where((s) => s['staff_type'] == 'temp' && s['date'] == dateStr)
        .toList();
    final regular = allConfirmed
        .where((s) => s['staff_type'] != 'temp' && s['date'] == dateStr)
        .toList();

    setState(() {
      _workHours = workHours;
      _staffingSlots = staffingSlots;
      _isHoliday = isHoliday;
      _tempShifts = temps;
      _confirmedShifts = regular;
      _isLoading = false;
    });
  }

  void _goToPrevDay() {
    final idx = widget.allDates.indexWhere((d) =>
        d.toIso8601String().substring(0, 10) ==
        _currentDate.toIso8601String().substring(0, 10));
    if (idx > 0) {
      setState(() => _currentDate = widget.allDates[idx - 1]);
      _loadData();
    }
  }

  void _goToNextDay() {
    final idx = widget.allDates.indexWhere((d) =>
        d.toIso8601String().substring(0, 10) ==
        _currentDate.toIso8601String().substring(0, 10));
    if (idx < widget.allDates.length - 1) {
      setState(() => _currentDate = widget.allDates[idx + 1]);
      _loadData();
    }
  }

  bool get _hasPrev {
    final idx = widget.allDates.indexWhere((d) =>
        d.toIso8601String().substring(0, 10) ==
        _currentDate.toIso8601String().substring(0, 10));
    return idx > 0;
  }

  bool get _hasNext {
    final idx = widget.allDates.indexWhere((d) =>
        d.toIso8601String().substring(0, 10) ==
        _currentDate.toIso8601String().substring(0, 10));
    return idx < widget.allDates.length - 1;
  }

  Map<String, dynamic>? get _todayWorkHours {
    final dayType = _isHoliday ? 'holiday' : 'weekday';
    final filtered =
        _workHours.where((w) => w['day_type'] == dayType).toList();
    return filtered.isNotEmpty ? filtered.first : null;
  }

  List<Map<String, dynamic>> get _todaySlots {
    final dayType = _isHoliday ? 'holiday' : 'weekday';
    return _staffingSlots
        .where((s) => s['day_type'] == dayType)
        .toList();
  }

  double _timeToDouble(String timeStr) {
    final parts = timeStr.substring(0, 5).split(':');
    return int.parse(parts[0]) + int.parse(parts[1]) / 60.0;
  }

  String get _dateStr =>
      _currentDate.toIso8601String().substring(0, 10);

  Map<String, dynamic>? _getConfirmedShift(String userId) {
    final found = _confirmedShifts
        .where((s) => s['user_id'] == userId)
        .toList();
    return found.isNotEmpty ? found.first : null;
  }

  Map<String, dynamic>? _getRequestShift(String userId) {
    final found = widget.shiftRequests
        .where((s) =>
            s['user_id'] == userId && s['date'] == _dateStr)
        .toList();
    return found.isNotEmpty ? found.first : null;
  }

  bool _isDayOff(String userId) {
    return widget.dayOffRequests
        .any((s) => s['user_id'] == userId && s['date'] == _dateStr);
  }

  List<Map<String, dynamic>> _getStaffAtTime(
      double time, List<Map<String, dynamic>> allShifts) {
    final result = <Map<String, dynamic>>[];
    for (var shift in allShifts) {
      if (shift['date'] != _dateStr) continue;
      final start = _timeToDouble(
          shift['start_time'].toString().substring(0, 5));
      final isLast = shift['is_last'] == true;
      double end = 24.0;
      if (!isLast && shift['end_time'] != null) {
        end = _timeToDouble(
            shift['end_time'].toString().substring(0, 5));
      }
      if (time >= start && time < end) result.add(shift);
    }
    return result;
  }

  int _getMinStaffAtTime(double time) {
    for (var slot in _todaySlots) {
      final start = _timeToDouble(
          slot['slot_start'].toString().substring(0, 5));
      final end = _timeToDouble(
          slot['slot_end'].toString().substring(0, 5));
      if (time >= start && time < end) return slot['min_staff'] as int;
    }
    return 0;
  }

  Future<void> _showConfirmFromTimelineDialog(
      Map<String, dynamic> staffMember) async {
    final profile = staffMember['user_profiles'] as Map<String, dynamic>;
    final userId = profile['id'] as String;
    final name = profile['name'] as String;
    final confirmed = _getConfirmedShift(userId);
    final request = _getRequestShift(userId);
    final isDayOff = _isDayOff(userId);
    final fmt = DateFormat('M/d(E)', 'ja');

    String startTime =
        confirmed?['start_time']?.toString().substring(0, 5) ??
            request?['preferred_start']?.toString().substring(0, 5) ??
            '';
    String endTime =
        confirmed?['end_time']?.toString().substring(0, 5) ??
            request?['preferred_end']?.toString().substring(0, 5) ??
            '';
    bool isLast =
        confirmed?['is_last'] ?? request?['is_last'] ?? false;
    bool isOff = isDayOff && confirmed == null;

    final startController = TextEditingController(text: startTime);
    final endController = TextEditingController(text: endTime);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('${fmt.format(_currentDate)} - $name'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline,
                          size: 14, color: Colors.grey),
                      const SizedBox(width: 4),
                      Text(
                        isDayOff
                            ? '希望：希望休'
                            : request != null
                                ? '希望：${request['preferred_start']?.toString().substring(0, 5) ?? ''}〜${request['is_last'] == true ? 'L' : request['preferred_end']?.toString().substring(0, 5) ?? ''}'
                                : '希望：未提出',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                        value: false,
                        label: Text('出勤'),
                        icon: Icon(Icons.work)),
                    ButtonSegment(
                        value: true,
                        label: Text('休み'),
                        icon: Icon(Icons.beach_access)),
                  ],
                  selected: {isOff},
                  onSelectionChanged: (s) =>
                      setDialogState(() => isOff = s.first),
                ),
                if (!isOff) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startController,
                          decoration: const InputDecoration(
                            labelText: '出勤時間',
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
                            labelText: '退勤時間',
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
                ],
              ],
            ),
          ),
          actions: [
            if (confirmed != null)
              TextButton(
                onPressed: () async {
                  await _shiftService.deleteShift(
                    storeId: widget.storeId,
                    userId: userId,
                    date: _currentDate,
                  );
                  if (context.mounted) Navigator.pop(context);
                  await _loadData();
                },
                child: const Text('確定を取り消す',
                    style: TextStyle(color: Colors.red)),
              ),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!isOff) {
                  await _shiftService.upsertShift(
                    storeId: widget.storeId,
                    userId: userId,
                    date: _currentDate,
                    startTime: startController.text.trim(),
                    endTime: isLast
                        ? null
                        : endController.text.trim().isEmpty
                            ? null
                            : endController.text.trim(),
                    isLast: isLast,
                  );
                } else {
                  if (confirmed != null) {
                    await _shiftService.deleteShift(
                      storeId: widget.storeId,
                      userId: userId,
                      date: _currentDate,
                    );
                  }
                }
                if (context.mounted) Navigator.pop(context);
                await _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('確定'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAddTempDialog() async {
    final nameController = TextEditingController();
    final startController = TextEditingController();
    final endController = TextEditingController();
    bool isLast = false;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ヘルプ・タイミーを追加'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名前',
                    hintText: '例：タイミー1、ヘルプ 田中',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startController,
                        decoration: const InputDecoration(
                          labelText: '出勤時間',
                          hintText: '例：10:00',
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
                          labelText: '退勤時間',
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
                if (nameController.text.trim().isEmpty ||
                    startController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('名前と出勤時間を入力してください')),
                  );
                  return;
                }
                await _shiftService.upsertTempShift(
                  storeId: widget.storeId,
                  date: _currentDate,
                  tempLabel: nameController.text.trim(),
                  startTime: startController.text.trim(),
                  endTime: isLast
                      ? null
                      : endController.text.trim().isEmpty
                          ? null
                          : endController.text.trim(),
                  isLast: isLast,
                );
                if (context.mounted) Navigator.pop(context);
                await _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('追加'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showEditTempDialog(Map<String, dynamic> shift) async {
    final nameController =
        TextEditingController(text: shift['temp_label'] ?? '');
    final startController = TextEditingController(
        text: shift['start_time']?.toString().substring(0, 5) ?? '');
    final endController = TextEditingController(
        text: shift['end_time']?.toString().substring(0, 5) ?? '');
    bool isLast = shift['is_last'] == true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('ヘルプ・タイミーを編集'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '名前',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: startController,
                        decoration: const InputDecoration(
                          labelText: '出勤時間',
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
                          labelText: '退勤時間',
                          hintText: isLast ? 'ラスト' : '',
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
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _shiftService.deleteTempShift(shift['id']);
                if (context.mounted) Navigator.pop(context);
                await _loadData();
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
                await _shiftService.updateTempShift(
                  shiftId: shift['id'],
                  tempLabel: nameController.text.trim(),
                  startTime: startController.text.trim(),
                  endTime: isLast
                      ? null
                      : endController.text.trim().isEmpty
                          ? null
                          : endController.text.trim(),
                  isLast: isLast,
                );
                if (context.mounted) Navigator.pop(context);
                await _loadData();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeHeader(double startHour, double endHour) {
    final totalHours = endHour - startHour;
    return Row(
      children: [
        const SizedBox(width: 80),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return Stack(
                children: [
                  Container(height: 20),
                  ...List.generate(
                    (totalHours).ceil() + 1,
                    (i) {
                      final hour = startHour + i;
                      if (hour > endHour) return const SizedBox();
                      final left = (i / totalHours) * width;
                      return Positioned(
                        left: left,
                        child: Text(
                          '${hour.toInt()}',
                          style: const TextStyle(
                              fontSize: 10, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStaffTimebar({
    required String name,
    required Map<String, dynamic>? confirmedShift,
    required Map<String, dynamic>? requestShift,
    required bool isDayOff,
    required double startHour,
    required double endHour,
    required VoidCallback onTap,
  }) {
    final totalHours = endHour - startHour;
    final isConfirmed = confirmedShift != null;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  if (isConfirmed)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: const BoxDecoration(
                        color: Colors.teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        fontSize: 11,
                        color: isConfirmed
                            ? Colors.teal[800]
                            : Colors.black87,
                        fontWeight: isConfirmed
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;

                  if (isDayOff && !isConfirmed) {
                    return Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.red[200]!, width: 1),
                      ),
                      alignment: Alignment.center,
                      child: Text('希望休',
                          style: TextStyle(
                              fontSize: 10, color: Colors.red[400])),
                    );
                  }

                  final displayShift = confirmedShift ?? requestShift;

                  if (displayShift == null) {
                    return Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      alignment: Alignment.center,
                      child: const Text('未確定・未提出',
                          style: TextStyle(
                              fontSize: 10, color: Colors.grey)),
                    );
                  }

                  final startKey =
                      displayShift.containsKey('start_time')
                          ? 'start_time'
                          : 'preferred_start';
                  final endKey =
                      displayShift.containsKey('end_time')
                          ? 'end_time'
                          : 'preferred_end';

                  final shiftStart = _timeToDouble(
                      displayShift[startKey]?.toString().substring(0, 5) ??
                          '09:00');
                  final isLast = displayShift['is_last'] == true;
                  double shiftEnd = endHour;
                  if (!isLast && displayShift[endKey] != null) {
                    shiftEnd = _timeToDouble(
                        displayShift[endKey].toString().substring(0, 5));
                  }

                  final leftRatio =
                      ((shiftStart - startHour) / totalHours)
                          .clamp(0.0, 1.0);
                  final widthRatio =
                      ((shiftEnd - shiftStart) / totalHours)
                          .clamp(0.0, 1.0 - leftRatio);

                  final startLabel =
                      displayShift[startKey]?.toString().substring(0, 5) ??
                          '';
                  final endLabel = isLast
                      ? 'L'
                      : displayShift[endKey]
                              ?.toString()
                              .substring(0, 5) ??
                          '';

                  final barColor = isConfirmed
                      ? Colors.teal[500]!
                      : Colors.teal[200]!;
                  final textColor =
                      isConfirmed ? Colors.white : Colors.teal[800]!;

                  return Stack(
                    children: [
                      Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Positioned(
                        left: leftRatio * width,
                        width: widthRatio * width,
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(4),
                            border: isConfirmed
                                ? null
                                : Border.all(
                                    color: Colors.teal[300]!, width: 1),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$startLabel〜$endLabel',
                            style: TextStyle(
                              fontSize: 9,
                              color: textColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTempTimebar({
    required Map<String, dynamic> shift,
    required double startHour,
    required double endHour,
    required VoidCallback onTap,
  }) {
    final totalHours = endHour - startHour;
    final label = shift['temp_label'] ?? 'ヘルプ';

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final shiftStart = _timeToDouble(
                      shift['start_time'].toString().substring(0, 5));
                  final isLast = shift['is_last'] == true;
                  double shiftEnd = endHour;
                  if (!isLast && shift['end_time'] != null) {
                    shiftEnd = _timeToDouble(
                        shift['end_time'].toString().substring(0, 5));
                  }

                  final leftRatio =
                      ((shiftStart - startHour) / totalHours)
                          .clamp(0.0, 1.0);
                  final widthRatio =
                      ((shiftEnd - shiftStart) / totalHours)
                          .clamp(0.0, 1.0 - leftRatio);
                  final endLabel = isLast
                      ? 'L'
                      : shift['end_time']?.toString().substring(0, 5) ??
                          '';

                  return Stack(
                    children: [
                      Container(
                        height: 28,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      Positioned(
                        left: leftRatio * width,
                        width: widthRatio * width,
                        child: Container(
                          height: 28,
                          decoration: BoxDecoration(
                            color: Colors.orange[400],
                            borderRadius: BorderRadius.circular(4),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${shift['start_time'].toString().substring(0, 5)}〜$endLabel',
                            style: const TextStyle(
                              fontSize: 9,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffingChart(double startHour, double endHour) {
    final slots = _todaySlots;
    final totalHours = endHour - startHour;
    final allShifts = [..._confirmedShifts, ..._tempShifts];

    final timePoints = <double>[];
    for (double h = startHour; h < endHour; h += 0.5) {
      timePoints.add(h);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 30),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(
                  (totalHours).ceil() + 1,
                  (i) {
                    final hour = startHour + i;
                    if (hour > endHour) return const SizedBox();
                    return Text('${hour.toInt()}',
                        style: const TextStyle(
                            fontSize: 9, color: Colors.grey));
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 80,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 30),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final barWidth =
                        constraints.maxWidth / timePoints.length;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: timePoints.map((time) {
                        final staffCount =
                            _getStaffAtTime(time, allShifts).length;
                        final minStaff = _getMinStaffAtTime(time);
                        final isShort =
                            minStaff > 0 && staffCount < minStaff;
                        const maxCount = 5;
                        final barHeight = staffCount == 0
                            ? 4.0
                            : (staffCount / maxCount * 70)
                                .clamp(4.0, 70.0);

                        return SizedBox(
                          width: barWidth,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (staffCount > 0)
                                Text(
                                  '$staffCount',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: isShort
                                        ? Colors.red
                                        : Colors.teal[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              Container(
                                width: barWidth - 1,
                                height: barHeight,
                                decoration: BoxDecoration(
                                  color: isShort
                                      ? Colors.red[300]
                                      : Colors.teal[300],
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(2),
                                    topRight: Radius.circular(2),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (slots.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...slots.map((slot) {
            final start =
                slot['slot_start'].toString().substring(0, 5);
            final end = slot['slot_end'].toString().substring(0, 5);
            final minStaff = slot['min_staff'] as int;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      color: Colors.orange[300]),
                  const SizedBox(width: 6),
                  Text('$start 〜 $end：$minStaff名必要',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            );
          }),
        ],
        const SizedBox(height: 16),
        _buildShortagesSummary(allShifts),
      ],
    );
  }

  Widget _buildShortagesSummary(List<Map<String, dynamic>> allShifts) {
    final shortages = <String>[];
    if (allShifts.isEmpty && _todaySlots.isNotEmpty) {
      shortages.add('全時間帯で人員不足');
    } else {
      for (var slot in _todaySlots) {
        final start = _timeToDouble(
            slot['slot_start'].toString().substring(0, 5));
        final end = _timeToDouble(
            slot['slot_end'].toString().substring(0, 5));
        final minStaff = slot['min_staff'] as int;
        final midTime = (start + end) / 2;
        final count = _getStaffAtTime(midTime, allShifts).length;
        if (count < minStaff) {
          final startStr =
              slot['slot_start'].toString().substring(0, 5);
          final endStr = slot['slot_end'].toString().substring(0, 5);
          shortages.add(
              '$startStr〜$endStr：${count}名 / 必要${minStaff}名（${minStaff - count}名不足）');
        }
      }
    }

    if (shortages.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.teal[600], size: 18),
            const SizedBox(width: 8),
            const Text('全時間帯で必要人数を満たしています',
                style: TextStyle(fontSize: 13)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.red[600], size: 18),
              const SizedBox(width: 8),
              Text('人員不足あり',
                  style: TextStyle(
                      fontSize: 13,
                      color: Colors.red[700],
                      fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          ...shortages.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('・$s',
                    style: TextStyle(
                        fontSize: 12, color: Colors.red[600])),
              )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M/d(E)', 'ja');
    final workHours = _todayWorkHours;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text(fmt.format(_currentDate)),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    double startHour = 9.0;
    double endHour = 22.0;
    if (workHours != null) {
      startHour = _timeToDouble(
          workHours['work_start'].toString().substring(0, 5));
      endHour = _timeToDouble(
          workHours['work_end'].toString().substring(0, 5));
    }

    return Scaffold(
  appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(Icons.chevron_left,
                  color: _hasPrev ? Colors.white : Colors.white38),
              onPressed: _hasPrev ? _goToPrevDay : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
            const SizedBox(width: 4),
            Text(
                '${fmt.format(_currentDate)} ${_isHoliday ? '（休日）' : '（平日）'}'),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.chevron_right,
                  color: _hasNext ? Colors.white : Colors.white38),
              onPressed: _hasNext ? _goToNextDay : null,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ヘッダー
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _isHoliday ? Colors.red[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                workHours != null
                    ? '勤務時間帯：${workHours['work_start'].toString().substring(0, 5)} 〜 ${workHours['work_end'].toString().substring(0, 5)}　確定：${_confirmedShifts.length}名 / ヘルプ等：${_tempShifts.length}名'
                    : '勤務時間帯：未設定',
                style: TextStyle(
                  fontSize: 13,
                  color:
                      _isHoliday ? Colors.red[700] : Colors.blue[700],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 凡例
            Wrap(
              spacing: 12,
              children: [
                _legend(Colors.teal[500]!, Colors.white, '確定済み'),
                _legend(Colors.teal[200]!, Colors.teal[800]!, '出勤希望'),
                _legend(Colors.red[50]!, Colors.red[400]!, '希望休'),
                _legend(Colors.orange[400]!, Colors.white, 'ヘルプ等'),
              ],
            ),
            const SizedBox(height: 12),

            // スタッフ配置
            const Text('スタッフ配置',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const Text('タップしてシフトを確定・編集',
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 8),
            _buildTimeHeader(startHour, endHour),
            const SizedBox(height: 4),

            // 通常スタッフ
            ...widget.staff.map((m) {
              final profile =
                  m['user_profiles'] as Map<String, dynamic>;
              final userId = profile['id'] as String;
              final name = profile['name'] as String;
              final confirmed = _getConfirmedShift(userId);
              final request = _getRequestShift(userId);
              final isDayOff = _isDayOff(userId);

              return _buildStaffTimebar(
                name: name,
                confirmedShift: confirmed,
                requestShift: request,
                isDayOff: isDayOff,
                startHour: startHour,
                endHour: endHour,
                onTap: () => _showConfirmFromTimelineDialog(m),
              );
            }),

            // 二重線区切り
            const SizedBox(height: 4),
            Container(
              height: 3,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey[400]!, width: 1),
                  bottom: BorderSide(
                      color: Colors.grey[400]!, width: 1),
                ),
              ),
            ),
            const SizedBox(height: 4),

            // ヘルプ・タイミー行
            ..._tempShifts.map((shift) => _buildTempTimebar(
                  shift: shift,
                  startHour: startHour,
                  endHour: endHour,
                  onTap: () => _showEditTempDialog(shift),
                )),

            // ヘルプ追加ボタン
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 20),
              child: GestureDetector(
                onTap: _showAddTempDialog,
                child: Container(
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                        color: Colors.orange[300]!, width: 1),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add,
                          size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 4),
                      Text(
                        'ヘルプ・タイミーを追加',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // 時間帯別在籍数
            const Text('時間帯別在籍数',
                style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            _buildStaffingChart(startHour, endHour),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color bg, Color textColor, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    );
  }
}