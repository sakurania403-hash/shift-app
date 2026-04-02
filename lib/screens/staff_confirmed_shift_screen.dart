import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/shift_service.dart';
import '../services/store_settings_service.dart';
import '../services/member_service.dart';

class StaffConfirmedShiftScreen extends StatefulWidget {
  final Map<String, dynamic> recruitment;
  final String storeId;
  final String storeName;

  const StaffConfirmedShiftScreen({
    super.key,
    required this.recruitment,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<StaffConfirmedShiftScreen> createState() =>
      _StaffConfirmedShiftScreenState();
}

class _StaffConfirmedShiftScreenState
    extends State<StaffConfirmedShiftScreen> {
  final _shiftService = ShiftService();
  final _memberService = MemberService();

  List<Map<String, dynamic>> _staff = [];
  Map<String, Map<String, dynamic>> _confirmedMap = {};
  Map<String, List<Map<String, dynamic>>> _tempShifts = {};
  Map<String, bool> _holidayMap = {};
  List<String> _tempRows = [];
  bool _isLoading = true;
  late DateTime _workStart;
  late DateTime _workEnd;

  @override
  void initState() {
    super.initState();
    _workStart = DateTime.parse(widget.recruitment['work_start']);
    _workEnd = DateTime.parse(widget.recruitment['work_end']);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final members = await _shiftService.getStoreMembers(widget.storeId);
      final shifts = await _shiftService.getConfirmedShifts(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final holidays = await StoreSettingsService.getJapaneseHolidays();
      final holidayMap = <String, bool>{};
      for (var d in _dates) {
        final isHoliday = await StoreSettingsService.isHoliday(d, holidays);
        holidayMap[d.toIso8601String().substring(0, 10)] = isHoliday;
      }

      final confirmedMap = <String, Map<String, dynamic>>{};
      final tempMap = <String, List<Map<String, dynamic>>>{};
      for (var c in shifts) {
        final dateStr = c['date'].toString().substring(0, 10);
        if (c['staff_type'] == 'temp') {
          tempMap.putIfAbsent(dateStr, () => []).add(c);
        } else if (c['user_id'] != null) {
          final key = '${c['user_id']}_$dateStr';
          confirmedMap[key] = c;
        }
      }

      // store_temp_labelsからsort_order順でラベル取得
      final tempLabels = await _memberService.getTempLabels(widget.storeId);
      final registeredLabels =
          tempLabels.map((e) => e['label'] as String).toList();
      final allUsedLabels = <String>{};
      for (var list in tempMap.values) {
        for (var t in list) {
          final label = (t['temp_label'] ?? '') as String;
          if (label.isNotEmpty) allUsedLabels.add(label);
        }
      }
      final unregistered = allUsedLabels
          .where((l) => !registeredLabels.contains(l))
          .toList()
        ..sort();
      final rows = [...registeredLabels, ...unregistered];

      setState(() {
        _staff = members;
        _confirmedMap = confirmedMap;
        _tempShifts = tempMap;
        _holidayMap = holidayMap;
        _tempRows = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error: $e');
      setState(() => _isLoading = false);
    }
  }

  List<DateTime> get _dates {
    final dates = <DateTime>[];
    var d = DateTime(_workStart.year, _workStart.month, _workStart.day);
    final end = DateTime(_workEnd.year, _workEnd.month, _workEnd.day);
    while (!d.isAfter(end)) {
      dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    return dates;
  }

  String _getCellText(String userId, String dateStr) {
    final c = _confirmedMap['${userId}_$dateStr'];
    if (c == null) return '';
    final start = c['start_time']?.toString().substring(0, 5) ?? '';
    if (c['is_last'] == true) return '$start\n~L';
    final end = c['end_time']?.toString().substring(0, 5) ?? '';
    return '$start\n~$end';
  }

  Color _getCellColor(String userId, String dateStr) {
    return _confirmedMap.containsKey('${userId}_$dateStr')
        ? Colors.teal[500]!
        : Colors.white;
  }

  Color _getCellTextColor(String userId, String dateStr) {
    return _confirmedMap.containsKey('${userId}_$dateStr')
        ? Colors.white
        : Colors.grey[300]!;
  }

  int _confirmedCount(String dateStr) {
    int count = 0;
    for (var key in _confirmedMap.keys) {
      if (key.endsWith('_$dateStr')) count++;
    }
    count += (_tempShifts[dateStr]?.length ?? 0);
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final fmt = DateFormat('M/d', 'ja');
    final fmtDay = DateFormat('E', 'ja');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.recruitment['title']} - 確定シフト'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  color: Colors.teal[50],
                  child: Text(
                    '勤務期間：${DateFormat('yyyy/MM/dd').format(_workStart)} 〜 ${DateFormat('yyyy/MM/dd').format(_workEnd)}',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _legend(Colors.teal[500]!, Colors.white, '確定済み'),
                      const SizedBox(width: 12),
                      _legend(Colors.orange[400]!, Colors.white, 'ヘルプ等'),
                    ],
                  ),
                ),
                Expanded(
                  child: _staff.isEmpty && _tempRows.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.event_busy,
                                  size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'まだ確定されたシフトがありません',
                                style: TextStyle(
                                    color: Colors.grey[600], fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    _headerCell('スタッフ', 70, 68),
                                    ...dates.map((date) {
                                      final weekday = date.weekday;
                                      final isSunday =
                                          weekday == DateTime.sunday;
                                      final isSaturday =
                                          weekday == DateTime.saturday;
                                      final dateStr = date
                                          .toIso8601String()
                                          .substring(0, 10);
                                      final isHoliday =
                                          _holidayMap[dateStr] ?? false;
                                      final isRed = isSunday || isHoliday;
                                      final isBlue = isSaturday && !isHoliday;
                                      final confirmedCnt =
                                          _confirmedCount(dateStr);

                                      return Container(
                                        width: 62,
                                        height: 68,
                                        decoration: BoxDecoration(
                                          color: isRed
                                              ? Colors.red[50]
                                              : isBlue
                                                  ? Colors.blue[50]
                                                  : Colors.grey[100],
                                          border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 0.5),
                                        ),
                                        alignment: Alignment.center,
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              fmt.format(date),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.bold,
                                                color: isRed
                                                    ? Colors.red
                                                    : isBlue
                                                        ? Colors.blue
                                                        : Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              fmtDay.format(date),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isRed
                                                    ? Colors.red
                                                    : isBlue
                                                        ? Colors.blue
                                                        : Colors.grey[600],
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            if (confirmedCnt > 0)
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal[600],
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.people,
                                                        size: 8,
                                                        color: Colors.white),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      '$confirmedCnt人確定',
                                                      style: const TextStyle(
                                                        fontSize: 7,
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                                ..._staff.map((m) {
                                  final profile = Map<String, dynamic>.from(
                                      m['user_profiles'] as Map);
                                  final userId = profile['id'] as String;
                                  final name = profile['name'] as String;

                                  return Row(
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: Colors.teal[50],
                                          border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 0.5),
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(4),
                                        child: Text(
                                          name,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.teal[800],
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      ...dates.map((date) {
                                        final dateStr = date
                                            .toIso8601String()
                                            .substring(0, 10);
                                        return Container(
                                          width: 62,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color:
                                                _getCellColor(userId, dateStr),
                                            border: Border.all(
                                                color: Colors.grey[200]!,
                                                width: 0.5),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            _getCellText(userId, dateStr),
                                            style: TextStyle(
                                              fontSize: 8,
                                              color: _getCellTextColor(
                                                  userId, dateStr),
                                              fontWeight: FontWeight.w500,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                }),
                                if (_tempRows.isNotEmpty)
                                  Container(
                                    height: 2,
                                    color: Colors.orange[200],
                                  ),
                                ..._tempRows.map((label) {
                                  final isTimee = label.startsWith('タイミー');
                                  return Row(
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: Colors.orange[50],
                                          border: Border.all(
                                              color: Colors.grey[300]!,
                                              width: 0.5),
                                        ),
                                        alignment: Alignment.center,
                                        padding: const EdgeInsets.all(4),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: isTimee
                                                ? Colors.orange[700]
                                                : Colors.deepOrange[700],
                                            fontWeight: FontWeight.w500,
                                          ),
                                          textAlign: TextAlign.center,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      ...dates.map((date) {
                                        final dateStr = date
                                            .toIso8601String()
                                            .substring(0, 10);
                                        final temps =
                                            _tempShifts[dateStr] ?? [];
                                        final temp = temps.firstWhere(
                                          (t) =>
                                              (t['temp_label'] ?? '') == label,
                                          orElse: () => {},
                                        );

                                        if (temp.isEmpty) {
                                          return Container(
                                            width: 62,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                  color: Colors.grey[200]!,
                                                  width: 0.5),
                                            ),
                                          );
                                        }

                                        final start = temp['start_time']
                                                ?.toString()
                                                .substring(0, 5) ??
                                            '';
                                        final isLast = temp['is_last'] == true;
                                        final end = isLast
                                            ? 'L'
                                            : temp['end_time']
                                                    ?.toString()
                                                    .substring(0, 5) ??
                                                '';

                                        return Container(
                                          width: 62,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: Colors.orange[50],
                                            border: Border.all(
                                                color: Colors.grey[200]!,
                                                width: 0.5),
                                          ),
                                          alignment: Alignment.center,
                                          child: Container(
                                            margin: const EdgeInsets.all(2),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 2, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: Colors.orange[400],
                                              borderRadius:
                                                  BorderRadius.circular(3),
                                            ),
                                            child: Text(
                                              '$start\n~$end',
                                              style: const TextStyle(
                                                fontSize: 7,
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _headerCell(String text, double width, double height) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border.all(color: Colors.grey[300]!, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
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
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}