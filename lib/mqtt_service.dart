import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart';

class MQTTService {
  static final MQTTService _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  MQTTService._internal();

  // MQTTX Configuration (Mosquitto Public Broker - đã test ổn định)
  static const String _host = 'test.mosquitto.org';
  static const int _port = 1883;
  static const String _username = ''; // Không cần username
  static const String _password = ''; // Không cần password

  MqttServerClient? _client;
  bool _isConnected = false;

  // Stream controllers cho các topic
  final _faceRecognitionController = StreamController<Map<String, dynamic>>.broadcast();
  final _deviceStateController = StreamController<Map<String, dynamic>>.broadcast();
  final _systemLogsController = StreamController<Map<String, dynamic>>.broadcast();

  // Getters cho streams
  Stream<Map<String, dynamic>> get faceRecognitionStream => _faceRecognitionController.stream;
  Stream<Map<String, dynamic>> get deviceStateStream => _deviceStateController.stream;
  Stream<Map<String, dynamic>> get systemLogsStream => _systemLogsController.stream;

  bool get isConnected => _isConnected;

  // ============================================================
  // CONNECT TO HIVEMQ
  // ============================================================
  Future<bool> connect() async {
    if (_isConnected) {
      debugPrint('✅ MQTT already connected');
      return true;
    }

    try {
      _client = MqttServerClient.withPort(_host, 'flutter_app_${DateTime.now().millisecondsSinceEpoch}', _port);
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 5000;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;
      _client!.onSubscribed = _onSubscribed;
      // ⭐ THAY ĐỔI - Không dùng TLS cho Mosquitto
      _client!.secure = false;

      final connMessage = MqttConnectMessage()
          .startClean()
          .withWillTopic('home/flutter/status')
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);

      _client!.connectionMessage = connMessage;

      debugPrint('🔌 Connecting to MQTTX (Mosquitto): $_host:$_port');
      await _client!.connect();

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        debugPrint('✅ MQTTX connected successfully');
        _isConnected = true;

        // Subscribe to topics
        _subscribeToTopics();

        // Listen to messages
        _client!.updates!.listen(_onMessage);

        // Publish online status
        publish('home/flutter/status', {'status': 'online', 'timestamp': DateTime.now().toIso8601String()});

        return true;
      } else {
        debugPrint('❌ MQTTX connection failed: ${_client!.connectionStatus}');
        _isConnected = false;
        return false;
      }
    } catch (e) {
      debugPrint('❌ MQTTX connection error: $e');
      _isConnected = false;
      return false;
    }
  }

  // ============================================================
  // SUBSCRIBE TO TOPICS
  // ============================================================
  void _subscribeToTopics() {
    final topics = [
      'home/face_recognition/result',
      'home/face_recognition/alert',
      'home/devices/+/+/state',
      'home/logs/activity',
      'home/analytics/stats',
    ];

    for (var topic in topics) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
      debugPrint('📡 Subscribed to: $topic');
    }
  }

  // ============================================================
  // PUBLISH MESSAGE
  // ============================================================
  void publish(String topic, Map<String, dynamic> payload) {
    if (!_isConnected || _client == null) {
      debugPrint('❌ Cannot publish: MQTT not connected');
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(jsonEncode(payload));

    _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
    debugPrint('📤 Published to $topic: $payload');
  }

  // ============================================================
  // DEVICE CONTROL
  // ============================================================
  void controlLight(String roomName, bool turnOn) {
    publish('home/devices/light/$roomName/command', {
      'state': turnOn ? 'ON' : 'OFF',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void controlDoor(String doorName, String action) {
    publish('home/devices/door/$doorName/command', {
      'action': action, // 'open', 'close', 'lock', 'unlock'
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void controlCamera(String action) {
    publish('home/devices/camera/esp32cam/command', {
      'action': action, // 'start_stream', 'stop_stream', 'capture'
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ============================================================
  // MESSAGE HANDLER
  // ============================================================
  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var message in messages) {
      final topic = message.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (message.payload as MqttPublishMessage).payload.message,
      );

      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        debugPrint('📨 MQTT Message [$topic]: $data');

        // Route message to appropriate stream
        if (topic.startsWith('home/face_recognition/')) {
          _faceRecognitionController.add({'topic': topic, 'data': data});
        } else if (topic.startsWith('home/devices/')) {
          _deviceStateController.add({'topic': topic, 'data': data});
        } else if (topic.startsWith('home/logs/')) {
          _systemLogsController.add({'topic': topic, 'data': data});
        }
      } catch (e) {
        debugPrint('❌ Error parsing MQTT message: $e');
      }
    }
  }

  // ============================================================
  // CONNECTION CALLBACKS
  // ============================================================
  void _onConnected() {
    debugPrint('✅ MQTTX connected callback');
    _isConnected = true;
  }

  void _onDisconnected() {
    debugPrint('⚠️ MQTTX disconnected');
    _isConnected = false;
    
    // Auto reconnect after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (!_isConnected) {
        debugPrint('🔄 Attempting to reconnect...');
        connect();
      }
    });
  }

  void _onSubscribed(String topic) {
    debugPrint('✅ Subscribed to: $topic');
  }

  // ============================================================
  // DISCONNECT
  // ============================================================
  void disconnect() {
    if (_client != null) {
      publish('home/flutter/status', {'status': 'offline', 'timestamp': DateTime.now().toIso8601String()});
      _client!.disconnect();
      _isConnected = false;
      debugPrint('⚠️ MQTTX disconnected manually');
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================
  void dispose() {
    disconnect();
    _faceRecognitionController.close();
    _deviceStateController.close();
    _systemLogsController.close();
  }
}
