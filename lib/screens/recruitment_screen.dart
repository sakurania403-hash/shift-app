import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/recruitment_service.dart';
import '../services/store_service.dart';
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

  // LinkedMap を安全に変換
  Map<String, dynamic> _toMap(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, dynamic>) return value;
    return Map<String, dynamic>.from(value as Map);
  }

  Future<void> _loadStores() async {
    final stores = await _storeService.getMyStores();
    setState(() {
      _stores = stores;
      if (stores.isNotEmpty) {
        final firstStore = _toMap(stores.first['stores']);
        _selectedStoreId = firstStore['id'] as String?;
        _selectedStoreName = firstStore['name'] as String?;
        _selectedRole = stores.first['role'] as String?;
      }
    });
    if (_selectedStoreId != null) {
      await _loadRecruitments();
    }
    setState(() => _isLoading = false);
  }

  Future<void> _loadRecruitments() async {
    if (_selectedStoreId == null) return;
    final result =
        await _recruitmentService.getRecruitments(_selectedStoreId!);
    setState(() => _recruitments = result);
  }

  Future<void> _showCreateDialog() async {
    final titleController = TextEditingController();
    DateTime? workStart;
    DateTime? workEnd;
    DateTime? requestStart;
    DateTime? requestEnd;
    final fmt = DateFormat('yyyy/MM/dd');

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('シフト募集を作成'),
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
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) {
                            setDialogState(() => workStart = d);
                          }
                        },
                        child: Text(workStart != null
                            ? fmt.format(workStart!)
                            : '開始日'),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('〜'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
                          );
                          if (d != null) {
                            setDialogState(() => workEnd = d);
                          }
                        },
                        child: Text(workEnd != null
                            ? fmt.format(workEnd!)
                            : '終了日'),
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
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
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
                      child: Text('〜'),
                    ),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final d = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2024),
                            lastDate: DateTime(2030),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            ElevatedButton(
              onPressed: () async {
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
                await _recruitmentService.createRecruitment(
                  storeId: _selectedStoreId!,
                  title: titleController.text.trim(),
                  workStart: workStart!,
                  workEnd: workEnd!,
                  requestStart: requestStart!,
                  requestEnd: requestEnd!,
                );
                if (context.mounted) Navigator.pop(context);
                await _loadRecruitments();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
              ),
              child: const Text('作成'),
            ),
          ],
        ),
      ),
    );
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
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                      ),
                                      icon: const Icon(Icons.people,
                                          size: 14),
                                      label: const Text('希望確認・シフト確定',
                                          style: TextStyle(fontSize: 12)),
                                    ),
                                    Row(
                                      children: [
                                        if (isOpen)
                                          TextButton(
                                            onPressed: () async {
                                              await _recruitmentService
                                                  .closeRecruitment(r['id']);
                                              await _loadRecruitments();
                                            },
                                            child: const Text('締め切る',
                                                style: TextStyle(
                                                    color: Colors.orange)),
                                          ),
                                        TextButton(
                                          onPressed: () async {
                                            await _recruitmentService
                                                .deleteRecruitment(r['id']);
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
                                                  storeId: _selectedStoreId!,
                                                  storeName:
                                                      _selectedStoreName!,
                                                ),
                                              ),
                                            );
                                          },
                                          style: OutlinedButton.styleFrom(
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
                                              style:
                                                  TextStyle(fontSize: 12)),
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
                                                storeId: _selectedStoreId!,
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
                                            style:
                                                TextStyle(fontSize: 12)),
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