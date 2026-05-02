import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const kPersonalColorPalette = [
  Color(0xFF2C7873),
  Color(0xFFE07B39),
  Color(0xFF6C5CE7),
  Color(0xFFE84393),
  Color(0xFF00B894),
  Color(0xFFE17055),
  Color(0xFF0984E3),
  Color(0xFFD63031),
  Color(0xFFFDAB4D),
  Color(0xFF55EFC4),
  Color(0xFF74B9FF),
  Color(0xFFB2BEC3),
];

String _colorToHex(Color c) =>
    '#${c.red.toRadixString(16).padLeft(2, '0')}'
    '${c.green.toRadixString(16).padLeft(2, '0')}'
    '${c.blue.toRadixString(16).padLeft(2, '0')}';

Color _hexToColor(String hex) {
  final h = hex.replaceAll('#', '');
  if (h.length != 6) return const Color(0xFF2C7873);
  return Color(int.parse('FF$h', radix: 16));
}

class PersonalStoreScreen extends StatefulWidget {
  const PersonalStoreScreen({super.key});

  @override
  State<PersonalStoreScreen> createState() => _PersonalStoreScreenState();
}

class _PersonalStoreScreenState extends State<PersonalStoreScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final data = await _supabase
          .from('personal_stores')
          .select()
          .eq('user_id', userId)
          .order('sort_order');
      if (mounted) {
        setState(() {
          _stores = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (e) {
      debugPrint('loadStores error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showStoreDialog({Map<String, dynamic>? existing}) async {
    final nameController =
        TextEditingController(text: existing?['name'] ?? '');
    Color selectedColor = existing != null
        ? _hexToColor(existing['color'] as String? ?? '#2C7873')
        : kPersonalColorPalette[_stores.length % kPersonalColorPalette.length];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(existing == null ? '職場を追加' : '職場を編集'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '職場名',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.store),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('カラー',
                  style: TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kPersonalColorPalette.map((color) {
                  final isSelected = selectedColor.value == color.value;
                  return GestureDetector(
                    onTap: () =>
                        setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected
                            ? Border.all(color: Colors.white, width: 2.5)
                            : null,
                        boxShadow: isSelected
                            ? [BoxShadow(
                                color: color.withOpacity(0.6),
                                blurRadius: 6,
                                spreadRadius: 1)]
                            : null,
                      ),
                      child: isSelected
                          ? const Icon(Icons.check,
                              color: Colors.white, size: 16)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            if (existing != null)
              TextButton(
                onPressed: () async {
                  await _deleteStore(existing['id']);
                  if (mounted) Navigator.pop(context);
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
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('職場名を入力してください')),
                  );
                  return;
                }
                await _saveStore(
                  id: existing?['id'],
                  name: nameController.text.trim(),
                  color: selectedColor,
                );
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal),
              child: const Text('保存',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveStore({
    String? id,
    required String name,
    required Color color,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final data = {
      'user_id':    userId,
      'name':       name,
      'color':      _colorToHex(color),
      'sort_order': id == null ? _stores.length : null,
    };
    if (id == null) {
      await _supabase.from('personal_stores').insert(data);
    } else {
      data.remove('sort_order');
      await _supabase
          .from('personal_stores')
          .update(data)
          .eq('id', id);
    }
    await _loadStores();
  }

  Future<void> _deleteStore(String id) async {
    await _supabase.from('personal_stores').delete().eq('id', id);
    await _loadStores();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        title: const Text('職場管理'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2C7873),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF2C7873)),
            onPressed: () => _showStoreDialog(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _stores.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.store_outlined,
                          size: 48, color: Colors.grey[400]),
                      const SizedBox(height: 8),
                      Text('職場が登録されていません',
                          style: TextStyle(color: Colors.grey[500])),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: () => _showStoreDialog(),
                        icon: const Icon(Icons.add),
                        label: const Text('職場を追加'),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _stores.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _stores[i];
                    final color =
                        _hexToColor(s['color'] as String? ?? '#2C7873');
                    return Card(
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        leading: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.store,
                              color: color, size: 22),
                        ),
                        title: Text(s['name'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold)),
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_outlined,
                              color: Colors.grey),
                          onPressed: () =>
                              _showStoreDialog(existing: s),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: _stores.isNotEmpty
          ? FloatingActionButton(
              onPressed: () => _showStoreDialog(),
              backgroundColor: Colors.teal,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}