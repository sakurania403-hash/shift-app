import 'package:supabase_flutter/supabase_flutter.dart';

class StoreService {
  final _supabase = Supabase.instance.client;

  // 店舗作成
  Future<Map<String, dynamic>> createStore({
    required String name,
  }) async {
    final userId = _supabase.auth.currentUser!.id;

    final store = await _supabase
        .from('stores')
        .insert({
          'name': name,
          'owner_id': userId,
        })
        .select()
        .single();

    // 作成者を管理者として所属登録
    await _supabase.from('store_memberships').insert({
      'user_id': userId,
      'store_id': store['id'],
      'role': 'admin',
      'hourly_wage': 1000,
      'closing_day': 25,
      'payday': 10,
      'payday_month_offset': 1,
    });

    return store;
  }

  // 自分が所属する店舗一覧を取得
  Future<List<Map<String, dynamic>>> getMyStores() async {
    final userId = _supabase.auth.currentUser!.id;

    final memberships = await _supabase
        .from('store_memberships')
        .select('store_id, role, stores(id, name)')
        .eq('user_id', userId);

    // LinkedMap を Map<String, dynamic> に変換
    return memberships.map((m) {
      final raw = Map<String, dynamic>.from(m as Map);
      if (raw['stores'] != null) {
        raw['stores'] = Map<String, dynamic>.from(raw['stores'] as Map);
      }
      return raw;
    }).toList();
  }

  // 自分の所属情報を取得
  Future<Map<String, dynamic>?> getMembership(String storeId) async {
    final userId = _supabase.auth.currentUser!.id;

    final result = await _supabase
        .from('store_memberships')
        .select()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .maybeSingle();

    return result;
  }
}