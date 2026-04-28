import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'device_config_service.dart';

/// Tự động tìm Python AI server trên LAN qua mDNS (_smarthome._tcp)
/// Không cần nhập IP thủ công — server tự broadcast, Flutter tự tìm
class ServerDiscoveryService {
  static final ServerDiscoveryService instance = ServerDiscoveryService._();
  ServerDiscoveryService._();

  static const _serviceType = '_smarthome._tcp';

  BonsoirDiscovery? _discovery;
  bool _isSearching = false;

  /// Bắt đầu tìm server — gọi 1 lần khi app khởi động
  Future<void> startDiscovery() async {
    if (_isSearching) return;
    _isSearching = true;

    try {
      _discovery = BonsoirDiscovery(type: _serviceType);
      await _discovery!.ready;

      _discovery!.eventStream?.listen((event) {
        if (event.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          event.service?.resolve(_discovery!.serviceResolver);
        } else if (event.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final svc = event.service as ResolvedBonsoirService?;
          if (svc == null) return;

          final ip   = svc.host ?? '';
          final port = svc.port;

          if (ip.isNotEmpty) {
            debugPrint('🔍 mDNS: Found AI server at $ip:$port');
            DeviceConfigService.instance.saveAiServer(ip, port: port);
          }
        }
      });

      await _discovery!.start();
      debugPrint('🔍 mDNS discovery started — looking for $_serviceType');
    } catch (e) {
      debugPrint('⚠️ mDNS discovery error: $e');
      _isSearching = false;
    }
  }

  Future<void> stopDiscovery() async {
    await _discovery?.stop();
    _discovery = null;
    _isSearching = false;
  }
}
