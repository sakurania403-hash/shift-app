import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftService {
  final _supabase = Supabase.instance.client;

  // 確定シフトを作成・更新（通常スタッフ）
  Future<void> upsertShift({
    required String storeId,
    required String? userId,
    required DateTime date,
    required String startTime,
    String? endTime,
    bool isLast = false,
    String staffType = 'regular',
    String? tempLabel,
  }) async {
    await _supabase.from('shifts').upsert({
      'store_id': storeId,
      'user_id': userId,
      'date': date.toIso8601String().substring(0, 10),
      'start_time': startTime,
      'end_time': endTime,
      'is_last': isLast,
      'status': 'confirmed',
      'staff_type': staffType,
      'temp_label': tempLabel,
    }, onConflict: 'store_id, user_id, date');
  }

  // 臨時スタッフを追加
  Future<void> upsertTempShift({
    required String storeId,
    required DateTime date,
    required String tempLabel,
    required String startTime,
    String? endTime,
    bool isLast = false,
  }) async {
    await _supabase.from('shifts').insert({
      'store_id': storeId,
      'user_id': null,
      'date': date.toIso8601String().substring(0, 10),
      'start_time': startTime,
      'end_time': endTime,
      'is_last': isLast,
      'status': 'confirmed',
      'staff_type': 'temp',
      'temp_label': tempLabel,
    });
  }

  // 臨時スタッフを更新
  Future<void> updateTempShift({
    required String shiftId,
    required String tempLabel,
    required String startTime,
    String? endTime,
    bool isLast = false,
  }) async {
    await _supabase.from('shifts').update({
      'temp_label': tempLabel,
      'start_time': startTime,
      'end_time': endTime,
      'is_last': isLast,
    }).eq('id', shiftId);
  }

  // 臨時スタッフを削除
  Future<void> deleteTempShift(String shiftId) async {
    await _supabase.from('shifts').delete().eq('id', shiftId);
  }

  // 確定シフトを削除（通常スタッフ）
  Future<void> deleteShift({
    required String storeId,
    required String? userId,
    required DateTime date,
  }) async {
    await _supabase
        .from('shifts')
        .delete()
        .eq('store_id', storeId)
        .eq('date', date.toIso8601String().substring(0, 10))
        .eq('user_id', userId ?? '');
  }

  // 店舗の確定シフト一覧を取得
  Future<List<Map<String, dynamic>>> getConfirmedShifts({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase
        .from('shifts')
        .select('*, user_profiles(id, name)')
        .eq('store_id', storeId)
        .eq('status', 'confirmed')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10))
        .order('date');
    return List<Map<String, dynamic>>.from(result);
  }

  // 自分の確定シフトを取得（スタッフ用）
  Future<List<Map<String, dynamic>>> getMyConfirmedShifts({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final result = await _supabase
        .from('shifts')
        .select('*, user_profiles(id, name)')
        .eq('store_id', storeId)
        .eq('user_id', userId)
        .eq('status', 'confirmed')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10))
        .order('date');
    return List<Map<String, dynamic>>.from(result);
  }

  // 店舗の全メンバーを取得（sort_order順）
  Future<List<Map<String, dynamic>>> getStoreMembers(String storeId) async {
    final result = await _supabase
        .from('store_memberships')
        .select('user_id, role, sort_order, user_profiles(id, name)')
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
}