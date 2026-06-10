import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/device_config_service.dart';

class MyWiFiNetwork {
  final String ssid;
  final int level;
  final String capabilities;

  const MyWiFiNetwork({
    required this.ssid,
    required this.level,
    required this.capabilities,
  });

  @override
  bool operator ==(Object other) => identical(this, other) || other is MyWiFiNetwork && runtimeType == other.runtimeType && ssid == other.ssid;

  @override
  int get hashCode => ssid.hashCode;
}

class BLEWiFiProvisioningScreen extends StatefulWidget {
  const BLEWiFiProvisioningScreen({super.key});

  @override
  State<BLEWiFiProvisioningScreen> createState() => _BLEWiFiProvisioningScreenState();
}

class _BLEWiFiProvisioningScreenState extends State<BLEWiFiProvisioningScreen> {
  final _ssidCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  static const _serviceUUID    = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const _ssidCharUUID   = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const _passCharUUID   = '1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e';
  static const _statusCharUUID = 'd8de624e-140f-4a22-8594-e2216b84a5f2';
  static const _wifiListCharUUID = '2b8c9e50-7182-4f32-8414-b49911e0eb7e';
  static const _devIdCharUUID  = 'c0de1234-abcd-ef01-2345-67890abcdef0';

  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConfiguring = false;
  bool _obscurePass = true;
  int _step = 0;

  List<ScanResult> _scanResults = [];
  List<MyWiFiNetwork> _wifiNetworks = [];
  String? _selectedSSID;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ssidChar, _passChar, _statusChar, _wifiListChar, _devIdChar;
  String _deviceId = '';
  String? _esp32IP;

  StreamSubscription? _scanSub, _statusSub;

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _statusSub?.cancel();
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    _disconnect();
    super.dispose();
  }

  Future<void> _checkBluetooth() async {
    if (await FlutterBluePlus.isSupported == false) {
      _showError('Device does not support Bluetooth');
      return;
    }

    try {
      await FlutterBluePlus.adapterState
          .where((state) => state == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 5));
      _startScan();
    } catch (e) {
      _showError('Please enable Bluetooth and grant permissions');
    }
  }

  Future<void> _startScan() async {
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showError('Bluetooth is not ON. Cannot scan.');
      return;
    }

    setState(() { _isScanning = true; _step = 0; _scanResults.clear(); _deviceId = ''; });
    try {
      await FlutterBluePlus.stopScan();
      _scanSub = FlutterBluePlus.scanResults.listen((results) {
        if (mounted) {
          setState(() {
            _scanResults = results.where((r) => r.device.platformName.startsWith('ESP32')).toList();
          });
        }
      });
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10), androidUsesFineLocation: true);
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      if (mounted) setState(() => _isScanning = false);
      if (_scanResults.isEmpty && mounted) _showError('No ESP32 devices found.\nMake sure ESP32 is in pairing mode.');
    } catch (e) {
      if (mounted) { setState(() => _isScanning = false); _showError('Scan error: $e'); }
    }
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() { _isConnecting = true; _step = 1; });
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      final services = await device.discoverServices();

      for (var svc in services) {
        if (svc.uuid.toString().toLowerCase() != _serviceUUID.toLowerCase()) continue;
        for (var char in svc.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == _ssidCharUUID.toLowerCase())    _ssidChar    = char;
          if (uuid == _passCharUUID.toLowerCase())    _passChar    = char;
          if (uuid == _wifiListCharUUID.toLowerCase()) _wifiListChar = char;
          if (uuid == _devIdCharUUID.toLowerCase())   _devIdChar   = char;
          if (uuid == _statusCharUUID.toLowerCase()) {
            _statusChar = char;
            await char.setNotifyValue(true);
            _statusSub = char.lastValueStream.listen((value) {
              final status = String.fromCharCodes(value);
              if (status.startsWith('connected|')) {
                final ip = status.split('|')[1];
                setState(() { _esp32IP = ip; _step = 5; });
                _onConnectedSuccessfully(ip);
              } else if (status == 'failed') {
                if (mounted) {
                  setState(() {
                    _isConfiguring = false;
                    _step = 4;
                    _passCtrl.clear();
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Row(
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Colors.white),
                          SizedBox(width: 10),
                          Expanded(child: Text('Mật khẩu WiFi không đúng!\nVui lòng thử lại.')),
                        ],
                      ),
                      backgroundColor: Colors.redAccent,
                      duration: Duration(seconds: 4),
                    ),
                  );
                }
              }
            });
          }
        }
      }

      if (_ssidChar == null || _passChar == null || _statusChar == null) {
        throw Exception('BLE characteristics not found. Check ESP32 firmware.');
      }

      if (_devIdChar != null) {
        final idBytes = await _devIdChar!.read();
        _deviceId = String.fromCharCodes(idBytes).trim();
      }
      if (_deviceId.isEmpty) {
        _deviceId = device.remoteId.str.replaceAll(':', '').toLowerCase();
      }
      debugPrint('[BLE] Device ID: $_deviceId');

      setState(() { _connectedDevice = device; _isConnecting = false; _step = 2; });
      _scanWiFiNetworks();
      _showSnack('Connected: ${device.platformName}', AppColors.success);
    } catch (e) {
      if (mounted) { setState(() => _isConnecting = false); _showError('Connection error: $e'); }
    }
  }

  Future<void> _scanWiFiNetworks() async {
    try {
      if (_wifiListChar != null) {
        final value = await _wifiListChar!.read();
        final rawList = String.fromCharCodes(value);
        if (rawList.isNotEmpty) {
          final ssids = rawList.split(';').where((s) => s.isNotEmpty).toSet().toList();
          if (mounted) {
            setState(() {
              _wifiNetworks = ssids.map((ssid) => MyWiFiNetwork(
                ssid: ssid, level: -50, capabilities: 'WPA2'
              )).toList();
            });
          }
          return;
        }
      }

      final canScan = await WiFiScan.instance.canGetScannedResults();
      if (canScan != CanGetScannedResults.yes) return;

      await WiFiScan.instance.startScan();
      await Future.delayed(const Duration(seconds: 3));
      final networks = await WiFiScan.instance.getScannedResults();
      if (mounted) {
        setState(() {
          _wifiNetworks = networks
              .where((n) => n.ssid.isNotEmpty)
              .map((n) => MyWiFiNetwork(ssid: n.ssid, level: n.level, capabilities: n.capabilities))
              .toSet().toList()
            ..sort((a, b) => b.level.compareTo(a.level));
        });
      }
    } catch (e) {
      if (mounted) setState(() => _wifiNetworks = []);
    }
  }

  void _selectWiFi(MyWiFiNetwork network) {
    setState(() {
      _selectedSSID = network.ssid;
      _ssidCtrl.text = network.ssid;
      _step = 4;
    });
  }

  Future<void> _sendWiFiConfig() async {
    if (_ssidCtrl.text.isEmpty) { _showError('Please enter SSID'); return; }
    if (_ssidChar == null || _passChar == null) { _showError('BLE not connected'); return; }

    setState(() => _isConfiguring = true);
    try {
      await _ssidChar!.write(_ssidCtrl.text.codeUnits);
      await Future.delayed(const Duration(milliseconds: 500));
      await _passChar!.write(_passCtrl.text.codeUnits);
      _showSnack('Đã gửi! ESP32 đang kết nối WiFi...', AppColors.info);
      Future.delayed(const Duration(seconds: 20), () {
        if (mounted && _isConfiguring && _step != 5) {
          _onConnectedSuccessfully('unknown');
        }
      });
    } catch (e) {
      setState(() => _isConfiguring = false);
      _showError('Send error: $e');
    }
  }

  void _onConnectedSuccessfully(String ip) {
    if (!mounted) return;
    DeviceConfigService.instance.saveEsp32Ip(ip);
    _showSnack('ESP32 connected! IP: $ip', AppColors.success);
    _notifyAiServer(ip);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'deviceIP': ip,
          'deviceName': _connectedDevice?.platformName ?? 'ESP32Device',
          'wifiSSID': _selectedSSID ?? _ssidCtrl.text,
          'mac': _deviceId,
        });
      }
    });
  }

  void _notifyAiServer(String ip) {
    final url = '${AppConfig.aiBaseUrl}/config';
    http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'ip': ip, 'capture_port': 80}),
    ).then((_) {
      debugPrint('AI server notified: ESP32 IP = $ip');
    }).catchError((e) {
      debugPrint('AI server notify failed (offline?): $e');
    });
  }

  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _connectedDevice = null;
      _ssidChar = _passChar = _statusChar = null;
    }
  }

  void _showError(String msg) {
    if (mounted) _showSnack(msg, AppColors.error);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.card,
        foregroundColor: ac.textPrimary,
        title: Text('BLE WiFi Setup', style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: Icon(Icons.bluetooth_disabled_rounded, color: ac.textSecondary),
              onPressed: () async { await _disconnect(); setState(() { _step = 0; _wifiNetworks.clear(); _selectedSSID = null; }); },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepBar(ac),
            const SizedBox(height: 24),
            if (_step == 0) _buildScanView(ac),
            if (_step == 1) _buildConnectingView(ac),
            if (_step == 2) _buildWiFiListView(ac),
            if (_step == 3) _buildVerifyingView(ac),
            if (_step == 4) _buildPasswordView(ac),
            if (_step == 5) _buildDoneView(ac),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBar(AC ac) {
    const labels = ['Scan', 'Connect', 'WiFi', 'Verify', 'Config', 'Done'];
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(child: Container(height: 2, color: i ~/ 2 < _step ? ac.accent : ac.divider));
        }
        final stepIdx = i ~/ 2;
        final isDone = stepIdx < _step;
        final isActive = stepIdx == _step;
        return Column(
          children: [
            Container(
              width: 28, height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDone ? ac.accent : isActive ? ac.accentDim : ac.card,
                border: Border.all(color: isDone || isActive ? ac.accent : ac.border),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : Text('${stepIdx + 1}', style: TextStyle(color: isActive ? ac.accentLight : ac.iconMuted, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[stepIdx], style: TextStyle(color: isActive ? ac.accentLight : ac.textSecondary, fontSize: 9)),
          ],
        );
      }),
    );
  }

  Widget _buildScanView(AC ac) => Column(
    children: [
      if (_isScanning)
        _infoCard(ac, Icons.bluetooth_searching_rounded, 'Scanning...', 'Looking for ESP32 devices', AppColors.info, showProgress: true)
      else if (_scanResults.isEmpty)
        _infoCard(ac, Icons.bluetooth_disabled_rounded, 'No devices found', 'Make sure ESP32 is powered on\nand in pairing mode (LED blinking)', AppColors.warning,
          action: TextButton.icon(onPressed: _startScan, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Scan Again')),
        ),
      if (_scanResults.isNotEmpty) ...[
        const SizedBox(height: 8),
        ..._scanResults.map((r) => _deviceTile(ac, r)),
      ],
    ],
  );

  Widget _deviceTile(AC ac, ScanResult r) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: ac.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: ac.border)),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: ac.accentDim, borderRadius: BorderRadius.circular(10)), child: Icon(Icons.developer_board_rounded, color: ac.accentLight, size: 20)),
      title: Text(r.device.platformName.isEmpty ? 'Unknown Device' : r.device.platformName, style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.w600)),
      subtitle: Text('${r.rssi} dBm · ${_signalLabel(r.rssi)}', style: TextStyle(color: _signalColor(r.rssi), fontSize: 11)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: ac.iconMuted, size: 14),
      onTap: () => _connectToDevice(r.device),
    ),
  );

  Widget _buildConnectingView(AC ac) => _infoCard(ac, Icons.bluetooth_connected_rounded, 'Connecting...', 'Establishing BLE connection', AppColors.info, showProgress: true);

  Widget _buildWiFiListView(AC ac) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _infoCard(ac, Icons.check_circle_rounded, 'Connected: ${_connectedDevice?.platformName ?? ""}', 'Select a WiFi network for ESP32', AppColors.success),
      const SizedBox(height: 20),
      Text('Available Networks', style: TextStyle(color: ac.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (_wifiNetworks.isEmpty)
        _infoCard(
          ac, Icons.wifi_find_rounded,
          'Scanning WiFi...',
          'If no networks appear (e.g., on iOS), please enter manually below.',
          AppColors.warning,
          showProgress: true
        )
      else
        ..._wifiNetworks.take(12).map((n) => _wifiTile(ac, n)),
      const SizedBox(height: 12),
      _manualEntryTile(ac),
    ],
  );

  Widget _wifiTile(AC ac, MyWiFiNetwork n) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: ac.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: ac.border)),
    child: ListTile(
      leading: Icon(_wifiIcon(n.level), color: _signalColor(n.level), size: 22),
      title: Text(n.ssid, style: TextStyle(color: ac.textPrimary, fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text('${_signalLabel(n.level)} · ${_securityLabel(n.capabilities)}', style: TextStyle(color: ac.textSecondary, fontSize: 11)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: ac.iconMuted, size: 14),
      onTap: () => _selectWiFi(n),
    ),
  );

  Widget _manualEntryTile(AC ac) => Container(
    decoration: BoxDecoration(color: ac.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: ac.border)),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: ac.border, borderRadius: BorderRadius.circular(8)), child: Icon(Icons.more_horiz_rounded, color: ac.iconMuted, size: 18)),
      title: Text('Other...', style: TextStyle(color: ac.textSecondary, fontWeight: FontWeight.w500)),
      subtitle: Text('Enter network name manually', style: TextStyle(color: ac.textSecondary, fontSize: 11)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, color: ac.iconMuted, size: 14),
      onTap: () => setState(() { _selectedSSID = null; _ssidCtrl.clear(); _step = 4; }),
    ),
  );

  Widget _buildVerifyingView(AC ac) => Column(
    children: [
      _infoCard(ac, Icons.wifi_find_rounded, 'Verifying WiFi', 'Checking if ESP32 can see "$_selectedSSID"', AppColors.info, showProgress: true),
      const SizedBox(height: 12),
      TextButton(onPressed: () => setState(() => _step = 4), child: Text('Skip verification', style: TextStyle(color: ac.textSecondary))),
    ],
  );

  Widget _buildPasswordView(AC ac) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_selectedSSID != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: ac.accentDim, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Icon(Icons.wifi_rounded, color: ac.accentLight, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(_selectedSSID!, style: TextStyle(color: ac.accentLight, fontWeight: FontWeight.bold))),
              GestureDetector(onTap: () => setState(() => _step = 2), child: Text('Change', style: TextStyle(color: ac.textSecondary, fontSize: 12))),
            ],
          ),
        ),
      if (_selectedSSID == null)
        _textField(ac, _ssidCtrl, 'WiFi Name (SSID)', Icons.wifi_rounded),
      const SizedBox(height: 12),
      _textField(ac, _passCtrl, 'Password', Icons.lock_rounded, obscure: _obscurePass,
        suffix: IconButton(icon: Icon(_obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18), color: ac.textSecondary, onPressed: () => setState(() => _obscurePass = !_obscurePass)),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isConfiguring ? null : _sendWiFiConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: ac.accent,
            disabledBackgroundColor: ac.accentDim,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isConfiguring
              ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Connecting...', style: TextStyle(color: Colors.white)),
                ])
              : const Text('Connect to WiFi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
        ),
      ),
    ],
  );

  Widget _buildDoneView(AC ac) => _infoCard(
    ac, Icons.check_circle_rounded, 'Connected!', 'ESP32 IP: $_esp32IP\nClosing automatically...', AppColors.success,
  );

  Widget _infoCard(AC ac, IconData icon, String title, String subtitle, Color color, {bool showProgress = false, Widget? action}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14))),
              if (showProgress) const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: TextStyle(color: ac.textSecondary, fontSize: 12, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _textField(AC ac, TextEditingController ctrl, String label, IconData icon, {bool obscure = false, Widget? suffix}) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: TextStyle(color: ac.textPrimary),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: ac.textSecondary),
      prefixIcon: Icon(icon, color: ac.textSecondary, size: 18),
      suffixIcon: suffix,
      filled: true,
      fillColor: ac.card,
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: ac.border), borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: ac.accentLight), borderRadius: BorderRadius.circular(14)),
    ),
  );

  IconData _wifiIcon(int rssi) => rssi > -50 ? Icons.wifi_rounded : rssi > -70 ? Icons.wifi_2_bar_rounded : Icons.wifi_1_bar_rounded;
  Color _signalColor(int rssi) => rssi > -50 ? AppColors.success : rssi > -70 ? AppColors.warning : AppColors.error;
  String _signalLabel(int rssi) => rssi > -50 ? 'Strong' : rssi > -70 ? 'Good' : 'Weak';
  String _securityLabel(String cap) {
    if (cap.contains('WPA3')) return 'WPA3';
    if (cap.contains('WPA2')) return 'WPA2';
    if (cap.contains('WPA')) return 'WPA';
    return 'Open';
  }
}
