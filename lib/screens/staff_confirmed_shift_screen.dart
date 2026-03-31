import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/shift_service.dart';
import '../services/store_settings_service.dart';

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
  List<Map<String, dynamic>> _confirmedShifts = [];
  bool _isLoading = true;
  late DateTime _workStart;
  late DateTime _workEnd;
  Map<String, bool> _holidayMap = {};

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
      final shifts = await _shiftService.getMyConfirmedShifts(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final holidays = await StoreSettingsService.getJapaneseHolidays();

      // 祝日マップを作成
      final holidayMap = <String, bool>{};
      for (var d in _dates) {
        final isHoliday =
            await StoreSettingsService.isHoliday(d, holidays);
        holidayMap[d.toIso8601String().substring(0, 10)] = isHoliday;
      }

      setState(() {
        _confirmedShifts = shifts;
        _holidayMap = holidayMap;
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

  Map<String, dynamic>? _getShift(String dateStr) {
    final found = _confirmedShifts
        .where((s) => s['date'].toString().substring(0, 10) == dateStr)
        .toList();
    return found.isNotEmpty ? found.first : null;
  }

  // 合計勤務時間を計算（ラストは22時として計算）
  double _calcTotalHours() {
    double total = 0;
    for (var s in _confirmedShifts) {
      final start = s['start_time']?.toString().substring(0, 5);
      if (start == null) continue;
      final startParts = start.split(':');
      final startH =
          int.parse(startParts[0]) + int.parse(startParts[1]) / 60.0;

      double endH;
      if (s['is_last'] == true || s['end_time'] == null) {
        endH = 22.0; // ラストは22時として計算
      } else {
        final end = s['end_time'].toString().substring(0, 5);
        final endParts = end.split(':');
        endH =
            int.parse(endParts[0]) + int.parse(endParts[1]) / 60.0;
      }
      total += endH - startH;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('M/d(E)', 'ja');
    final fmtMonth = DateFormat('yyyy年M月', 'ja');
    final dates = _dates;
    final totalHours = _calcTotalHours();
    final confirmedDays = _confirmedShifts.length;

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
                // サマリーカード
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.teal[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.teal[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.storeName,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.teal[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${DateFormat('yyyy/MM/dd').format(_workStart)} 〜 ${DateFormat('yyyy/MM/dd').format(_workEnd)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _summaryItem(
                            Icons.calendar_today,
                            '$confirmedDays日',
                            '確定日数',
                            Colors.teal,
                          ),
                          const SizedBox(width: 24),
                          _summaryItem(
                            Icons.access_time,
                            confirmedDays == 0
                                ? '0時間'
                                : '${totalHours.toStringAsFixed(1)}h',
                            'ラスト除く目安',
                            Colors.blue,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 凡例
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      _legend(Colors.teal[500]!, '確定済み'),
                      const SizedBox(width: 16),
                      _legend(Colors.grey[200]!, '未確定'),
                    ],
                  ),
                ),
                // シフトリスト
                Expanded(
                  child: confirmedDays == 0
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
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          itemCount: dates.length,
                          itemBuilder: (context, index) {
                            final date = dates[index];
                            final dateStr =
                                date.toIso8601String().substring(0, 10);
                            final shift = _getShift(dateStr);
                            final isHoliday =
                                _holidayMap[dateStr] ?? false;
                            final isSunday =
                                date.weekday == DateTime.sunday;
                            final isSaturday =
                                date.weekday == DateTime.saturday;
                            final isRed =
                                isSunday || isHoliday;
                            final isBlue = isSaturday && !isHoliday;

                            // 月の区切り
                            final showMonthHeader = index == 0 ||
                                dates[index - 1].month != date.month;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (showMonthHeader)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                        top: 8, bottom: 4, left: 4),
                                    child: Text(
                                      fmtMonth.format(date),
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ),
                                Container(
                                  margin:
                                      const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: shift != null
                                        ? Colors.teal[50]
                                        : Colors.grey[50],
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    border: Border.all(
                                      color: shift != null
                                          ? Colors.teal[200]!
                                          : Colors.grey[200]!,
                                    ),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    child: Row(
                                      children: [
                                        // 日付
                                        SizedBox(
                                          width: 80,
                                          child: Text(
                                            fmt.format(date),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: isRed
                                                  ? Colors.red
                                                  : isBlue
                                                      ? Colors.blue
                                                      : Colors.black87,
                                            ),
                                          ),
                                        ),
                                        // 祝日ラベル
                                        if (isHoliday)
                                          Container(
                                            margin: const EdgeInsets.only(
                                                right: 8),
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.red[50],
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                              border: Border.all(
                                                  color: Colors.red[200]!),
                                            ),
                                            child: Text(
                                              '祝',
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.red[400]),
                                            ),
                                          ),
                                        // シフト内容
                                        Expanded(
                                          child: shift != null
                                              ? _buildShiftBar(shift)
                                              : Text(
                                                  '未確定',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Colors.grey[400],
                                                  ),
                                                ),
                                        ),
                                      ],
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
    );
  }

  Widget _buildShiftBar(Map<String, dynamic> shift) {
    final start =
        shift['start_time']?.toString().substring(0, 5) ?? '';
    final isLast = shift['is_last'] == true;
    final end = isLast
        ? 'ラスト'
        : shift['end_time']?.toString().substring(0, 5) ?? '';

    return Row(
      children: [
        Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.teal[500],
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '$start 〜 $end',
            style: const TextStyle(
              fontSize: 13,
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (isLast)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange[100],
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'L',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.orange[800],
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _summaryItem(
      IconData icon, String value, String label, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: Colors.grey[300]!),
          ),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}