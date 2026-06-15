import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/services/mqtt_service.dart';
import 'core/services/device_config_service.dart';
import 'core/services/notification_service.dart';
import 'core/services/app_notification_service.dart';
import 'core/services/server_discovery_service.dart';
import 'core/services/auth_service.dart';
import 'core/services/database_helper.dart';
import 'presentation/screens/admin/admin_screen.dart';
import 'presentation/screens/main_screen.dart';
import 'presentation/screens/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DeviceConfigService.instance.init();
  await NotificationService.instance.init();
  await DatabaseHelper.instance.ensureAdminAccount();
  await AuthService.instance.init();

  MQTTService().connect().then((ok) {
    debugPrint(ok ? 'MQTT connected' : 'MQTT offline');
  });

  AppNotificationService.instance.startListening();
  ServerDiscoveryService.instance.startDiscovery();

  runApp(const SmartHomeApp());
}

class SmartHomeApp extends StatelessWidget {
  const SmartHomeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (_, mode, __) => MaterialApp(
        title: 'Smart Home',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        home: const _AuthGate(),
      ),
    );
  }
}

class _AuthGate extends StatelessWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AuthService.instance.isLoggedIn,
      builder: (_, loggedIn, __) {
        if (!loggedIn) return const LoginScreen();
        return AuthService.instance.isAdmin
            ? const AdminScreen()
            : const MainScreen();
      },
    );
  }
}
