import '../services/device_config_service.dart';

class AppConfig {
  // MQTT Broker (HiveMQ Public)
  static const String mqttHost = 'broker.hivemq.com';
  static const int    mqttPort = 1883;

  // Python AI Server — IP lưu trong SharedPreferences, thay đổi qua Settings screen
  static String get aiBaseUrl => DeviceConfigService.instance.aiBaseUrl;
  static bool   get hasAiServer => DeviceConfigService.instance.hasAiIp;

  // Stream URL — Python relay, ESP32 chỉ có 1 kết nối
  static String get streamUrl => hasAiServer ? '$aiBaseUrl/stream' : '';

  // ESP32 direct — Python server dùng nội bộ
  static String get captureUrl => DeviceConfigService.instance.captureUrl;

  // AI endpoints
  static String get enrollUrl  => '$aiBaseUrl/enroll';
  static String get deleteUrl  => '$aiBaseUrl/delete';
  static String get membersUrl => '$aiBaseUrl/members';
  static String get configUrl  => '$aiBaseUrl/config';
  static String get statusUrl  => '$aiBaseUrl/status';

  // MQTT Topics
  static const String topicFaceResult  = 'home/face_recognition/result';
  static const String topicFaceAlert   = 'home/face_recognition/alert';
  static const String topicDeviceState = 'home/devices/+/+/state';
  static const String topicLogs        = 'home/logs/activity';

  // App settings
  static const int maxLocalLogs = 100;
}
