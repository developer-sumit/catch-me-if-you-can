import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/api_client.dart';
import 'models/user.dart';

const _storage = FlutterSecureStorage();
final authProvider =
    AsyncNotifierProvider<AuthController, User?>(AuthController.new);
final apiProvider = Provider<ApiClient>((ref) => ApiClient(
    token: ref.watch(authProvider).valueOrNull == null
        ? null
        : ref.read(authProvider.notifier).token));

class AuthController extends AsyncNotifier<User?> {
  String? token;
  @override
  Future<User?> build() async {
    token = await _storage.read(key: 'access_token');
    if (token == null) return null;
    try {
      return User.fromJson(Map<String, dynamic>.from(
          await ApiClient(token: token).get('/auth/me')));
    } catch (_) {
      await _storage.delete(key: 'access_token');
      token = null;
      return null;
    }
  }

  Future<void> login(String email, String password) async {
    final j = Map<String, dynamic>.from(await ApiClient()
        .post('/auth/login', {'email': email, 'password': password}));
    token = j['token'];
    await _storage.write(key: 'access_token', value: token);
    state = AsyncData(User.fromJson(Map<String, dynamic>.from(j['user'])));
  }

  Future<void> register(Map<String, dynamic> body) async {
    final j = Map<String, dynamic>.from(
        await ApiClient().post('/auth/register', body));
    token = j['token'];
    await _storage.write(key: 'access_token', value: token);
    state = AsyncData(User.fromJson(Map<String, dynamic>.from(j['user'])));
  }

  Future<void> logout() async {
    await _storage.delete(key: 'access_token');
    token = null;
    state = const AsyncData(null);
  }
}
