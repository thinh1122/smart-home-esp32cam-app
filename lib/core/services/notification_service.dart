import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../theme/app_theme.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _channelStranger = AndroidNotificationChannel(
    'stranger_alert',
    'Cảnh báo người lạ',
    description: 'Thông báo khi phát hiện người không xác định tại cửa',
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
  );

  static const _channelFace = AndroidNotificationChannel(
    'face_recognition',
    'Nhận diện khuôn mặt',
    description: 'Thông báo khi nhận diện thành công thành viên',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(_channelStranger);
    await androidPlugin?.createNotificationChannel(_channelFace);
    await androidPlugin?.requestNotificationsPermission();

    _initialized = true;
    debugPrint('NotificationService initialized');
  }

  // Cảnh báo người lạ — ưu tiên max, fullscreen intent, rung mạnh
  Future<void> showStrangerAlert() async {
    if (!_initialized) await init();
    await _plugin.show(
      1001,
      '⚠️ CẢNH BÁO: Phát hiện người lạ!',
      'Có người không xác định đứng trước cửa nhà. Kiểm tra ngay!',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelStranger.id,
          _channelStranger.name,
          channelDescription: _channelStranger.description,
          importance: Importance.max,
          priority: Priority.high,
          color: AppColors.error,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
          playSound: true,
          fullScreenIntent: true,
          ticker: 'Người lạ tại cửa',
          styleInformation: const BigTextStyleInformation(
            'Hệ thống camera cửa trước đã phát hiện một khuôn mặt không xác định. Vui lòng kiểm tra ngay!',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  // Thành viên được nhận diện thành công
  Future<void> showMemberRecognized({
    required String name,
    required String role,
    String confidence = '',
  }) async {
    if (!_initialized) await init();
    await _plugin.show(
      1002,
      '✅ Xin chào, $name!',
      '$role · Chào mừng về nhà${confidence.isNotEmpty ? " · $confidence" : ""}',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelFace.id,
          _channelFace.name,
          channelDescription: _channelFace.description,
          importance: Importance.high,
          priority: Priority.defaultPriority,
          color: AppColors.success,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: false,
        ),
      ),
    );
  }
}
