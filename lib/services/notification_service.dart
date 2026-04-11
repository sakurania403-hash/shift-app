import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationItem {
  final String id;
  final String storeId;
  final String type;
  final String title;
  final String body;
  final bool isRead;
  final String? relatedId;
  final DateTime createdAt;

  NotificationItem({
    required this.id,
    required this.storeId,
    required this.type,
    required this.title,
    required this.body,
    required this.isRead,
    this.relatedId,
    required this.createdAt,
  });

  factory NotificationItem.fromMap(Map<String, dynamic> map) {
    return NotificationItem(
      id: map['id'] as String,
      storeId: map['store_id'] as String,
      type: map['type'] as String,
      title: map['title'] as String,
      body: map['body'] as String,
      isRead: map['is_read'] as bool,
      relatedId: map['related_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}

class NotificationService {
  final _supabase = Supabase.instance.client;

  // 未読通知数を取得（ポーリング用）
  Future<int> getUnreadCount() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      final response = await _supabase
          .from('notifications')
          .select('id')
          .eq('recipient_user_id', userId)
          .eq('is_read', false);
      return (response as List).length;
    } catch (_) {
      return 0;
    }
  }

  // 通知一覧を取得（最新50件）
  Future<List<NotificationItem>> getNotifications() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return [];
    try {
      final response = await _supabase
          .from('notifications')
          .select()
          .eq('recipient_user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      return (response as List)
          .map((e) => NotificationItem.fromMap(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // 全通知を既読化
  Future<void> markAllAsRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('recipient_user_id', userId)
          .eq('is_read', false);
    } catch (_) {}
  }

  // 個別既読化
  Future<void> markAsRead(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
    } catch (_) {}
  }

  // 通知を削除
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _supabase
          .from('notifications')
          .delete()
          .eq('id', notificationId);
    } catch (_) {}
  }

  // ---- 通知送信メソッド ----

  // シフト確定通知（管理者→スタッフ1人）
  Future<void> sendShiftConfirmed({
    required String storeId,
    required String recipientUserId,
    required String storeName,
    required String periodLabel, // 例: "5/1〜5/15"
    String? submissionId,
  }) async {
    await _send(
      storeId: storeId,
      recipientUserId: recipientUserId,
      type: 'shift_confirmed',
      title: 'シフトが確定しました',
      body: '$storeName のシフト（$periodLabel）が確定しました。確認してください。',
      relatedId: submissionId,
    );
  }

  // 募集開始通知（管理者→店舗の全スタッフ）
  Future<void> sendRecruitmentStarted({
    required String storeId,
    required List<String> recipientUserIds,
    required String storeName,
    required String periodLabel, // 例: "5/1〜5/15"
    String? recruitmentId,
  }) async {
    for (final uid in recipientUserIds) {
      await _send(
        storeId: storeId,
        recipientUserId: uid,
        type: 'recruitment_started',
        title: 'シフト募集が始まりました',
        body: '$storeName のシフト希望提出（$periodLabel）が開始しました。期限内に提出してください。',
        relatedId: recruitmentId,
      );
    }
  }

  // 希望シフト提出通知（スタッフ→管理者）
  Future<void> sendShiftRequestSubmitted({
    required String storeId,
    required String recipientUserId, // 管理者のuser_id
    required String staffName,
    required String storeName,
    required String periodLabel,
    String? recruitmentId,
  }) async {
    await _send(
      storeId: storeId,
      recipientUserId: recipientUserId,
      type: 'shift_request_submitted',
      title: 'シフト希望が提出されました',
      body: '$storeName：$staffName さんがシフト希望（$periodLabel）を提出しました。',
      relatedId: recruitmentId,
    );
  }

  // 内部送信処理
  Future<void> _send({
    required String storeId,
    required String recipientUserId,
    required String type,
    required String title,
    required String body,
    String? relatedId,
  }) async {
    final senderId = _supabase.auth.currentUser?.id;
    try {
      await _supabase.from('notifications').insert({
        'store_id': storeId,
        'recipient_user_id': recipientUserId,
        'sender_user_id': senderId,
        'type': type,
        'title': title,
        'body': body,
        'related_id': relatedId,
      });
    } catch (_) {}
  }
}