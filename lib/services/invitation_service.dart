import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InvitationService {
  final _supabase = Supabase.instance.client;

  // 招待トークンを作成
  Future<String> createInvitation(String storeId) async {
    final result = await _supabase
        .from('store_invitations')
        .insert({
          'store_id': storeId,
          'created_by': _supabase.auth.currentUser!.id,
        })
        .select('token')
        .single();

    return result['token'] as String;
  }

  // トークンから招待情報を取得（認証不要）
  Future<Map<String, dynamic>?> getInvitationByToken(String token) async {
    try {
      // 招待情報を取得
      final invitation = await _supabase
          .from('store_invitations')
          .select()
          .eq('token', token)
          .eq('is_active', true)
          .maybeSingle();

      if (invitation == null) return null;

      // 有効期限チェック
      final expiresAt = DateTime.parse(invitation['expires_at']);
      if (expiresAt.isBefore(DateTime.now())) return null;

      // 店舗情報を取得（postgrestのRPC経由で取得）
      final storeId = invitation['store_id'] as String;
      final stores = await _supabase
          .from('stores')
          .select('id, name')
          .eq('id', storeId);

      Map<String, dynamic>? store;
      if (stores.isNotEmpty) {
        store = Map<String, dynamic>.from(stores.first);
      }

      return {
        ...invitation,
        'stores': store ?? {'id': storeId, 'name': '店舗'},
      };
    } catch (e) {
      debugPrint('getInvitationByToken error: $e');
      return null;
    }
  }

  // 招待を使って店舗に参加
  Future<void> joinStore({
    required String token,
    required String storeId,
  }) async {
    final userId = _supabase.auth.currentUser!.id;

    // すでに所属していないか確認
    final existing = await _supabase
        .from('store_memberships')
        .select()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .maybeSingle();

    if (existing != null) return;

    // スタッフとして所属登録
    await _supabase.from('store_memberships').insert({
      'user_id': userId,
      'store_id': storeId,
      'role': 'staff',
      'hourly_wage': 1000,
      'closing_day': 25,
      'payday': 10,
      'payday_month_offset': 1,
    });

    // 使用回数を更新
    await _supabase.rpc('increment_invitation_used_count',
        params: {'invitation_token': token});
  }

  // 店舗の招待一覧を取得
  Future<List<Map<String, dynamic>>> getInvitations(String storeId) async {
    final result = await _supabase
        .from('store_invitations')
        .select()
        .eq('store_id', storeId)
        .eq('is_active', true)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  // 招待を無効化
  Future<void> deactivateInvitation(String invitationId) async {
    await _supabase
        .from('store_invitations')
        .update({'is_active': false}).eq('id', invitationId);
  }
}