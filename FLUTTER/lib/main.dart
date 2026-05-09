import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/mqtt_service.dart';
import 'core/services/device_config_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/server_discovery_service.dart';
import 'presentation/screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved IP (ESP32 + AI server) trước khi app render
  await DeviceConfigService.instance.init();

  // Khởi tạo notification channels
  await NotificationService.instance.init();

  // Connect MQTT in background
  MQTTService().connect().then((ok) => debugPrint(ok ? 'MQTT connected' : 'MQTT offline'));

  // Tự động tìm Python AI server trên LAN qua mDNS (background)
  // Nếu tìm thấy sẽ tự lưu IP — không cần nhập thủ công
  ServerDiscoveryService.instance.startDiscovery();

  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Smart Home',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const MainScreen(),
    );
  }
}
