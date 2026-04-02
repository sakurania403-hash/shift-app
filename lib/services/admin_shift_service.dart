import 'package:supabase_flutter/supabase_flutter.dart';
 
class AdminShiftService {
  final _supabase = Supabase.instance.client;
 
  // 店舗の全メンバーを取得（管理者を先頭に）
  Future<List<Map<String, dynamic>>> getStoreStaff(String storeId) async {
  final result = await _supabase
      .from('store_memberships')
      .select('user_id, role, hourly_wage, sort_order, user_profiles(id, name, email)')
      .eq('store_id', storeId)
      .order('sort_order', ascending: true);

  final members = List<Map<String, dynamic>>.from(result);

  // Dart側でも念のためソート
  members.sort((a, b) {
    final aOrder = (a['sort_order'] as num?)?.toInt() ?? 9999;
    final bOrder = (b['sort_order'] as num?)?.toInt() ?? 9999;
    return aOrder.compareTo(bOrder);
  });

  return members;
}
 
  // 募集に対する全メンバーの提出済み希望シフトを取得
  Future<List<Map<String, dynamic>>> getAllShiftRequests({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase
        .from('shift_requests')
        .select('*, user_profiles(id, name)')
        .eq('store_id', storeId)
        .eq('status', 'submitted')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10))
        .order('date');
    return List<Map<String, dynamic>>.from(result);
  }
 
  // 募集に対する全メンバーの提出済み希望休を取得
  Future<List<Map<String, dynamic>>> getAllDayOffRequests({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final result = await _supabase
        .from('day_off_requests')
        .select('*, user_profiles(id, name)')
        .eq('store_id', storeId)
        .eq('status_submit', 'submitted')
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10))
        .order('date');
    return List<Map<String, dynamic>>.from(result);
  }
 
  // 提出状況を取得
  Future<List<Map<String, dynamic>>> getSubmissions(
      String recruitmentId) async {
    final result = await _supabase
        .from('shift_submissions')
        .select('*, user_profiles(id, name)')
        .eq('recruitment_id', recruitmentId);
    return List<Map<String, dynamic>>.from(result);
  }
 
  // 確定済みシフトを取得
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
}