import 'package:flutter/material.dart';
import '../services/store_settings_service.dart';
import '../services/store_service.dart';

class StoreSettingsScreen extends StatefulWidget {
  const StoreSettingsScreen({super.key});

  @override
  State<StoreSettingsScreen> createState() => _StoreSettingsScreenState();
}

class _StoreSettingsScreenState extends State<StoreSettingsScreen>
    with SingleTickerProviderStateMixin {
  final _settingsService = StoreSettingsService();
  final _storeService = StoreService();
  late TabController _tabController;
  List<Map<String, dynamic>> _stores = [];
  String? _selectedStoreId;
  String? _selectedStoreName;
  List<Map<String, dynamic>> _workHours = [];
  List<Map<String, dynamic>> _staffingSlots = [];
  List<Map<String, dynamic>> _breakRules = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStores();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final stores = await _storeService.getMyStores();
    final adminStores =
        stores.where((m) => m['role'] == 'admin').toList();
    setState(() {
      _stores = adminStores;
      if (adminStores.isNotEmpty) {
        final first =
            adminStores.first['stores'] as Map<String, dynamic>;
        _selectedStoreId = first['id'];
        _selectedStoreName = first['name'];
      }
    });
    if (_selectedStoreId != null) await _loadSettings();
    setState(() => _isLoading = false);
  }

  Future<void> _loadSettings() async {
    if (_selectedStoreId == null) return;
    final workHours =
        await _settingsService.getWorkHours(_selectedStoreId!);
    final staffingSlots =
        await _settingsService.getStaffingSlots(_selectedStoreId!);
    final breakRules =
        await _settingsService.getBreakRules(_selectedStoreId!);
    setState(() {
      _workHours = workHours;
      _staffingSlots = staffingSlots;
      _breakRules = breakRules;
    });
  }

  Future<void> _showWorkHoursDialog(String dayType) async {
    final existing = _workHours
        .where((w) => w['day_type'] == dayType)
        .toList();
    final e = existing.isNotEmpty ? existing.first : null;
    final startController = TextEditingController(
        text: e?['work_start']?.toString().substring(0, 5) ?? '09:00');
    final endController = TextEditingController(
        text: e?['work_end']?.toString().substring(0, 5) ?? '22:00');
    final label = dayType == 'weekday' ? '平日' : '休日（土日・祝日）';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label 勤務時間帯'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: '開始時間',
                      hintText: '09:00',
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
                    decoration: const InputDecoration(
                      labelText: '終了時間',
                      hintText: '22:00',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _settingsService.upsertWorkHours(
                storeId: _selectedStoreId!,
                dayType: dayType,
                workStart: startController.text.trim(),
                workEnd: endController.text.trim(),
              );
              if (context.mounted) Navigator.pop(context);
              await _loadSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _showStaffingSlotDialog(String dayType) async {
    final startController = TextEditingController();
    final endController = TextEditingController();
    final minStaffController = TextEditingController(text: '1');
    final label = dayType == 'weekday' ? '平日' : '休日';

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$label 時間帯別必要人数を追加'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: startController,
                    decoration: const InputDecoration(
                      labelText: '開始',
                      hintText: '09:00',
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
                    decoration: const InputDecoration(
                      labelText: '終了',
                      hintText: '12:00',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _settingsService.addStaffingSlot(
                storeId: _selectedStoreId!,
                dayType: dayType,
                slotStart: startController.text.trim(),
                slotEnd: endController.text.trim(),
                minStaff:
                    int.tryParse(minStaffController.text.trim()) ?? 1,
              );
              if (context.mounted) Navigator.pop(context);
              await _loadSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBreakRuleDialog() async {
    final thresholdController = TextEditingController();
    final breakController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('休憩ルールを追加'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: thresholdController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '勤務時間',
                  suffixText: '時間以上',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: breakController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '休憩',
                  suffixText: '分',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _settingsService.addBreakRule(
                storeId: _selectedStoreId!,
                workHoursThreshold:
                    double.tryParse(thresholdController.text.trim()) ?? 6,
                breakMinutes:
                    int.tryParse(breakController.text.trim()) ?? 45,
              );
              if (context.mounted) Navigator.pop(context);
              await _loadSettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            child: const Text('追加'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkHoursTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final dayType in ['weekday', 'holiday']) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: dayType == 'weekday'
                          ? Colors.blue[50]
                          : Colors.red[50],
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      dayType == 'weekday' ? '平日' : '休日（土日・祝日）',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: dayType == 'weekday'
                            ? Colors.blue[700]
                            : Colors.red[700],
                      ),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: () => _showWorkHoursDialog(dayType),
                icon: const Icon(Icons.edit, size: 14),
                label: const Text('設定'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.teal),
              ),
            ],
          ),
          // 勤務時間帯表示
          Builder(builder: (context) {
            final wh = _workHours
                .where((w) => w['day_type'] == dayType)
                .toList();
            if (wh.isEmpty) {
              return Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: const Text('未設定',
                    style: TextStyle(color: Colors.grey)),
              );
            }
            final w = wh.first;
            return Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: dayType == 'weekday'
                    ? Colors.blue[50]
                    : Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${w['work_start'].toString().substring(0, 5)} 〜 ${w['work_end'].toString().substring(0, 5)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: dayType == 'weekday'
                      ? Colors.blue[700]
                      : Colors.red[700],
                ),
              ),
            );
          }),
          // 時間帯別必要人数
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('時間帯別必要人数',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey[600])),
              TextButton.icon(
                onPressed: () => _showStaffingSlotDialog(dayType),
                icon: const Icon(Icons.add, size: 14),
                label: const Text('追加'),
                style: TextButton.styleFrom(
                    foregroundColor: Colors.teal),
              ),
            ],
          ),
          ..._staffingSlots
              .where((s) => s['day_type'] == dayType)
              .map((s) => Card(
                    margin: const EdgeInsets.only(bottom: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ListTile(
                      dense: true,
                      title: Text(
                        '${s['slot_start'].toString().substring(0, 5)} 〜 ${s['slot_end'].toString().substring(0, 5)}',
                      ),
                      subtitle:
                          Text('必要人数：${s['min_staff']}名'),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete,
                            size: 18, color: Colors.red),
                        onPressed: () async {
                          await _settingsService
                              .deleteStaffingSlot(s['id']);
                          await _loadSettings();
                        },
                      ),
                    ),
                  )),
          const Divider(height: 32),
        ],
      ],
    );
  }

  Widget _buildBreakRulesTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('休憩ルール',
                style: Theme.of(context).textTheme.titleMedium),
            TextButton.icon(
              onPressed: _showBreakRuleDialog,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('追加'),
              style:
                  TextButton.styleFrom(foregroundColor: Colors.teal),
            ),
          ],
        ),
        const Text(
          '例：6時間以上勤務で45分休憩',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 12),
        if (_breakRules.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.grey[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey[200]!),
            ),
            child: const Text('休憩ルールが設定されていません',
                style: TextStyle(color: Colors.grey),
                textAlign: TextAlign.center),
          )
        else
          ..._breakRules.map((r) {
            final threshold =
                (r['work_hours_threshold'] as num).toDouble();
            final breakMin = r['break_minutes'] as int;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              child: ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.coffee,
                      size: 20, color: Colors.orange[700]),
                ),
                title: Text(
                    '${threshold.toStringAsFixed(0)}時間以上 → $breakMin分休憩'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete,
                      size: 18, color: Colors.red),
                  onPressed: () async {
                    await _settingsService
                        .deleteBreakRule(r['id']);
                    await _loadSettings();
                  },
                ),
              ),
            );
          }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                  final store = m['stores'] as Map<String, dynamic>;
                  return DropdownMenuItem(
                    value: store['id'] as String,
                    child: Text(store['name']),
                  );
                }).toList(),
                onChanged: (v) async {
                  final store = (_stores.firstWhere((m) =>
                      (m['stores'] as Map<String, dynamic>)['id'] ==
                      v)['stores']) as Map<String, dynamic>;
                  setState(() {
                    _selectedStoreId = v;
                    _selectedStoreName = store['name'];
                  });
                  await _loadSettings();
                },
              ),
            ),
          TabBar(
            controller: _tabController,
            labelColor: Colors.teal,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Colors.teal,
            tabs: const [
              Tab(text: '勤務時間帯'),
              Tab(text: '休憩ルール'),
              Tab(text: '店舗情報'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildWorkHoursTab(),
                _buildBreakRulesTab(),
                Center(
                  child: Text(
                    '「$_selectedStoreName」',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}