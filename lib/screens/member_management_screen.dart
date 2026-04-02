import 'package:flutter/material.dart';
import '../services/member_service.dart';
import '../services/store_service.dart';

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen>
    with SingleTickerProviderStateMixin {
  final _memberService = MemberService();
  final _storeService = StoreService();
  late TabController _tabController;

  List<Map<String, dynamic>> _stores = [];
  String? _selectedStoreId;
  String? _selectedStoreName;
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _tempLabels = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStores();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    final stores = await _storeService.getMyStores();
    final adminStores = stores.where((m) => m['role'] == 'admin').toList();
    if (adminStores.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    final first = Map<String, dynamic>.from(adminStores.first['stores'] as Map);
    setState(() {
      _stores = adminStores;
      _selectedStoreId = first['id'];
      _selectedStoreName = first['name'];
    });
    await _loadData();
  }

  Future<void> _loadData() async {
    if (_selectedStoreId == null) return;
    setState(() => _isLoading = true);
    final members = await _memberService.getMembers(_selectedStoreId!);
    final tempLabels = await _memberService.getTempLabels(_selectedStoreId!);
    setState(() {
      _members = members;
      _tempLabels = tempLabels;
      _isLoading = false;
    });
  }

  // メンバー編集ダイアログ
  Future<void> _showEditMemberDialog(Map<String, dynamic> member) async {
    final profile = Map<String, dynamic>.from(member['user_profiles'] as Map);
    final nameController = TextEditingController(text: profile['name'] ?? '');
    final wageController = TextEditingController(
        text: (member['hourly_wage'] ?? 0).toString());

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メンバー情報を編集'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '名前',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: wageController,
              decoration: const InputDecoration(
                labelText: '時給（円）',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _memberService.updateMember(
                membershipId: member['id'],
                name: nameController.text.trim(),
                hourlyWage: int.tryParse(wageController.text) ?? 0,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadData();
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

  // メンバー削除確認ダイアログ
  Future<void> _showRemoveMemberDialog(Map<String, dynamic> member) async {
    final profile = Map<String, dynamic>.from(member['user_profiles'] as Map);
    final name = profile['name'] ?? '';
    final isAdmin = member['role'] == 'admin';
    if (isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('管理者は削除できません')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('メンバーを削除'),
        content: Text('「$name」を店舗から削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _memberService.removeMember(member['id']);
      await _loadData();
    }
  }

  // ヘルプラベル追加ダイアログ
  Future<void> _showAddLabelDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ヘルプラベルを追加'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'ラベル名（例：タイミー5、南星花）',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () async {
              final label = controller.text.trim();
              if (label.isEmpty) return;
              await _memberService.addTempLabel(
                storeId: _selectedStoreId!,
                label: label,
              );
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadData();
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_stores.isEmpty) {
      return const Center(child: Text('管理者の店舗がありません'));
    }

    return Scaffold(
      body: Column(
        children: [
          // 店舗選択
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
                  final store = Map<String, dynamic>.from(m['stores'] as Map);
                  return DropdownMenuItem(
                    value: store['id'] as String,
                    child: Text(store['name']),
                  );
                }).toList(),
                onChanged: (v) async {
                  final store = Map<String, dynamic>.from(
                      (_stores.firstWhere((m) =>
                          (Map<String, dynamic>.from(m['stores'] as Map))['id'] == v)['stores']) as Map);
                  setState(() {
                    _selectedStoreId = v;
                    _selectedStoreName = store['name'];
                  });
                  await _loadData();
                },
              ),
            ),
          // タブ
          TabBar(
            controller: _tabController,
            labelColor: Colors.teal,
            indicatorColor: Colors.teal,
            tabs: const [
              Tab(text: 'スタッフ'),
              Tab(text: 'ヘルプ・タイミー'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStaffTab(),
                _buildTempLabelTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // スタッフタブ
  Widget _buildStaffTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.teal[50],
          width: double.infinity,
          child: const Text(
            '長押しして行をドラッグすると並び順を変更できます（管理者は常に先頭）',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            itemCount: _members.length,
            onReorder: (oldIndex, newIndex) async {
              // 管理者行は動かせない
              if (_members[oldIndex]['role'] == 'admin') return;
              if (newIndex > 0 && _members[newIndex - 1]['role'] == 'admin' &&
                  oldIndex > newIndex) return;

              setState(() {
                if (newIndex > oldIndex) newIndex--;
                // 管理者より上には移動させない
                final adminCount =
                    _members.where((m) => m['role'] == 'admin').length;
                if (newIndex < adminCount) newIndex = adminCount;
                final item = _members.removeAt(oldIndex);
                _members.insert(newIndex, item);
              });
              await _memberService.updateMemberOrder(_members);
            },
            itemBuilder: (context, index) {
              final member = _members[index];
              final profile =
                  Map<String, dynamic>.from(member['user_profiles'] as Map);
              final name = profile['name'] ?? '';
              final email = profile['email'] ?? '';
              final role = member['role'] as String;
              final wage = member['hourly_wage'] ?? 0;
              final isAdmin = role == 'admin';

              return ListTile(
                key: ValueKey(member['id']),
                leading: CircleAvatar(
                  backgroundColor:
                      isAdmin ? Colors.teal : Colors.teal[100],
                  child: Text(
                    name.isNotEmpty ? name[0] : '?',
                    style: TextStyle(
                      color: isAdmin ? Colors.white : Colors.teal[800],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                title: Row(
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(width: 8),
                    if (isAdmin)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.teal[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('管理者',
                            style: TextStyle(
                                fontSize: 10, color: Colors.teal[800])),
                      ),
                  ],
                ),
                subtitle: Text('$email　時給：¥$wage',
                    style: const TextStyle(fontSize: 12)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => _showEditMemberDialog(member),
                    ),
                    if (!isAdmin)
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        onPressed: () => _showRemoveMemberDialog(member),
                      ),
                    const Icon(Icons.drag_handle, color: Colors.grey),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ヘルプ・タイミータブ
  Widget _buildTempLabelTab() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.orange[50],
          width: double.infinity,
          child: const Text(
            '長押しして行をドラッグすると並び順を変更できます',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        Expanded(
          child: _tempLabels.isEmpty
              ? const Center(
                  child: Text('ヘルプラベルがありません',
                      style: TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
                  itemCount: _tempLabels.length,
                  onReorder: (oldIndex, newIndex) async {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = _tempLabels.removeAt(oldIndex);
                      _tempLabels.insert(newIndex, item);
                    });
                    await _memberService.updateTempLabelOrder(_tempLabels);
                  },
                  itemBuilder: (context, index) {
                    final label = _tempLabels[index];
                    return ListTile(
                      key: ValueKey(label['id']),
                      leading: const Icon(Icons.label_outline,
                          color: Colors.orange),
                      title: Text(label['label'] ?? ''),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                size: 18, color: Colors.red),
                            onPressed: () async {
                              await _memberService
                                  .removeTempLabel(label['id']);
                              await _loadData();
                            },
                          ),
                          const Icon(Icons.drag_handle, color: Colors.grey),
                        ],
                      ),
                    );
                  },
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAddLabelDialog,
              icon: const Icon(Icons.add),
              label: const Text('ヘルプラベルを追加'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}