import 'package:supabase_flutter/supabase_flutter.dart';

class RecruitmentService {
  final _supabase = Supabase.instance.client;

  // シフト募集を作成
  Future<Map<String, dynamic>> createRecruitment({
    required String storeId,
    required String title,
    required DateTime workStart,
    required DateTime workEnd,
    required DateTime requestStart,
    required DateTime requestEnd,
  }) async {
    final result = await _supabase
        .from('shift_recruitments')
        .insert({
          'store_id': storeId,
          'title': title,
          'work_start': workStart.toIso8601String().substring(0, 10),
          'work_end': workEnd.toIso8601String().substring(0, 10),
          'request_start': requestStart.toIso8601String().substring(0, 10),
          'request_end': requestEnd.toIso8601String().substring(0, 10),
          'status': 'open',
        })
        .select()
        .single();

    return result;
  }

  // 店舗のシフト募集一覧を取得
  Future<List<Map<String, dynamic>>> getRecruitments(String storeId) async {
    final result = await _supabase
        .from('shift_recruitments')
        .select()
        .eq('store_id', storeId)
        .order('work_start', ascending: false);

    return List<Map<String, dynamic>>.from(result);
  }

  // 募集を締め切る
  Future<void> closeRecruitment(String recruitmentId) async {
    await _supabase
        .from('shift_recruitments')
        .update({'status': 'closed'})
        .eq('id', recruitmentId);
  }

  // 募集を再開（締切 → 募集中に戻す）
  Future<void> reopenRecruitment(String recruitmentId) async {
    await _supabase
        .from('shift_recruitments')
        .update({'status': 'open'})
        .eq('id', recruitmentId);
  }

  // 募集を削除
  Future<void> deleteRecruitment(String recruitmentId) async {
    await _supabase
        .from('shift_recruitments')
        .delete()
        .eq('id', recruitmentId);
  }
}