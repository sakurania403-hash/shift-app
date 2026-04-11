import 'dart:convert';
import 'package:universal_html/html.dart' as html;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:intl/intl.dart';
import '../services/admin_shift_service.dart';
import '../services/member_service.dart';
import 'shift_timeline_screen.dart';

class AdminShiftOverviewScreen extends StatefulWidget {
  final Map<String, dynamic> recruitment;
  final String storeId;
  final String storeName;

  const AdminShiftOverviewScreen({
    super.key,
    required this.recruitment,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<AdminShiftOverviewScreen> createState() =>
      _AdminShiftOverviewScreenState();
}

class _AdminShiftOverviewScreenState
    extends State<AdminShiftOverviewScreen> {
  final _service = AdminShiftService();
  final _memberService = MemberService();
  final _repaintKey = GlobalKey();

  List<Map<String, dynamic>> _staff = [];
  Map<String, Map<String, dynamic>> _shiftRequests = {};
  Map<String, Map<String, dynamic>> _dayOffRequests = {};
  Map<String, Map<String, dynamic>> _confirmedShifts = {};
  Map<String, List<Map<String, dynamic>>> _tempShifts = {};
  List<Map<String, dynamic>> _submissions = [];
  List<String> _tempRows = [];
  bool _isLoading = true;
  bool _isSaving = false;
  late DateTime _workStart;
  late DateTime _workEnd;

  // 募集が open かどうか（再募集中は希望を優先表示）
  bool get _isOpen => widget.recruitment['status'] == 'open';

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
      final confirmed = await _service.getConfirmedShifts(
        storeId: widget.storeId,
        from: _workStart,
        to: _workEnd,
      );
      final tempLabels =
          await _memberService.getTempLabels(widget.storeId);

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

      final confirmedMap = <String, Map<String, dynamic>>{};
      final tempMap = <String, List<Map<String, dynamic>>>{};
      for (var c in confirmed) {
        final dateStr = c['date'].toString().substring(0, 10);
        if (c['staff_type'] == 'temp') {
          tempMap.putIfAbsent(dateStr, () => []).add(c);
        } else if (c['user_id'] != null) {
          final key = '${c['user_id']}_$dateStr';
          confirmedMap[key] = c;
        }
      }

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
        _staff = staff;
        _shiftRequests = shiftMap;
        _dayOffRequests = dayOffMap;
        _confirmedShifts = confirmedMap;
        _tempShifts = tempMap;
        _submissions = submissions;
        _tempRows = rows;
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
    final end =
        DateTime(_workEnd.year, _workEnd.month, _workEnd.day);
    while (!d.isAfter(end)) {
      dates.add(d);
      d = d.add(const Duration(days: 1));
    }
    return dates;
  }

  bool _isSubmitted(String userId) =>
      _submissions.any((s) => s['user_id'] == userId);

  bool _isConfirmed(String userId, String dateStr) =>
      _confirmedShifts.containsKey('${userId}_$dateStr');

  int _confirmedCount(String dateStr) {
    int count = 0;
    for (var m in _staff) {
      final profile =
          m['user_profiles'] as Map<String, dynamic>;
      final userId = profile['id'] as String;
      if (_confirmedShifts.containsKey('${userId}_$dateStr'))
        count++;
    }
    count += (_tempShifts[dateStr]?.length ?? 0);
    return count;
  }

  // ─── セルテキスト ────────────────────────────────────────────
  // open（再募集中）の場合：希望シフト → 確定シフト の優先順
  // closed（締切）の場合：確定シフト → 希望シフト の優先順（従来通り）
  String _getCellText(String userId, String dateStr) {
    final confirmedKey = '${userId}_$dateStr';
    final hasConfirmed = _confirmedShifts.containsKey(confirmedKey);
    final shift = _shiftRequests['${userId}_$dateStr'];
    final hasDayOff = _dayOffRequests.containsKey('${userId}_$dateStr');

    if (_isOpen) {
      // 再募集中：希望シフトを優先表示
      if (hasDayOff) return '休';
      if (shift != null) {
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
      // 希望がなければ確定シフトを表示
      if (hasConfirmed) {
        final c = _confirmedShifts[confirmedKey]!;
        final start =
            c['start_time']?.toString().substring(0, 5) ?? '';
        if (c['is_last'] == true) return '$start\n~L';
        final end = c['end_time']?.toString().substring(0, 5) ?? '';
        return '$start\n~$end';
      }
      return '';
    } else {
      // 締切済み：確定シフトを優先表示（従来通り）
      if (hasConfirmed) {
        final c = _confirmedShifts[confirmedKey]!;
        final start =
            c['start_time']?.toString().substring(0, 5) ?? '';
        if (c['is_last'] == true) return '$start\n~L';
        final end = c['end_time']?.toString().substring(0, 5) ?? '';
        return '$start\n~$end';
      }
      if (hasDayOff) return '休';
      if (shift != null) {
        final start =
            shift['preferred_start']?.toString().substring(0, 5) ??
                '';
        if (shift['is_last'] == true) {
          return start.isEmpty ? 'L' : '$start\n~L';
        }
        final end =
            shift['preferred_end']?.toString().substring(0, 5) ?? '';
        if (start.isEmpty) return '○';
        return '$start\n~$end';
      }
      return '';
    }
  }

  // ─── セル背景色 ──────────────────────────────────────────────
  Color _getCellColor(String userId, String dateStr) {
    final hasConfirmed = _isConfirmed(userId, dateStr);
    final key = '${userId}_$dateStr';
    final hasDayOff = _dayOffRequests.containsKey(key);
    final hasShift = _shiftRequests.containsKey(key);

    if (_isOpen) {
      // 再募集中：希望シフトを優先
      if (hasDayOff) return Colors.red[50]!;
      if (hasShift) return Colors.teal[50]!;
      // 希望がなければ確定シフトの色
      if (hasConfirmed) return Colors.teal[200]!; // 薄めの確定色
      return Colors.white;
    } else {
      // 締切済み：確定シフトを優先
      if (hasConfirmed) return Colors.teal[500]!;
      if (hasDayOff) return Colors.red[50]!;
      if (hasShift) return Colors.teal[50]!;
      return Colors.white;
    }
  }

  // ─── セル文字色 ──────────────────────────────────────────────
  Color _getCellTextColor(String userId, String dateStr) {
    final hasConfirmed = _isConfirmed(userId, dateStr);
    final key = '${userId}_$dateStr';
    final hasDayOff = _dayOffRequests.containsKey(key);
    final hasShift = _shiftRequests.containsKey(key);

    if (_isOpen) {
      if (hasDayOff) return Colors.red[400]!;
      if (hasShift) return Colors.teal[700]!;
      if (hasConfirmed) return Colors.teal[600]!;
      return Colors.grey[400]!;
    } else {
      if (hasConfirmed) return Colors.white;
      if (hasDayOff) return Colors.red[400]!;
      if (hasShift) return Colors.teal[700]!;
      return Colors.grey[400]!;
    }
  }

  int _getSubmittedCount(String userId) {
    int count = 0;
    for (var d in _dates) {
      final dateStr = d.toIso8601String().substring(0, 10);
      final key = '${userId}_$dateStr';
      if (_shiftRequests.containsKey(key) ||
          _dayOffRequests.containsKey(key)) {
        count++;
      }
    }
    return count;
  }

  Future<void> _shareShift() async {
    setState(() => _isSaving = true);
    try {
      final boundary = _repaintKey.currentContext
          ?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;

      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final bytes = byteData.buffer.asUint8List();
      final base64str = base64Encode(bytes);
      final dataUrl = 'data:image/png;base64,$base64str';

      final title = widget.recruitment['title'] ?? 'shift';
      html.AnchorElement(href: dataUrl)
        ..setAttribute('download', '$title.png')
        ..click();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('シフト表を画像としてダウンロードしました'),
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
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = _dates;
    final fmt = DateFormat('M/d', 'ja');
    final fmtDay = DateFormat('E', 'ja');

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.recruitment['title']} - 希望確認'),
        backgroundColor:
            Theme.of(context).colorScheme.inversePrimary,
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
                  color: _isOpen
                      ? Colors.orange[50]
                      : Colors.teal[50],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '勤務期間：${DateFormat('yyyy/MM/dd').format(_workStart)} 〜 ${DateFormat('yyyy/MM/dd').format(_workEnd)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'スタッフ数：${_staff.length}名　提出済み：${_submissions.length}名',
                            style: TextStyle(
                                fontSize: 13,
                                color: Colors.teal[700]),
                          ),
                          if (_isOpen) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange[100],
                                borderRadius:
                                    BorderRadius.circular(8),
                              ),
                              child: Text(
                                '再募集中 - 希望シフトを優先表示',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange[800],
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ],
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
                      Expanded(
                        child: Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            if (!_isOpen)
                              _legend(Colors.teal[500]!,
                                  Colors.white, '確定済み'),
                            if (_isOpen)
                              _legend(Colors.teal[200]!,
                                  Colors.teal[600]!, '確定済み（希望未提出）'),
                            _legend(Colors.teal[50]!,
                                Colors.teal[700]!, '出勤希望'),
                            _legend(Colors.red[50]!,
                                Colors.red[400]!, '希望休'),
                            _legend(Colors.white,
                                Colors.grey[400]!, '未提出'),
                            _legend(Colors.orange[400]!,
                                Colors.white, 'ヘルプ等'),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _isSaving ? null : _shareShift,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.download, size: 16),
                        label: const Text('シフト共有',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _staff.isEmpty
                      ? const Center(child: Text('スタッフがいません'))
                      : RepaintBoundary(
                          key: _repaintKey,
                          child: Container(
                            color: Colors.white,
                            child: SingleChildScrollView(
                              scrollDirection: Axis.vertical,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        _headerCell(
                                            'スタッフ', 70, 68),
                                        ...dates.map((date) {
                                          final weekday =
                                              date.weekday;
                                          final isSunday = weekday ==
                                              DateTime.sunday;
                                          final isSaturday =
                                              weekday ==
                                                  DateTime.saturday;
                                          final dateStr = date
                                              .toIso8601String()
                                              .substring(0, 10);
                                          final confirmedCnt =
                                              _confirmedCount(
                                                  dateStr);

                                          return GestureDetector(
                                            onTap: () {
                                              Navigator.push(
                                                context,
                                                MaterialPageRoute(
                                                  builder: (_) => ShiftTimelineScreen(
  date: date,
  storeId: widget.storeId,
  storeName: widget.storeName,
  confirmedShifts: _confirmedShifts.values.toList(),
  staff: _staff,
  shiftRequests: _shiftRequests.values.toList(),
  dayOffRequests: _dayOffRequests.values.toList(),
  allDates: dates,
),
                                                ),
                                              ).then(
                                                  (_) => _loadData());
                                            },
                                            child: Container(
                                              width: 62,
                                              height: 68,
                                              decoration: BoxDecoration(
                                                color: isSunday
                                                    ? Colors.red[50]
                                                    : isSaturday
                                                        ? Colors
                                                            .blue[50]
                                                        : Colors
                                                            .grey[100],
                                                border: Border.all(
                                                    color: Colors
                                                        .grey[300]!,
                                                    width: 0.5),
                                              ),
                                              alignment:
                                                  Alignment.center,
                                              child: Column(
                                                mainAxisAlignment:
                                                    MainAxisAlignment
                                                        .center,
                                                children: [
                                                  Text(
                                                    fmt.format(date),
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight
                                                              .bold,
                                                      color: isSunday
                                                          ? Colors.red
                                                          : isSaturday
                                                              ? Colors
                                                                  .blue
                                                              : Colors
                                                                  .black87,
                                                    ),
                                                  ),
                                                  Text(
                                                    fmtDay
                                                        .format(date),
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      color: isSunday
                                                          ? Colors.red
                                                          : isSaturday
                                                              ? Colors
                                                                  .blue
                                                              : Colors
                                                                  .grey[600],
                                                    ),
                                                  ),
                                                  const SizedBox(
                                                      height: 4),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal:
                                                                4,
                                                            vertical:
                                                                2),
                                                    decoration:
                                                        BoxDecoration(
                                                      color: confirmedCnt >
                                                              0
                                                          ? Colors
                                                              .teal[600]
                                                          : Colors
                                                              .grey[500],
                                                      borderRadius:
                                                          BorderRadius
                                                              .circular(
                                                                  4),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize:
                                                          MainAxisSize
                                                              .min,
                                                      children: [
                                                        const Icon(
                                                            Icons
                                                                .people,
                                                            size: 8,
                                                            color: Colors
                                                                .white),
                                                        const SizedBox(
                                                            width: 2),
                                                        Text(
                                                          confirmedCnt >
                                                                  0
                                                              ? '$confirmedCnt人確定'
                                                              : '人員確認',
                                                          style:
                                                              const TextStyle(
                                                            fontSize: 7,
                                                            color: Colors
                                                                .white,
                                                            fontWeight:
                                                                FontWeight
                                                                    .bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                    ..._staff.map((m) {
                                      final profile =
                                          m['user_profiles']
                                              as Map<String, dynamic>;
                                      final userId =
                                          profile['id'] as String;
                                      final name =
                                          profile['name'] as String;

                                      return Row(
                                        children: [
                                          Container(
                                            width: 70,
                                            height: 52,
                                            decoration: BoxDecoration(
                                              color: Colors.teal[50],
                                              border: Border.all(
                                                  color:
                                                      Colors.grey[300]!,
                                                  width: 0.5),
                                            ),
                                            alignment: Alignment.center,
                                            padding:
                                                const EdgeInsets.all(4),
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w500,
                                                color: Colors.teal[800],
                                              ),
                                              textAlign:
                                                  TextAlign.center,
                                              overflow:
                                                  TextOverflow.ellipsis,
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
                                                color: _getCellColor(
                                                    userId, dateStr),
                                                border: Border.all(
                                                    color: Colors
                                                        .grey[200]!,
                                                    width: 0.5),
                                              ),
                                              alignment: Alignment.center,
                                              child: Text(
                                                _getCellText(
                                                    userId, dateStr),
                                                style: TextStyle(
                                                  fontSize: 8,
                                                  color: _getCellTextColor(
                                                      userId, dateStr),
                                                  fontWeight:
                                                      FontWeight.w500,
                                                ),
                                                textAlign:
                                                    TextAlign.center,
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
                                      final isTimee =
                                          label.startsWith('タイミー');
                                      return Row(
                                        children: [
                                          Container(
                                            width: 70,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: Colors.orange[50],
                                              border: Border.all(
                                                  color:
                                                      Colors.grey[300]!,
                                                  width: 0.5),
                                            ),
                                            alignment: Alignment.center,
                                            padding:
                                                const EdgeInsets.all(4),
                                            child: Text(
                                              label,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: isTimee
                                                    ? Colors.orange[700]
                                                    : Colors
                                                        .deepOrange[700],
                                                fontWeight:
                                                    FontWeight.w500,
                                              ),
                                              textAlign:
                                                  TextAlign.center,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                            ),
                                          ),
                                          ...dates.map((date) {
                                            final dateStr = date
                                                .toIso8601String()
                                                .substring(0, 10);
                                            final temps =
                                                _tempShifts[dateStr] ??
                                                    [];
                                            final temp = temps.firstWhere(
                                              (t) =>
                                                  (t['temp_label'] ??
                                                      '') ==
                                                  label,
                                              orElse: () => {},
                                            );

                                            if (temp.isEmpty) {
                                              return Container(
                                                width: 62,
                                                height: 44,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  border: Border.all(
                                                      color: Colors
                                                          .grey[200]!,
                                                      width: 0.5),
                                                ),
                                              );
                                            }

                                            final start = temp[
                                                        'start_time']
                                                    ?.toString()
                                                    .substring(0, 5) ??
                                                '';
                                            final isLast =
                                                temp['is_last'] == true;
                                            final end = isLast
                                                ? 'L'
                                                : temp['end_time']
                                                        ?.toString()
                                                        .substring(
                                                            0, 5) ??
                                                    '';

                                            return Container(
                                              width: 62,
                                              height: 44,
                                              decoration: BoxDecoration(
                                                color: Colors.orange[50],
                                                border: Border.all(
                                                    color: Colors
                                                        .grey[200]!,
                                                    width: 0.5),
                                              ),
                                              alignment: Alignment.center,
                                              child: Container(
                                                margin:
                                                    const EdgeInsets.all(
                                                        2),
                                                padding: const EdgeInsets
                                                    .symmetric(
                                                    horizontal: 2,
                                                    vertical: 1),
                                                decoration: BoxDecoration(
                                                  color:
                                                      Colors.orange[400],
                                                  borderRadius:
                                                      BorderRadius
                                                          .circular(3),
                                                ),
                                                child: Text(
                                                  '$start\n~$end',
                                                  style: const TextStyle(
                                                    fontSize: 7,
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.bold,
                                                  ),
                                                  textAlign:
                                                      TextAlign.center,
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
        border:
            Border.all(color: Colors.grey[300]!, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold),
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
            style: TextStyle(
                fontSize: 11, color: Colors.grey[600])),
      ],
    );
  }
}