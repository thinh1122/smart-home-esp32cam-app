import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceConfigService {
  static final DeviceConfigService instance = DeviceConfigService._();
  DeviceConfigService._();

  /// Fires whenever the AI server IP/port is saved — listen to force stream reload
  final aiServerNotifier = ValueNotifier<String>('');

  static const _keyEsp32Ip  = 'esp32_ip';
  static const _keyEsp32Port = 'esp32_port';
  static const _keyAiIp    = 'ai_server_ip';
  static const _keyAiPort   = 'ai_server_port';

  String _esp32Ip  = '';
  int    _esp32Port = 81;
  String _aiIp     = '';   // empty = chưa cấu hình
  int    _aiPort   = 5000;

  // ESP32
  String get esp32Ip     => _esp32Ip;
  int    get esp32Port   => _esp32Port;
  bool   get hasEsp32Ip  => _esp32Ip.isNotEmpty;
  String get esp32BaseUrl => 'http://$_esp32Ip:$_esp32Port';
  // Nếu AI online → dùng /stream_annotated (có bounding box khuôn mặt)
  // Nếu không → thẳng ESP32
  String get streamUrl    => hasAiIp ? '$aiBaseUrl/stream_annotated' : '$esp32BaseUrl/stream';
  String get captureUrl   => '$esp32BaseUrl/capture';

  // AI Server
  String get aiIp      => _aiIp;
  int    get aiPort    => _aiPort;
  bool   get hasAiIp   => _aiIp.isNotEmpty;
  String get aiBaseUrl => hasAiIp ? 'http://$_aiIp:$_aiPort' : '';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();

    // ESP32 — clear stale port=8080 from old version
    final savedEsp32Port = prefs.getInt(_keyEsp32Port) ?? 81;
    if (savedEsp32Port == 8080) {
      await prefs.remove(_keyEsp32Ip);
      await prefs.remove(_keyEsp32Port);
      _esp32Ip   = '';
      _esp32Port = 81;
    } else {
      _esp32Ip   = prefs.getString(_keyEsp32Ip) ?? '';
      _esp32Port = savedEsp32Port;
    }

    // AI Server
    _aiIp   = prefs.getString(_keyAiIp)  ?? '';
    _aiPort = prefs.getInt(_keyAiPort)   ?? 5000;
  }

  Future<void> saveEsp32Ip(String ip, {int port = 81}) async {
    _esp32Ip   = ip;
    _esp32Port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEsp32Ip, ip);
    await prefs.setInt(_keyEsp32Port, port);
  }

  Future<void> saveAiServer(String ip, {int port = 5000}) async {
    _aiIp   = ip;
    _aiPort = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAiIp, ip);
    await prefs.setInt(_keyAiPort, port);
    aiServerNotifier.value = aiBaseUrl; // notify listeners
  }

  Future<void> reset() async {
    _esp32Ip = ''; _esp32Port = 81;
    _aiIp    = ''; _aiPort    = 5000;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEsp32Ip);
    await prefs.remove(_keyEsp32Port);
    await prefs.remove(_keyAiIp);
    await prefs.remove(_keyAiPort);
  }
}
