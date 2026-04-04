import 'package:supabase_flutter/supabase_flutter.dart';

class ShiftRequestService {
  final _supabase = Supabase.instance.client;

  Future<void> saveShiftRequest({
    required String storeId,
    required String recruitmentId,
    required DateTime date,
    String? preferredStart,
    String? preferredEnd,
    bool isDayOff = false,
    bool isLast = false,
    String? note,
    // 既に提出済みかどうか（提出済みの場合はINSERT時からsubmittedにする）
    bool alreadySubmitted = false,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final dateStr = date.toIso8601String().substring(0, 10);

    // 提出済みなら新規レコードも即submittedにする
    final shiftStatus = alreadySubmitted ? 'submitted' : 'draft';
    final dayOffStatus = alreadySubmitted ? 'submitted' : 'draft';

    if (isDayOff) {
      // 既存の shift_request を削除
      await _supabase
          .from('shift_requests')
          .delete()
          .eq('user_id', userId)
          .eq('store_id', storeId)
          .eq('date', dateStr);

      // day_off_requests は DELETE → INSERT
      await _supabase
          .from('day_off_requests')
          .delete()
          .eq('user_id', userId)
          .eq('store_id', storeId)
          .eq('date', dateStr);

      await _supabase.from('day_off_requests').insert({
        'user_id': userId,
        'store_id': storeId,
        'date': dateStr,
        'status': 'pending',
        'status_submit': dayOffStatus,
      });
    } else {
      // 既存の day_off_request を削除
      await _supabase
          .from('day_off_requests')
          .delete()
          .eq('user_id', userId)
          .eq('store_id', storeId)
          .eq('date', dateStr);

      // shift_requests は DELETE → INSERT
      await _supabase
          .from('shift_requests')
          .delete()
          .eq('user_id', userId)
          .eq('store_id', storeId)
          .eq('date', dateStr);

      await _supabase.from('shift_requests').insert({
        'user_id': userId,
        'store_id': storeId,
        'date': dateStr,
        'preferred_start': preferredStart,
        'preferred_end': preferredEnd,
        'is_last': isLast,
        'note': note,
        'status': shiftStatus,
      });
    }
  }

  Future<void> submitShiftRequests({
    required String storeId,
    required String recruitmentId,
    required DateTime from,
    required DateTime to,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final fromStr = from.toIso8601String().substring(0, 10);
    final toStr = to.toIso8601String().substring(0, 10);

    await _supabase
        .from('shift_requests')
        .update({'status': 'submitted'})
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .gte('date', fromStr)
        .lte('date', toStr);

    await _supabase
        .from('day_off_requests')
        .update({'status_submit': 'submitted'})
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .gte('date', fromStr)
        .lte('date', toStr);

    await _supabase.from('shift_submissions').upsert({
      'recruitment_id': recruitmentId,
      'user_id': userId,
      'store_id': storeId,
    }, onConflict: 'recruitment_id, user_id');
  }

  Future<bool> isSubmitted({required String recruitmentId}) async {
    final userId = _supabase.auth.currentUser!.id;
    final result = await _supabase
        .from('shift_submissions')
        .select()
        .eq('recruitment_id', recruitmentId)
        .eq('user_id', userId)
        .maybeSingle();
    return result != null;
  }

  Future<List<Map<String, dynamic>>> getMyShiftRequests({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final result = await _supabase
        .from('shift_requests')
        .select()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10));
    return List<Map<String, dynamic>>.from(result);
  }

  Future<List<Map<String, dynamic>>> getMyDayOffRequests({
    required String storeId,
    required DateTime from,
    required DateTime to,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final result = await _supabase
        .from('day_off_requests')
        .select()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .gte('date', from.toIso8601String().substring(0, 10))
        .lte('date', to.toIso8601String().substring(0, 10));
    return List<Map<String, dynamic>>.from(result);
  }

  Future<void> deleteShiftRequest({
    required String storeId,
    required DateTime date,
  }) async {
    final userId = _supabase.auth.currentUser!.id;
    final dateStr = date.toIso8601String().substring(0, 10);

    await _supabase
        .from('shift_requests')
        .delete()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .eq('date', dateStr);

    await _supabase
        .from('day_off_requests')
        .delete()
        .eq('user_id', userId)
        .eq('store_id', storeId)
        .eq('date', dateStr);
  }
}