import 'package:flutter/foundation.dart';

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

  List<AppNotification> get items => List.unmodifiable(_items);
  int get unreadCount => _unreadCount;

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
