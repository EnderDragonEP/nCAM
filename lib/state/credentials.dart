import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CameraCredentials {
  const CameraCredentials(this.ssid, this.password);
  final String ssid;
  final String password;
}

/// Remembers the camera's Wi-Fi name and password between launches.
abstract class CredentialStore {
  Future<CameraCredentials?> load();
  Future<void> save(CameraCredentials credentials);
  Future<void> clear();
}

/// Name in app preferences; password in the Android Keystore-backed secure storage.
class DeviceCredentialStore implements CredentialStore {
  static const _ssidKey = 'camera_ssid';
  static const _passwordKey = 'camera_password';
  final _secure = const FlutterSecureStorage();

  @override
  Future<CameraCredentials?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ssid = prefs.getString(_ssidKey);
    if (ssid == null || ssid.isEmpty) return null;
    String? password;
    try {
      password = await _secure.read(key: _passwordKey);
    } catch (_) {
      // Secure storage can be wiped by a restore from backup; ask again in that case.
      return null;
    }
    return CameraCredentials(ssid, password ?? '');
  }

  @override
  Future<void> save(CameraCredentials credentials) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ssidKey, credentials.ssid);
    await _secure.write(key: _passwordKey, value: credentials.password);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ssidKey);
    await _secure.delete(key: _passwordKey);
  }
}

class MemoryCredentialStore implements CredentialStore {
  MemoryCredentialStore([this._value]);
  CameraCredentials? _value;

  @override
  Future<CameraCredentials?> load() async => _value;

  @override
  Future<void> save(CameraCredentials credentials) async =>
      _value = credentials;

  @override
  Future<void> clear() async => _value = null;
}
