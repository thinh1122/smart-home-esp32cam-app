import 'dart:async';
import 'package:flutter/foundation.dart';
import 'mqtt_service.dart';
import 'notification_service.dart';
import '../config/app_config.dart';

class AppNotification {
  final String title, body;
  final bool isAlert;
  final DateTime time;
  const AppNotification({
    required this.title,
    required this.body,
    required this.isAlert,
    required this.time,
  });
}

class AppNotificationService extends ChangeNotifier {
  static final AppNotificationService instance = AppNotificationService._();
  AppNotificationService._();

  final List<AppNotification> _items = [];
  int _unreadCount = 0;
  StreamSubscription? _faceSub;

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;

  /// Gọi 1 lần trong main() sau khi MQTT connect
  void startListening() {
    _faceSub?.cancel();
    _faceSub = MQTTService().faceRecognitionStream.listen((event) {
      final topic = event['topic'] as String;
      final data  = event['data']  as Map<String, dynamic>;

      if (topic == AppConfig.topicFaceResult &&
          (data['matched'] as bool? ?? false)) {
        final name = data['name'] as String? ?? '';
        final role = data['role'] as String? ?? '';
        final conf = data['confidence'] != null
            ? '${((data['confidence'] as num) * 100).toStringAsFixed(0)}%'
            : '';
        add('Xin chào $name!', '$role — $conf');
        NotificationService.instance
            .showMemberRecognized(name: name, role: role, confidence: conf);
      } else if (topic == AppConfig.topicFaceAlert) {
        add('Phát hiện người lạ!',
            'Camera cửa trước phát hiện người không xác định',
            isAlert: true);
        NotificationService.instance.showStrangerAlert();
      }
    });
  }

  void stopListening() => _faceSub?.cancel();

  void add(String title, String body, {bool isAlert = false}) {
    _items.insert(0, AppNotification(
      title: title, body: body, isAlert: isAlert, time: DateTime.now(),
    ));
    if (_items.length > 100) _items.removeLast();
    _unreadCount++;
    notifyListeners();
  }

  void markAllRead() {
    _unreadCount = 0;
    notifyListeners();
  }

  void clearAll() {
    _items.clear();
    _unreadCount = 0;
    notifyListeners();
  }
}
