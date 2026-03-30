import 'package:supabase_flutter/supabase_flutter.dart';

class AdminShiftService {
  final _supabase = Supabase.instance.client;

  // 店舗のスタッフ一覧を取得（管理者を除く）
  Future<List<Map<String, dynamic>>> getStoreStaff(String storeId) async {
    final result = await _supabase
        .from('store_memberships')
        .select('user_id, role, hourly_wage, user_profiles(id, name, email)')
        .eq('store_id', storeId)
        .eq('role', 'staff')
        .order('created_at');
    return List<Map<String, dynamic>>.from(result);
  }

  // 全スタッフ（管理者含む）を取得
  Future<List<Map<String, dynamic>>> getAllStoreMembers(
      String storeId) async {
    final result = await _supabase
        .from('store_memberships')
        .select('user_id, role, hourly_wage, user_profiles(id, name, email)')
        .eq('store_id', storeId)
        .order('created_at');
    return List<Map<String, dynamic>>.from(result);
  }

  // 募集に対する全スタッフの提出済み希望シフトを取得
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

  // 募集に対する全スタッフの提出済み希望休を取得
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
}