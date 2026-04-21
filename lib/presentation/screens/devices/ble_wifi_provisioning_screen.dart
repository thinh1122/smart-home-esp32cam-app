import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';

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

  // BLE UUIDs (must match ESP32 firmware)
  static const _serviceUUID   = '4fafc201-1fb5-459e-8fcc-c5c9c331914b';
  static const _ssidCharUUID  = 'beb5483e-36e1-4688-b7f5-ea07361b26a8';
  static const _passCharUUID  = '1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e';
  static const _statusCharUUID = 'd8de624e-140f-4a22-8594-e2216b84a5f2';
  static const _wifiListCharUUID = '2b8c9e50-7182-4f32-8414-b49911e0eb7e';

  // State
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConfiguring = false;
  bool _obscurePass = true;
  int _step = 0; // 0: Scan, 1: Connecting, 2: WiFi list, 3: Verifying, 4: Password, 5: Done

  List<ScanResult> _scanResults = [];
  List<MyWiFiNetwork> _wifiNetworks = [];
  String? _selectedSSID;
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ssidChar, _passChar, _statusChar, _wifiListChar;
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
      // Chờ tối đa 5 giây để Bluetooth chuyển sang trạng thái ON
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
    // Kiểm tra state lần nữa trước khi scan (hỗ trợ nút Scan Again)
    if (await FlutterBluePlus.adapterState.first != BluetoothAdapterState.on) {
      _showError('Bluetooth is not ON. Cannot scan.');
      return;
    }

    setState(() { _isScanning = true; _step = 0; _scanResults.clear(); });
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
          if (uuid == _ssidCharUUID.toLowerCase()) _ssidChar = char;
          if (uuid == _passCharUUID.toLowerCase()) _passChar = char;
          if (uuid == _wifiListCharUUID.toLowerCase()) _wifiListChar = char;
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
                _showError('WiFi connection failed.\nCheck SSID and password.');
              }
            });
          }
        }
      }

      if (_ssidChar == null || _passChar == null || _statusChar == null) {
        throw Exception('BLE characteristics not found. Check ESP32 firmware.');
      }

      setState(() { _connectedDevice = device; _isConnecting = false; _step = 2; });
      _scanWiFiNetworks();
      _showSnack('Connected: ${device.platformName}', AppColors.success);
    } catch (e) {
      if (mounted) { setState(() => _isConnecting = false); _showError('Connection error: $e'); }
    }
  }

  Future<void> _scanWiFiNetworks() async {
    try {
      // 1. Dùng danh sách WiFi do ESP32 tự quét và gửi qua BLE (Tương thích 100% Android + iOS)
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
          return; // Nếu đọc được thì dừng, không cần quét bằng điện thoại nữa
        }
      }

      // 2. Fallback: Nếu ESP32 chưa có FW mới, dùng thư viện điện thoại quét
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

  // ── Select WiFi and verify with ESP32 ────────────────────────────────────
  void _selectWiFi(MyWiFiNetwork network) {
    setState(() {
      _selectedSSID = network.ssid;
      _ssidCtrl.text = network.ssid;
      _step = 3;
    });
    _verifyWiFiWithESP32(network.ssid);
  }

  // Send SSID to ESP32 to verify it can see this network
  Future<void> _verifyWiFiWithESP32(String ssid) async {
    try {
      if (_ssidChar == null) { _proceedToPassword(); return; }
      // Write SSID with a "verify:" prefix so ESP32 scans its WiFi list
      await _ssidChar!.write('verify:$ssid'.codeUnits);
      // Wait up to 6s for ESP32 to confirm; then proceed to password step regardless
      await Future.delayed(const Duration(seconds: 5));
      if (mounted && _step == 3) _proceedToPassword();
    } catch (_) {
      if (mounted) _proceedToPassword();
    }
  }

  void _proceedToPassword() => setState(() => _step = 4);

  // ── Send WiFi config to ESP32 ─────────────────────────────────────────────
  Future<void> _sendWiFiConfig() async {
    if (_ssidCtrl.text.isEmpty) { _showError('Please enter SSID'); return; }
    if (_ssidChar == null || _passChar == null) { _showError('BLE not connected'); return; }

    setState(() => _isConfiguring = true);
    try {
      await _ssidChar!.write(_ssidCtrl.text.codeUnits);
      await Future.delayed(const Duration(milliseconds: 500));
      await _passChar!.write(_passCtrl.text.codeUnits);
      _showSnack('Config sent! ESP32 connecting to WiFi...', AppColors.info);
      // ESP32 will notify via _statusSub when connected
    } catch (e) {
      setState(() => _isConfiguring = false);
      _showError('Send error: $e');
    }
  }

  void _onConnectedSuccessfully(String ip) {
    if (!mounted) return;
    _showSnack('ESP32 connected! IP: $ip', AppColors.success);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        Navigator.pop(context, {
          'success': true,
          'deviceIP': ip,
          'deviceName': _connectedDevice?.platformName ?? 'ESP32CAM',
          'wifiSSID': _selectedSSID ?? _ssidCtrl.text,
        });
      }
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

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        foregroundColor: Colors.white,
        title: const Text('BLE WiFi Setup', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        elevation: 0,
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled_rounded, color: AppColors.textSecondary),
              onPressed: () async { await _disconnect(); setState(() { _step = 0; _wifiNetworks.clear(); _selectedSSID = null; }); },
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStepBar(),
            const SizedBox(height: 24),
            if (_step == 0) _buildScanView(),
            if (_step == 1) _buildConnectingView(),
            if (_step == 2) _buildWiFiListView(),
            if (_step == 3) _buildVerifyingView(),
            if (_step == 4) _buildPasswordView(),
            if (_step == 5) _buildDoneView(),
          ],
        ),
      ),
    );
  }

  Widget _buildStepBar() {
    const labels = ['Scan', 'Connect', 'WiFi', 'Verify', 'Config', 'Done'];
    return Row(
      children: List.generate(labels.length * 2 - 1, (i) {
        if (i.isOdd) {
          return Expanded(child: Container(height: 2, color: i ~/ 2 < _step ? AppColors.accent : Colors.white12));
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
                color: isDone ? AppColors.accent : isActive ? AppColors.accentDim : AppColors.card,
                border: Border.all(color: isDone || isActive ? AppColors.accent : Colors.white24),
              ),
              child: Center(
                child: isDone
                    ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                    : Text('${stepIdx + 1}', style: TextStyle(color: isActive ? AppColors.accentLight : Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(height: 4),
            Text(labels[stepIdx], style: TextStyle(color: isActive ? AppColors.accentLight : AppColors.textSecondary, fontSize: 9)),
          ],
        );
      }),
    );
  }

  Widget _buildScanView() => Column(
    children: [
      if (_isScanning)
        _infoCard(Icons.bluetooth_searching_rounded, 'Scanning...', 'Looking for ESP32 devices', AppColors.info, showProgress: true)
      else if (_scanResults.isEmpty)
        _infoCard(Icons.bluetooth_disabled_rounded, 'No devices found', 'Make sure ESP32 is powered on\nand in pairing mode (LED blinking)', AppColors.warning,
          action: TextButton.icon(onPressed: _startScan, icon: const Icon(Icons.refresh_rounded, size: 16), label: const Text('Scan Again')),
        ),
      if (_scanResults.isNotEmpty) ...[
        const SizedBox(height: 8),
        ..._scanResults.map((r) => _deviceTile(r)),
      ],
    ],
  );

  Widget _deviceTile(ScanResult r) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.white10)),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.developer_board_rounded, color: AppColors.accentLight, size: 20)),
      title: Text(r.device.platformName.isEmpty ? 'Unknown Device' : r.device.platformName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text('${r.rssi} dBm · ${_signalLabel(r.rssi)}', style: TextStyle(color: _signalColor(r.rssi), fontSize: 11)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
      onTap: () => _connectToDevice(r.device),
    ),
  );

  Widget _buildConnectingView() => _infoCard(Icons.bluetooth_connected_rounded, 'Connecting...', 'Establishing BLE connection', AppColors.info, showProgress: true);

  Widget _buildWiFiListView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _infoCard(Icons.check_circle_rounded, 'Connected: ${_connectedDevice?.platformName ?? ""}', 'Select a WiFi network for ESP32', AppColors.success),
      const SizedBox(height: 20),
      const Text('Available Networks', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      if (_wifiNetworks.isEmpty)
        _infoCard(
          Icons.wifi_find_rounded, 
          'Scanning WiFi...', 
          'If no networks appear (e.g., on iOS), please enter manually below.', 
          AppColors.warning, 
          showProgress: true
        )
      else
        ..._wifiNetworks.take(12).map(_wifiTile),
      const SizedBox(height: 12),
      _manualEntryTile(),
    ],
  );

  Widget _wifiTile(MyWiFiNetwork n) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
    child: ListTile(
      leading: Icon(_wifiIcon(n.level), color: _signalColor(n.level), size: 22),
      title: Text(n.ssid, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14)),
      subtitle: Text('${_signalLabel(n.level)} · ${_securityLabel(n.capabilities)}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
      onTap: () => _selectWiFi(n),
    ),
  );

  Widget _manualEntryTile() => Container(
    decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
    child: ListTile(
      leading: Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.more_horiz_rounded, color: Colors.white60, size: 18)),
      title: const Text('Other...', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
      subtitle: const Text('Enter network name manually', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white38, size: 14),
      onTap: () => setState(() { _selectedSSID = null; _ssidCtrl.clear(); _step = 4; }),
    ),
  );

  Widget _buildVerifyingView() => Column(
    children: [
      _infoCard(Icons.wifi_find_rounded, 'Verifying WiFi', 'Checking if ESP32 can see "$_selectedSSID"', AppColors.info, showProgress: true),
      const SizedBox(height: 12),
      TextButton(onPressed: _proceedToPassword, child: const Text('Skip verification', style: TextStyle(color: AppColors.textSecondary))),
    ],
  );

  Widget _buildPasswordView() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (_selectedSSID != null)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(Icons.wifi_rounded, color: AppColors.accentLight, size: 18),
              const SizedBox(width: 10),
              Expanded(child: Text(_selectedSSID!, style: const TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.bold))),
              GestureDetector(onTap: () => setState(() => _step = 2), child: const Text('Change', style: TextStyle(color: AppColors.textSecondary, fontSize: 12))),
            ],
          ),
        ),
      if (_selectedSSID == null)
        _textField(_ssidCtrl, 'WiFi Name (SSID)', Icons.wifi_rounded),
      const SizedBox(height: 12),
      _textField(_passCtrl, 'Password', Icons.lock_rounded, obscure: _obscurePass,
        suffix: IconButton(icon: Icon(_obscurePass ? Icons.visibility_rounded : Icons.visibility_off_rounded, size: 18), color: AppColors.textSecondary, onPressed: () => setState(() => _obscurePass = !_obscurePass)),
      ),
      const SizedBox(height: 24),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isConfiguring ? null : _sendWiFiConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            disabledBackgroundColor: AppColors.accentDim,
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

  Widget _buildDoneView() => _infoCard(
    Icons.check_circle_rounded, 'Connected!', 'ESP32 IP: $_esp32IP\nClosing automatically...', AppColors.success,
  );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _infoCard(IconData icon, String title, String subtitle, Color color, {bool showProgress = false, Widget? action}) {
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
          Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, IconData icon, {bool obscure = false, Widget? suffix}) => TextField(
    controller: ctrl,
    obscureText: obscure,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.card,
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.accentLight), borderRadius: BorderRadius.circular(14)),
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
