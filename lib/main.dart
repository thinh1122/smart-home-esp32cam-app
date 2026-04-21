import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/mqtt_service.dart';
import 'core/services/render_api_service.dart';
import 'presentation/screens/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Connect MQTT in background — don't block app startup
  MQTTService().connect().then((ok) => debugPrint(ok ? 'MQTT connected' : 'MQTT offline'));

  // Check backend health in background
  RenderAPIService().checkHealth().then((ok) => debugPrint(ok ? 'Backend online' : 'Backend offline'));

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
