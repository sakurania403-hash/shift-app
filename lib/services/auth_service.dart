import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService {
  final _supabase = Supabase.instance.client;

  // サインアップ
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
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
}