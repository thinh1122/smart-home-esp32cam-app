import 'dart:async';
import 'dart:convert';
import 'dart:io';
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
  StreamSubscription? _msgSub;
  final ValueNotifier<bool> connectionNotifier = ValueNotifier(false);
  final ValueNotifier<bool> voiceMicOnlineNotifier = ValueNotifier(false);

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
      _client?.disconnect();
      _client = null;
      final clientId = 'flutter_smarthome_${DateTime.now().millisecondsSinceEpoch}';
      // TCP SSL port 8883 — dùng SecurityContext.defaultContext để OS tự xác thực cert HiveMQ
      _client = MqttServerClient.withPort(AppConfig.mqttHost, clientId, AppConfig.mqttPort);
      _client!.secure = true;
      _client!.securityContext = SecurityContext.defaultContext;
      _client!.logging(on: false);
      _client!.keepAlivePeriod = 60;
      _client!.connectTimeoutPeriod = 10000;
      _client!.onDisconnected = _onDisconnected;
      _client!.onConnected = _onConnected;

      final connMessage = MqttConnectMessage()
          .withClientIdentifier(clientId)
          .startClean()
          .withWillTopic('home/flutter/status')
          .withWillMessage('offline')
          .withWillQos(MqttQos.atLeastOnce);
      _client!.connectionMessage = connMessage;

      debugPrint('MQTT connecting TCP SSL: ${AppConfig.mqttHost}:${AppConfig.mqttPort}');
      await _client!.connect(AppConfig.mqttUsername, AppConfig.mqttPassword);

      debugPrint('MQTT state: ${_client!.connectionStatus!.state}');
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
      'home/devices/voice/status',  // online/offline ESP32-MIC
    ];
    for (var topic in topics) {
      _client!.subscribe(topic, MqttQos.atLeastOnce);
    }
  }

  void publish(String topic, Map<String, dynamic> payload, {bool retain = false}) {
    if (!_isConnected || _client == null) {
      connect().then((ok) {
        if (ok) {
          Future.delayed(const Duration(milliseconds: 300), () => _doPublish(topic, payload, retain: retain));
        } else {
          debugPrint('MQTT publish skipped — offline: $topic');
        }
      });
      return;
    }
    _doPublish(topic, payload, retain: retain);
  }

  void _doPublish(String topic, Map<String, dynamic> payload, {bool retain = false}) {
    try {
      final builder = MqttClientPayloadBuilder();
      builder.addString(jsonEncode(payload));
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      debugPrint('MQTT publish → $topic: $payload${retain ? " [retain]" : ""}');
    } catch (e) {
      debugPrint('MQTT publish error: $e');
    }
  }

  /// Publish raw string (dùng để clear retained message bằng cách publish payload rỗng)
  void publishRaw(String topic, String payload, {bool retain = false}) {
    if (!_isConnected || _client == null) return;
    try {
      final builder = MqttClientPayloadBuilder();
      if (payload.isNotEmpty) builder.addString(payload);
      _client!.publishMessage(topic, MqttQos.atLeastOnce, builder.payload!, retain: retain);
      debugPrint('MQTT publishRaw → $topic${retain ? " [retain]" : ""}');
    } catch (e) {
      debugPrint('MQTT publishRaw error: $e');
    }
  }

  /// Unsubscribe rồi subscribe lại state topics để nhận retained message từ broker.
  /// Gọi sau khi đăng nhập lại để đồng bộ trạng thái đèn mà không cần ESP32 publish mới.
  void resubscribeState() {
    if (!_isConnected || _client == null) return;
    const stateTopics = [AppConfig.topicDeviceState, 'home/devices/+/+/power'];
    for (final t in stateTopics) {
      _client!.unsubscribe(t);
      _client!.subscribe(t, MqttQos.atLeastOnce);
    }
  }

  void controlLight(String roomName, bool turnOn) {
    publish('home/devices/light/$roomName/command', {
      'state': turnOn ? 'ON' : 'OFF',
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void resetVoiceMicWifi() {
    const topic = 'home/devices/voice/reset_wifi';
    publish(topic, {
      'action': 'reset_wifi',
      'ts': DateTime.now().millisecondsSinceEpoch,
    }, retain: true);
    Future.delayed(const Duration(seconds: 3), () {
      publishRaw(topic, '', retain: true);
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
      if (topic == 'home/devices/voice/status') {
        voiceMicOnlineNotifier.value = payload == 'online';
        continue;
      }
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
          debugPrint('MQTT recv state → $topic: $data');
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
    _msgSub?.cancel();
    _msgSub = _client!.updates!.listen(_onMessage);
    publish('home/flutter/status', {'status': 'online', 'ts': DateTime.now().toIso8601String()});
    // Force broker gửi lại retained state ngay khi (re)connect — đảm bảo UI luôn nhận trạng thái thật
    resubscribeState();
  }

  void _onDisconnected() {
    _isConnected = false;
    connectionNotifier.value = false;
    // Jitter ngẫu nhiên 0-3s tránh dồn dập reconnect cùng lúc với ESP32 khác, tránh broker từ chối hàng loạt
    final jitterMs = 3000 + (DateTime.now().millisecondsSinceEpoch % 3000);
    Future.delayed(Duration(milliseconds: jitterMs), () {
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
