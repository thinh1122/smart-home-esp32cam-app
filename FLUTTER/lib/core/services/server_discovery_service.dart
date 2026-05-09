import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'device_config_service.dart';

/// Tự động tìm ESP32-CAM trên LAN qua mDNS (_esp32cam._tcp)
/// ESP32 broadcast sau khi kết nối WiFi → Flutter tự lấy IP, không cần nhập tay
class ServerDiscoveryService {
  static final ServerDiscoveryService instance = ServerDiscoveryService._();
  ServerDiscoveryService._();

  // ESP32-CAM service type — phải khớp với MDNS.addService trong firmware
  static const _esp32ServiceType = '_esp32cam._tcp';
  // Python AI server (vẫn giữ để tương thích cũ)
  static const _aiServiceType = '_smarthome._tcp';

  BonsoirDiscovery? _esp32Discovery;
  BonsoirDiscovery? _aiDiscovery;
  bool _isSearching = false;

  Future<void> startDiscovery() async {
    if (_isSearching) return;
    _isSearching = true;
    _discoverEsp32();
    _discoverAiServer();
  }

  void _discoverEsp32() async {
    try {
      _esp32Discovery = BonsoirDiscovery(type: _esp32ServiceType);
      await _esp32Discovery!.ready;
      _esp32Discovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_esp32Discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final svc = event.service as ResolvedBonsoirService?;
          if (svc == null) return;
          final ip = svc.host ?? '';
          if (ip.isNotEmpty) {
            debugPrint('📡 mDNS: ESP32-CAM found at $ip:${svc.port}');
            DeviceConfigService.instance.saveEsp32Ip(ip, port: svc.port);
          }
        }
      });
      await _esp32Discovery!.start();
      debugPrint('🔍 mDNS discovery started — looking for ESP32-CAM ($_esp32ServiceType)');
    } catch (e) {
      debugPrint('⚠️ mDNS ESP32 discovery error: $e');
    }
  }

  void _discoverAiServer() async {
    try {
      _aiDiscovery = BonsoirDiscovery(type: _aiServiceType);
      await _aiDiscovery!.ready;
      _aiDiscovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_aiDiscovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final svc = event.service as ResolvedBonsoirService?;
          if (svc == null) return;
          final ip = svc.host ?? '';
          if (ip.isNotEmpty) {
            debugPrint('🔍 mDNS: AI server found at $ip:${svc.port}');
            DeviceConfigService.instance.saveAiServer(ip, port: svc.port);
          }
        }
      });
      await _aiDiscovery!.start();
    } catch (e) {
      debugPrint('⚠️ mDNS AI discovery error: $e');
    }
  }

  Future<void> stopDiscovery() async {
    await _esp32Discovery?.stop();
    await _aiDiscovery?.stop();
    _esp32Discovery = null;
    _aiDiscovery = null;
    _isSearching = false;
  }
}
