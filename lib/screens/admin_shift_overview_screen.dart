import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/admin_shift_service.dart';

class AdminShiftOverviewScreen extends StatefulWidget {
  final Map<String, dynamic> recruitment;
  final String storeId;

  const AdminShiftOverviewScreen({
    super.key,
    required this.recruitment,
    required this.storeId,
  });

  @override
  State<AdminShiftOverviewScreen> createState() =>
      _AdminShiftOverviewScreenState();
}

class _AdminShiftOverviewScreenState
    extends State<AdminShiftOverviewScreen> {
  final _service = AdminShiftService();
  List<Map<String, dynamic>> _staff = [];
  Map<String, Map<String, dynamic>> _shiftRequests = {};
  Map<String, Map<String, dynamic>> _dayOffRequests = {};
  List<Map<String, dynamic>> _submissions = [];
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
      final staff = await _service.getStoreStaff(widget.storeId);
      final shifts = await _service.getAllShiftRequests(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final dayOffs = await _service.getAllDayOffRequests(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final submissions =
          await _service.getSubmissions(widget.recruitment['id']);

      final shiftMap = <String, Map<String, dynamic>>{};
      for (var s in shifts) {
        final key = '${s['user_id']}_${s['date']}';
        shiftMap[key] = s;
      }

      final dayOffMap = <String, Map<String, dynamic>>{};
      for (var d in dayOffs) {
        final key = '${d['user_id']}_${d['date']}';
        dayOffMap[key] = d;
      }

      setState(() {
        _staff = staff;
        _shiftRequests = shiftMap;
        _dayOffRequests = dayOffMap;
        _submissions = submissions;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
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

  bool _isSubmitted(String userId) {
    return _submissions.any((s) => s['user_id'] == userId);
  }

  String _getCellText(String userId, String dateStr) {
    final key = '${userId}_$dateStr';
    if (_dayOffRequests.containsKey(key)) return '休';
    final shift = _shiftRequests[key];
    if (shift == null) return '';
    final start =
        shift['preferred_start']?.toString().substring(0, 5) ?? '';
    if (shift['is_last'] == true) {
      return start.isEmpty ? 'L' : '$start\n~L';
    }
    final end =
        shift['preferred_end']?.toString().substring(0, 5) ?? '';
    if (start.isEmpty) return '○';
    return '$start\n~$end';
  }

  Color _getCellColor(String userId, String dateStr) {
    final key = '${userId}_$dateStr';
    if (_dayOffRequests.containsKey(key)) return Colors.red[50]!;
    if (_shiftRequests.containsKey(key)) return Colors.teal[50]!;
    return Colors.white;
  }

  Color _getCellTextColor(String userId, String dateStr) {
    final key = '${userId}_$dateStr';
    if (_dayOffRequests.containsKey(key)) return Colors.red[400]!;
    if (_shiftRequests.containsKey(key)) return Colors.teal[700]!;
    return Colors.grey[400]!;
  }

  int _getSubmittedCount(String userId) {
    final dates = _dates;
    int count = 0;
    for (var d in dates) {
      final dateStr = d.toIso8601String().substring(0, 10);
      final key = '${userId}_$dateStr';
      if (_shiftRequests.containsKey(key) ||
          _dayOffRequests.containsKey(key)) {
        count++;
      }
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final fmt = DateFormat('M/d', 'ja');
    final fmtDay = DateFormat('E', 'ja');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.recruitment['title']} - 希望確認'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '勤務期間：${DateFormat('yyyy/MM/dd').format(_workStart)} 〜 ${DateFormat('yyyy/MM/dd').format(_workEnd)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'スタッフ数：${_staff.length}名　提出済み：${_submissions.length}名',
                        style: TextStyle(
                            fontSize: 13, color: Colors.teal[700]),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: _staff.map((m) {
                          final profile = m['user_profiles']
                              as Map<String, dynamic>;
                          final userId = profile['id'] as String;
                          final name = profile['name'] as String;
                          final submitted = _isSubmitted(userId);
                          final count = _getSubmittedCount(userId);
                          return Chip(
                            label: Text(
                              '$name ${submitted ? '提出済' : '未提出'} $count/${dates.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: submitted
                                    ? Colors.teal[700]
                                    : Colors.orange[700],
                              ),
                            ),
                            backgroundColor: submitted
                                ? Colors.teal[50]
                                : Colors.orange[50],
                            padding: EdgeInsets.zero,
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      _legend(Colors.teal[50]!, Colors.teal[700]!, '出勤希望'),
                      const SizedBox(width: 12),
                      _legend(Colors.red[50]!, Colors.red[400]!, '希望休'),
                      const SizedBox(width: 12),
                      _legend(Colors.white, Colors.grey[400]!, '未提出'),
                    ],
                  ),
                ),
                Expanded(
                  child: _staff.isEmpty
                      ? const Center(child: Text('スタッフがいません'))
                      : SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 70,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[100],
                                        border: Border.all(
                                            color: Colors.grey[300]!,
                                            width: 0.5),
                                      ),
                                      alignment: Alignment.center,
                                      child: const Text(
                                        'スタッフ',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    ...dates.map((date) {
                                      final weekday = date.weekday;
                                      final isSunday =
                                          weekday == DateTime.sunday;
                                      final isSaturday =
                                          weekday == DateTime.saturday;
                                      return Container(
                                        width: 52,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: isSunday
                                              ? Colors.red[50]
                                              : isSaturday
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
                                                color: isSunday
                                                    ? Colors.red
                                                    : isSaturday
                                                        ? Colors.blue
                                                        : Colors.black87,
                                              ),
                                            ),
                                            Text(
                                              fmtDay.format(date),
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isSunday
                                                    ? Colors.red
                                                    : isSaturday
                                                        ? Colors.blue
                                                        : Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                                ..._staff.map((m) {
                                  final profile = m['user_profiles']
                                      as Map<String, dynamic>;
                                  final userId = profile['id'] as String;
                                  final name = profile['name'] as String;
                                  final submitted = _isSubmitted(userId);

                                  return Row(
                                    children: [
                                      Container(
                                        width: 70,
                                        height: 52,
                                        decoration: BoxDecoration(
                                          color: submitted
                                              ? Colors.teal[50]
                                              : Colors.orange[50],
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
                                            color: submitted
                                                ? Colors.teal[800]
                                                : Colors.orange[800],
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
                                          width: 52,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: _getCellColor(
                                                userId, dateStr),
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
                              ],
                            ),
                          ),
                        ),
                ),
              ],
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