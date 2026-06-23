import '../services/device_config_service.dart';

class AppConfig {
  // MQTT Broker (HiveMQ Cloud — TCP SSL port 8883)
  static const String mqttHost     = '1ef998ab22bd4df3bc84b3aea3525fa7.s1.eu.hivemq.cloud';
  static const int    mqttPort     = 8883;
  static const String mqttUsername = 'phungthinh';
  static const String mqttPassword = '@Phungthinh2611';

  // Python AI Server — IP lưu trong SharedPreferences, thay đổi qua Settings screen
  static String get aiBaseUrl => DeviceConfigService.instance.aiBaseUrl;
  static bool   get hasAiServer => DeviceConfigService.instance.hasAiIp;

  // Stream URL — trực tiếp từ ESP32-CAM, không qua relay
  static String get streamUrl => DeviceConfigService.instance.streamUrl;

  // Capture URL — trực tiếp từ ESP32-CAM
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
  static const String topicFaceBbox    = 'home/face_recognition/bbox';
  static const String topicDeviceState = 'home/devices/+/+/state';
  static const String topicLogs        = 'home/logs/activity';

  // App settings
  static const int maxLocalLogs = 100;
}
