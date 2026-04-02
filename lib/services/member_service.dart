import 'package:supabase_flutter/supabase_flutter.dart';

class MemberService {
  final _supabase = Supabase.instance.client;

  // 店舗のメンバー一覧をsort_order順で取得
  Future<List<Map<String, dynamic>>> getMembers(String storeId) async {
    final result = await _supabase
        .from('store_memberships')
        .select('id, user_id, role, hourly_wage, sort_order, user_profiles(id, name, email)')
        .eq('store_id', storeId)
        .order('sort_order', ascending: true);

    final members = List<Map<String, dynamic>>.from(result);
    members.sort((a, b) {
      final aOrder = (a['sort_order'] as num?)?.toInt() ?? 9999;
      final bOrder = (b['sort_order'] as num?)?.toInt() ?? 9999;
      return aOrder.compareTo(bOrder);
    });
    return members;
  }

  // メンバー情報を更新（名前・時給）
  Future<void> updateMember({
    required String membershipId,
    required String name,
    required int hourlyWage,
  }) async {
    final membership = await _supabase
        .from('store_memberships')
        .select('user_id')
        .eq('id', membershipId)
        .single();
    final userId = membership['user_id'] as String;
    await _supabase
        .from('user_profiles')
        .update({'name': name})
        .eq('id', userId);
    await _supabase
        .from('store_memberships')
        .update({'hourly_wage': hourlyWage})
        .eq('id', membershipId);
  }

  // メンバーを削除（店舗から除名）
  Future<void> removeMember(String membershipId) async {
    await _supabase
        .from('store_memberships')
        .delete()
        .eq('id', membershipId);
  }

  // スタッフの並び順を一括更新
  Future<void> updateMemberOrder(List<Map<String, dynamic>> members) async {
    for (int i = 0; i < members.length; i++) {
      await _supabase
          .from('store_memberships')
          .update({'sort_order': i + 1})
          .eq('id', members[i]['id']);
    }
  }

  // ヘルプラベル一覧をsort_order順で取得
  Future<List<Map<String, dynamic>>> getTempLabels(String storeId) async {
  final result = await _supabase
      .from('store_temp_labels')
      .select()
      .eq('store_id', storeId)
      .order('sort_order', ascending: true);

  final labels = List<Map<String, dynamic>>.from(result);
  labels.sort((a, b) {
    final aOrder = (a['sort_order'] as num?)?.toInt() ?? 9999;
    final bOrder = (b['sort_order'] as num?)?.toInt() ?? 9999;
    return aOrder.compareTo(bOrder);
  });
  return labels;
}

  // ヘルプラベルを追加
  Future<void> addTempLabel({
    required String storeId,
    required String label,
  }) async {
    final existing = await getTempLabels(storeId);
    final maxOrder = existing.isEmpty
        ? 0
        : existing.map((e) => e['sort_order'] as int).reduce((a, b) => a > b ? a : b);
    await _supabase.from('store_temp_labels').insert({
      'store_id': storeId,
      'label': label,
      'sort_order': maxOrder + 1,
    });
  }

  // ヘルプラベルを削除
  Future<void> removeTempLabel(String labelId) async {
    await _supabase
        .from('store_temp_labels')
        .delete()
        .eq('id', labelId);
  }

  // ヘルプラベルの並び順を一括更新
  Future<void> updateTempLabelOrder(List<Map<String, dynamic>> labels) async {
    for (int i = 0; i < labels.length; i++) {
      await _supabase
          .from('store_temp_labels')
          .update({'sort_order': i + 1})
          .eq('id', labels[i]['id']);
    }
  }
}