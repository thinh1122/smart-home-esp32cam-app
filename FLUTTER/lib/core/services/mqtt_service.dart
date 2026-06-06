import 'dart:async';
import 'dart:convert';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import 'device_config_service.dart';

class MQTTService {
  static final MQTTService _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  MQTTService._internal();

  MqttServerClient? _client;
  bool _isConnected = false;
  final ValueNotifier<bool> connectionNotifier = ValueNotifier(false);

  final _faceRecognitionController = StreamController<Map<String, dynamic>>.broadcast();
  final _deviceStateController = StreamController<Map<String, dynamic>>.broadcast();
  final _systemLogsController = StreamController<Map<String, dynamic>>.broadcast();
  final _faceBboxController = StreamController<Map<String, dynamic>>.broadcast();
  final _devicePowerController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<Map<String, dynamic>> get faceRecognitionStream => _faceRecognitionController.stream;
  Stream<Map<String, dynamic>> get deviceStateStream => _deviceStateController.stream;
  Stream<Map<String, dynamic>> get systemLogsStream => _systemLogsController.stream;
  Stream<Map<String, dynamic>> get faceBboxStream => _faceBboxController.stream;
  // Power stream: {topic, data:{watt, current, state, ts}}
  Stream<Map<String, dynamic>> get devicePowerStream => _devicePowerController.stream;

  bool get isConnected => _isConnected;

  Future<bool> connect() async {
    if (_isConnected) return true;

    try {
      final clientId = 'flutter_smarthome_${DateTime.now().millisecondsSinceEpoch}';
      _client = MqttServerClient.withPort(AppConfig.mqttHost, clientId, AppConfig.mqttPort);
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 5000;
      _client!.secure = true;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;

      final connMessage = MqttConnectMessage()
          .startClean()
          .withWillTopic('home/flutter/status')
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);
      _client!.connectionMessage = connMessage;

      await _client!.connect(AppConfig.mqttUsername, AppConfig.mqttPassword);

      if (_client!.connectionStatus!.state == MqttConnectionState.connected) {
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('MQTT connect error: $e');
      _isConnected = false;
      connectionNotifier.value = false;
      return false;
    }
  }

  void _subscribeToTopics() {
    const topics = [
      AppConfig.topicFaceResult,
      AppConfig.topicFaceAlert,
      AppConfig.topicFaceBbox,
      AppConfig.topicDeviceState,
      AppConfig.topicLogs,
      'home/server/ip',
      'home/devices/+/+/power',  // ACS712 power data từ ESP32-S3
    ];
    for (var topic in topics) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void publish(String topic, Map<String, dynamic> payload) {
    if (!_isConnected || _client == null) {
      connect().then((ok) {
        if (ok) {
          Future.delayed(const Duration(milliseconds: 300), () => _doPublish(topic, payload));
        } else {
          debugPrint('MQTT publish skipped — offline: $topic');
        }
      });
      return;
    }
    _doPublish(topic, payload);
  }

  void _doPublish(String topic, Map<String, dynamic> payload) {
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payload));
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!);
      debugPrint('MQTT publish → $topic: $payload');
    } catch (e) {
      debugPrint('MQTT publish error: $e');
    }
  }

  void controlLight(String roomName, bool turnOn) {
    publish('home/devices/light/$roomName/command', {
      'state': turnOn ? 'ON' : 'OFF',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void controlDoor(String doorName, String action) {
    publish('home/devices/door/$doorName/command', {
      'action': action,
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _onMessage(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (var message in messages) {
      final topic = message.topic;
      final payload = MqttPublishPayload.bytesToStringAsString(
        (message.payload as MqttPublishMessage).payload.message,
      );
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        if (topic == 'home/server/ip') {
          final ip   = data['ip']   as String?;
          final port = (data['port'] as num?)?.toInt();
          final type = data['type'] as String? ?? '';
          if (ip != null && ip.isNotEmpty) {
            if (type == 'esp32cam') {
              // ESP32CAM broadcast IP → lưu để stream
              DeviceConfigService.instance.saveEsp32Ip(ip, port: port ?? 81);
              debugPrint('📷 ESP32CAM tự động phát hiện: $ip:${port ?? 81}');
            } else {
              // Python AI server broadcast IP
              DeviceConfigService.instance.saveAiServer(ip, port: port ?? 5000);
              debugPrint('🤖 AI Server tự động cấu hình: $ip:${port ?? 5000}');
            }
          }
        } else if (topic == AppConfig.topicFaceBbox) {
          _faceBboxController.add(data);
        } else if (topic.startsWith('home/face_recognition/')) {
          _faceRecognitionController.add({'topic': topic, 'data': data});
        } else if (topic.endsWith('/power')) {
          _devicePowerController.add({'topic': topic, 'data': data});
        } else if (topic.startsWith('home/devices/')) {
          _deviceStateController.add({'topic': topic, 'data': data});
        } else if (topic.startsWith('home/logs/')) {
          _systemLogsController.add({'topic': topic, 'data': data});
        }
      } catch (_) {}
    }
  }

  void _onConnected() {
    _isConnected = true;
    connectionNotifier.value = true;
    _subscribeToTopics();
    _client!.updates!.listen(_onMessage);
    publish('home/flutter/status', {'status': 'online', 'ts': DateTime.now().toIso8601String()});
  }

  void _onDisconnected() {
    _isConnected = false;
    connectionNotifier.value = false;
    // Retry ngắn hơn: 3s lần 1, sau đó 10s
    Future.delayed(const Duration(seconds: 3), () {
      if (!_isConnected) connect();
    });
  }

  void disconnect() {
    if (_client != null) {
      publish('home/flutter/status', {'status': 'offline', 'ts': DateTime.now().toIso8601String()});
      _client!.disconnect();
      _isConnected = false;
    }
  }

  void dispose() {
    disconnect();
    _faceRecognitionController.close();
    _deviceStateController.close();
    _systemLogsController.close();
    _faceBboxController.close();
    _devicePowerController.close();
  }
}
