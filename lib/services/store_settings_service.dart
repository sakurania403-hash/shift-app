import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';

class StoreSettingsService {
  final _supabase = Supabase.instance.client;
  static Map<String, String>? _holidayCache;

  // 日本の祝日を取得（キャッシュあり）
  static Future<Map<String, String>> getJapaneseHolidays() async {
    if (_holidayCache != null) return _holidayCache!;
    try {
      final response = await http.get(
        Uri.parse('https://holidays-jp.github.io/api/v1/date.json'),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        _holidayCache = data.map((k, v) => MapEntry(k, v.toString()));
        return _holidayCache!;
      }
    } catch (e) {
      debugPrint('祝日取得エラー: $e');
    }
    return {};
  }

  // 指定日が休日かどうか判定（土日・祝日）
  static Future<bool> isHoliday(
      DateTime date, Map<String, String> holidays) async {
    final weekday = date.weekday;
    if (weekday == DateTime.saturday || weekday == DateTime.sunday) {
      return true;
    }
    final dateStr = date.toIso8601String().substring(0, 10);
    return holidays.containsKey(dateStr);
  }

  // 勤務時間帯を取得
  Future<List<Map<String, dynamic>>> getWorkHours(String storeId) async {
    final result = await _supabase
        .from('store_work_hours')
        .select()
        .eq('store_id', storeId)
        .order('day_type');
    return List<Map<String, dynamic>>.from(result);
  }

  // 勤務時間帯を保存
  Future<void> upsertWorkHours({
    required String storeId,
    required String dayType,
    required String workStart,
    required String workEnd,
  }) async {
    await _supabase.from('store_work_hours').upsert({
      'store_id': storeId,
      'day_type': dayType,
      'work_start': workStart,
      'work_end': workEnd,
    }, onConflict: 'store_id, day_type');
  }

  // 時間帯別必要人数を取得
  Future<List<Map<String, dynamic>>> getStaffingSlots(
      String storeId) async {
    final result = await _supabase
        .from('store_staffing_slots')
        .select()
        .eq('store_id', storeId)
        .order('day_type')
        .order('slot_start');
    return List<Map<String, dynamic>>.from(result);
  }

  // 時間帯別必要人数を追加
  Future<void> addStaffingSlot({
    required String storeId,
    required String dayType,
    required String slotStart,
    required String slotEnd,
    required int minStaff,
  }) async {
    await _supabase.from('store_staffing_slots').insert({
      'store_id': storeId,
      'day_type': dayType,
      'slot_start': slotStart,
      'slot_end': slotEnd,
      'min_staff': minStaff,
    });
  }

  // 時間帯別必要人数を削除
  Future<void> deleteStaffingSlot(String slotId) async {
    await _supabase
        .from('store_staffing_slots')
        .delete()
        .eq('id', slotId);
  }

  // 休憩ルールを取得
  Future<List<Map<String, dynamic>>> getBreakRules(String storeId) async {
    final result = await _supabase
        .from('store_break_rules')
        .select()
        .eq('store_id', storeId)
        .order('work_hours_threshold');
    return List<Map<String, dynamic>>.from(result);
  }

  // 休憩ルールを追加
  Future<void> addBreakRule({
    required String storeId,
    required double workHoursThreshold,
    required int breakMinutes,
  }) async {
    await _supabase.from('store_break_rules').insert({
      'store_id': storeId,
      'work_hours_threshold': workHoursThreshold,
      'break_minutes': breakMinutes,
    });
  }

  // 休憩ルールを削除
  Future<void> deleteBreakRule(String ruleId) async {
    await _supabase
        .from('store_break_rules')
        .delete()
        .eq('id', ruleId);
  }

  // 休業日を取得
  Future<List<Map<String, dynamic>>> getShiftHolidays(
      String recruitmentId) async {
    final result = await _supabase
        .from('shift_holidays')
        .select()
        .eq('recruitment_id', recruitmentId)
        .order('date');
    return List<Map<String, dynamic>>.from(result);
  }

  // 休業日を追加
  Future<void> addShiftHoliday({
    required String recruitmentId,
    required String storeId,
    required DateTime date,
  }) async {
    await _supabase.from('shift_holidays').upsert({
      'recruitment_id': recruitmentId,
      'store_id': storeId,
      'date': date.toIso8601String().substring(0, 10),
    }, onConflict: 'recruitment_id, date');
  }

  // 休業日を削除
  Future<void> deleteShiftHoliday(String holidayId) async {
    await _supabase
        .from('shift_holidays')
        .delete()
        .eq('id', holidayId);
  }

  // 特別期間を取得
  Future<List<Map<String, dynamic>>> getSpecialPeriods(
      String recruitmentId) async {
    final result = await _supabase
        .from('shift_special_periods')
        .select()
        .eq('recruitment_id', recruitmentId)
        .order('start_date');
    return List<Map<String, dynamic>>.from(result);
  }

  // 特別期間を追加
  Future<void> addSpecialPeriod({
    required String recruitmentId,
    required String storeId,
    required String label,
    required DateTime startDate,
    required DateTime endDate,
    required int minStaffOverride,
  }) async {
    await _supabase.from('shift_special_periods').insert({
      'recruitment_id': recruitmentId,
      'store_id': storeId,
      'label': label,
      'start_date': startDate.toIso8601String().substring(0, 10),
      'end_date': endDate.toIso8601String().substring(0, 10),
      'min_staff_override': minStaffOverride,
    });
  }

  // 特別期間を削除
  Future<void> deleteSpecialPeriod(String periodId) async {
    await _supabase
        .from('shift_special_periods')
        .delete()
        .eq('id', periodId);
  }

  // 実働時間から休憩時間を計算
  int calcBreakMinutes(
      List<Map<String, dynamic>> breakRules, double workHours) {
    int breakMinutes = 0;
    for (var rule in breakRules) {
      if (workHours >=
          (rule['work_hours_threshold'] as num).toDouble()) {
        breakMinutes = rule['break_minutes'] as int;
      }
    }
    return breakMinutes;
  }
}