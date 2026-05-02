import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // サインアップ
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    String mode = 'store',
  }) async {
    final response = await _supabase.auth.signUp(
      email: email,
      password: password,
    );

    // user_profilesにも登録
    if (response.user != null) {
      await _supabase.from('user_profiles').insert({
        'id': response.user!.id,
        'name': name,
        'email': email,
        'mode': mode,
      });
    }

    return response;
  }

  // ログイン
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  // ログアウト
  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }

  // 現在のユーザー
  User? get currentUser => _supabase.auth.currentUser;

  // ログイン状態の監視
  Stream<AuthState> get authStateChanges => _supabase.auth.onAuthStateChange;

  // モード取得
  Future<String> getUserMode() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'store';
    final data = await _supabase
        .from('user_profiles')
        .select('mode')
        .eq('id', userId)
        .single();
    return data['mode'] as String? ?? 'store';
  }
}