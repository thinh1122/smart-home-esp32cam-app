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

  // ESP32-CAM trực tiếp
  static const String esp32Host = '192.168.110.230';
  static const int esp32StreamPort = 81;
  static String get esp32StreamUrl => 'http://$esp32Host:$esp32StreamPort/stream';

  // Stream URL: Dùng Relay qua Python để xem được nhiều máy cùng lúc
  static String get streamUrl => '$aiBaseUrl/stream';
  static String get captureUrl => 'http://$esp32Host:$esp32StreamPort/capture';

  // AI server endpoints
  static String get recognizeUrl => '$aiBaseUrl/recognize';
  static String get enrollUrl => '$aiBaseUrl/enroll';
  static String get deleteUrl => '$aiBaseUrl/delete';
  static String get membersUrl => '$aiBaseUrl/members';
  static String get autoCaptureCompareUrl => '$aiBaseUrl/auto_capture_compare';

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
