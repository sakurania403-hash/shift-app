import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/invitation_service.dart';
import '../services/store_service.dart';

class InviteScreen extends StatefulWidget {
  const InviteScreen({super.key});

  @override
  State<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends State<InviteScreen> {
  final _invitationService = InvitationService();
  final _storeService = StoreService();
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _invitations = [];
  String? _selectedStoreId;
  String? _selectedStoreName;
  bool _isLoading = true;

  // 環境に応じてベースURLを切り替え
  String get _baseUrl {
    final uri = Uri.base;
    if (uri.host == 'localhost' || uri.host == '127.0.0.1') {
      return '${uri.scheme}://${uri.host}:${uri.port}';
    }
    return 'https://shift-app.web.app';
  }

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    final stores = await _storeService.getMyStores();
    final adminStores = stores
        .where((m) => m['role'] == 'admin')
        .toList();
    setState(() {
      _stores = adminStores;
      if (adminStores.isNotEmpty) {
        final first =
            adminStores.first['stores'] as Map<String, dynamic>;
        _selectedStoreId = first['id'];
        _selectedStoreName = first['name'];
      }
      _isLoading = false;
    });
    if (_selectedStoreId != null) {
      await _loadInvitations();
    }
  }

  Future<void> _loadInvitations() async {
    if (_selectedStoreId == null) return;
    final result =
        await _invitationService.getInvitations(_selectedStoreId!);
    setState(() => _invitations = result);
  }

  Future<void> _createInvitation() async {
    if (_selectedStoreId == null) return;
    try {
      final token =
          await _invitationService.createInvitation(_selectedStoreId!);
      final url = '$_baseUrl/join?token=$token';
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('招待URLをクリップボードにコピーしました'),
            backgroundColor: Colors.teal,
          ),
        );
      }
      await _loadInvitations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('エラー: $e')),
        );
      }
    }
  }

  String _getInviteUrl(String token) {
    return '$_baseUrl/join?token=$token';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_stores.isEmpty) {
      return const Center(
        child: Text('管理者の店舗がありません'),
      );
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
                  await _loadInvitations();
                },
              ),
            ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.teal[50],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '「$_selectedStoreName」への招待',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 4),
                const Text(
                  '招待URLを発行してスタッフに共有してください。\nURLからアカウント作成すると自動で店舗に参加できます。',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.teal[100],
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '現在の環境：$_baseUrl',
                    style: TextStyle(
                        fontSize: 11, color: Colors.teal[800]),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _invitations.isEmpty
                ? const Center(
                    child: Text('招待URLがありません',
                        style: TextStyle(color: Colors.grey)),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _invitations.length,
                    itemBuilder: (context, index) {
                      final inv = _invitations[index];
                      final expiresAt =
                          DateTime.parse(inv['expires_at']).toLocal();
                      final isExpired =
                          expiresAt.isBefore(DateTime.now());
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.link,
                                      size: 16, color: Colors.teal),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      _getInviteUrl(inv['token']),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black54),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy,
                                        size: 18),
                                    onPressed: () async {
                                      await Clipboard.setData(
                                        ClipboardData(
                                            text: _getInviteUrl(
                                                inv['token'])),
                                      );
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content: Text('コピーしました')),
                                        );
                                      }
                                    },
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text(
                                    '使用回数：${inv['used_count']}回',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    isExpired
                                        ? '期限切れ'
                                        : '有効期限：${expiresAt.month}/${expiresAt.day}まで',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isExpired
                                          ? Colors.red
                                          : Colors.black54,
                                    ),
                                  ),
                                  const Spacer(),
                                  TextButton(
                                    onPressed: () async {
                                      await _invitationService
                                          .deactivateInvitation(
                                              inv['id']);
                                      await _loadInvitations();
                                    },
                                    child: const Text('無効化',
                                        style: TextStyle(
                                            color: Colors.red,
                                            fontSize: 12)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createInvitation,
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_link),
        label: const Text('招待URLを発行'),
      ),
    );
  }
}