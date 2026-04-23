import 'package:shared_preferences/shared_preferences.dart';

class DeviceConfigService {
  static final DeviceConfigService instance = DeviceConfigService._();
  DeviceConfigService._();

  static const _keyEsp32Ip = 'esp32_ip';
  static const _keyEsp32Port = 'esp32_port';
  static const _defaultIp = '';
  static const _defaultPort = 81;

  String _esp32Ip = _defaultIp;
  int _esp32Port = _defaultPort;

  String get esp32Ip => _esp32Ip;
  int get esp32Port => _esp32Port;
  String get esp32BaseUrl => 'http://$_esp32Ip:$_esp32Port';
  String get streamUrl => '$esp32BaseUrl/stream';
  String get captureUrl => '$esp32BaseUrl/capture';

  bool get hasIp => _esp32Ip.isNotEmpty;

  // Gọi 1 lần khi app khởi động
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final savedPort = prefs.getInt(_keyEsp32Port) ?? _defaultPort;
    // Clear stale config from old version that used port 8080
    if (savedPort == 8080) {
      await prefs.remove(_keyEsp32Ip);
      await prefs.remove(_keyEsp32Port);
      _esp32Ip = _defaultIp;
      _esp32Port = _defaultPort;
    } else {
      _esp32Ip = prefs.getString(_keyEsp32Ip) ?? _defaultIp;
      _esp32Port = savedPort;
    }
  }

  // Gọi khi BLE provisioning thành công và nhận được IP mới
  Future<void> saveEsp32Ip(String ip, {int port = _defaultPort}) async {
    _esp32Ip = ip;
    _esp32Port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEsp32Ip, ip);
    await prefs.setInt(_keyEsp32Port, port);
  }

  // Reset về default
  Future<void> reset() async {
    _esp32Ip = _defaultIp;
    _esp32Port = _defaultPort;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEsp32Ip);
    await prefs.remove(_keyEsp32Port);
  }
}
