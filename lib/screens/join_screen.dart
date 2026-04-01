import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../services/invitation_service.dart';
import 'main_screen.dart';

class JoinScreen extends StatefulWidget {
  final String token;

  const JoinScreen({super.key, required this.token});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _authService = AuthService();
  final _invitationService = InvitationService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLogin = false;
  bool _isLoading = true;
  Map<String, dynamic>? _invitation;
  String? _errorMessage;

  // 現在ログイン済みかどうか
  bool get _isAlreadyLoggedIn =>
      Supabase.instance.client.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _loadInvitation();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitation() async {
    try {
      final inv =
          await _invitationService.getInvitationByToken(widget.token);
      setState(() {
        _invitation = inv;
        _isLoading = false;
        if (inv == null) {
          _errorMessage = 'この招待URLは無効または期限切れです';
        }
      });

      // ログイン済みの場合は自動で参加処理を実行
      if (inv != null && _isAlreadyLoggedIn) {
        await _joinAsCurrentUser();
      }
    } catch (e) {
      setState(() {
        _invitation = null;
        _isLoading = false;
        _errorMessage = '招待情報の取得に失敗しました: $e';
      });
    }
  }

  // ログイン済みユーザーとしてそのまま店舗参加
  Future<void> _joinAsCurrentUser() async {
    if (_invitation == null) return;
    setState(() => _isLoading = true);
    try {
      final storeId = _invitation!['store_id'] as String;
      await _invitationService.joinStore(
        token: widget.token,
        storeId: storeId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('店舗への参加が完了しました！'),
            backgroundColor: Colors.teal,
          ),
        );
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = '参加に失敗しました: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_invitation == null) return;
    setState(() => _isLoading = true);
    try {
      if (_isLogin) {
        await _authService.signIn(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
        );
      } else {
        await _authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text.trim(),
          name: _nameController.text.trim(),
        );
      }

      final storeId = _invitation!['store_id'] as String;

      // 店舗に参加
      await _invitationService.joinStore(
        token: widget.token,
        storeId: storeId,
      );

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } on AuthException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'エラーが発生しました: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_invitation == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                _errorMessage ?? '無効な招待URLです',
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final storesData = _invitation!['stores'];
    String storeName = '店舗';
    if (storesData != null && storesData is Map) {
      storeName = (storesData['name'] ?? '店舗').toString();
    }

    // ログイン済みの場合はローディング表示（自動参加処理中）
    if (_isAlreadyLoggedIn) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(color: Colors.teal),
              const SizedBox(height: 16),
              Text(
                '「$storeName」に参加しています...',
                style: const TextStyle(fontSize: 16),
              ),
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _joinAsCurrentUser,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('再試行'),
                ),
              ],
            ],
          ),
        ),
      );
    }

    // 未ログインの場合は通常の参加フォームを表示
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.store, size: 64, color: Colors.teal),
                    const SizedBox(height: 16),
                    Text(
                      '「$storeName」に参加する',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isLogin
                          ? '既存のアカウントでログインして参加'
                          : '新しいアカウントを作成して参加',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 32),
                    if (!_isLogin) ...[
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: '名前',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'メールアドレス',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'パスワード',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    if (_errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const CircularProgressIndicator(
                                color: Colors.white)
                            : Text(_isLogin ? 'ログインして参加' : 'アカウント作成して参加'),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () =>
                          setState(() => _isLogin = !_isLogin),
                      child: Text(
                        _isLogin
                            ? 'アカウントをお持ちでない方はこちら'
                            : 'すでにアカウントをお持ちの方はこちら',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}