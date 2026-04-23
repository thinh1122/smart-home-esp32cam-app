import '../services/device_config_service.dart';

class AppConfig {
  // MQTT Broker (HiveMQ Public)
  static const String mqttHost = 'broker.hivemq.com';
  static const int mqttPort = 1883;

  // Render Backend API
  static const String renderApiUrl = 'https://your-app.onrender.com/api';
  static const String renderApiKey = 'your_api_key';

  // Local Relay Server (Raspberry Pi / PC trên cùng mạng LAN)
  static const String relayHost = '192.168.110.40';
  static const int relayPort = 8080;
  static String get relayBaseUrl => 'http://$relayHost:$relayPort';

  // Python AI Server (nhận diện khuôn mặt)
  static const String aiHost = '192.168.110.40';
  static const int aiPort = 5000;
  static String get aiBaseUrl => 'http://$aiHost:$aiPort';

  // Stream URL — dùng Python relay để tránh quá tải ESP32 (ESP32 chỉ chịu 1 client)
  // Flutter đọc từ relay, Python server tự kéo 1 kết nối duy nhất từ ESP32
  static String get streamUrl => '$aiBaseUrl/stream';

  // ESP32 trực tiếp — chỉ dùng nội bộ (Python server gọi để lấy frame cho AI)
  static String get esp32StreamUrl => DeviceConfigService.instance.streamUrl;
  static String get captureUrl => DeviceConfigService.instance.captureUrl;

  // AI server endpoints
  static String get enrollUrl => '$aiBaseUrl/enroll';
  static String get deleteUrl => '$aiBaseUrl/delete';
  static String get membersUrl => '$aiBaseUrl/members';

  // MQTT Topics
  static const String topicFaceResult = 'home/face_recognition/result';
  static const String topicFaceAlert = 'home/face_recognition/alert';
  static const String topicDeviceState = 'home/devices/+/+/state';
  static const String topicLogs = 'home/logs/activity';

  // App settings
  static const int recognitionIntervalSeconds = 3;
  static const int faceStableThresholdSeconds = 2;
  static const int maxLocalLogs = 100;
}
