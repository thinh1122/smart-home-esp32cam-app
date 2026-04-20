class AppConfig {
class AppConfig {
  // ⭐ MQTTX Configuration (Mosquitto Public Broker - đã test ổn định)
  static const String hivemqHost = 'test.mosquitto.org'; // Mosquitto public broker
  static const int hivemqPort = 1883;
  static const String hivemqUsername = ''; // Không cần cho Mosquitto
  static const String hivemqPassword = ''; // Không cần cho Mosquitto
  static const bool hivemqUseTLS = false;

  // Render Backend API
  static const String renderApiUrl = 'https://your-app.onrender.com/api'; // ⚠️ Thay bằng Render URL
  static const String renderApiKey = 'your_api_key'; // ⚠️ Thay bằng API key

  // Local Relay Server (khi ở nhà)
  static const String relayServerUrl = 'http://192.168.110.101:8080';
  
  // Python AI Server (local)
  static const String pythonAIUrl = 'http://192.168.110.101:5000';

  // ESP32-CAM
  static const String esp32IP = '192.168.110.38';
  static const int esp32Port = 81;

  // MQTT Topics
  static const String topicFaceRecognitionResult = 'home/face_recognition/result';
  static const String topicFaceRecognitionAlert = 'home/face_recognition/alert';
  static const String topicDeviceCommand = 'home/devices/{type}/{name}/command';
  static const String topicDeviceState = 'home/devices/{type}/{name}/state';
  static const String topicLogs = 'home/logs/activity';
  static const String topicAnalytics = 'home/analytics/stats';

  // App Settings
  static const int syncIntervalMinutes = 5; // Sync với Render mỗi 5 phút
  static const int maxLocalLogs = 100; // Giữ tối đa 100 logs local
  static const bool enableOfflineMode = true;
}
