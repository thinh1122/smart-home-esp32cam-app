import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:async';

class BLEWiFiProvisioningScreen extends StatefulWidget {
  const BLEWiFiProvisioningScreen({Key? key}) : super(key: key);

  @override
  State<BLEWiFiProvisioningScreen> createState() => _BLEWiFiProvisioningScreenState();
}

class _BLEWiFiProvisioningScreenState extends State<BLEWiFiProvisioningScreen> {
  final _ssidController = TextEditingController();
  final _passwordController = TextEditingController();
  
  // BLE UUIDs (phải khớp với ESP32)
  final String serviceUUID = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String ssidCharUUID = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  final String passCharUUID = "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e";
  final String statusCharUUID = "d8de624e-140f-4a22-8594-e2216b84a5f2";
  
  bool _isScanning = false;
  bool _isConnecting = false;
  bool _isConfiguring = false;
  bool _obscurePassword = true;
  int _currentStep = 0; // 0: Scan, 1: Connect, 2: Config, 3: Done
  
  List<ScanResult> _scanResults = [];
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _ssidChar;
  BluetoothCharacteristic? _passChar;
  BluetoothCharacteristic? _statusChar;
  String? _esp32IP;
  
  StreamSubscription? _scanSubscription;
  StreamSubscription? _statusSubscription;
  
  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }
  
  Future<void> _checkBluetooth() async {
    // Kiểm tra Bluetooth có bật không
    if (await FlutterBluePlus.isSupported == false) {
      _showError("Thiết bị không hỗ trợ Bluetooth");
      return;
    }
    
    // Kiểm tra quyền
    var state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      _showError("Vui lòng bật Bluetooth");
      return;
    }
    
    // Tự động scan
    _startScan();
  }
  
  // Scan BLE devices
  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _currentStep = 0;
      _scanResults.clear();
    });
    
    try {
      // Stop previous scan
      await FlutterBluePlus.stopScan();
      
      // Start scan
      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        setState(() {
          // Chỉ lấy ESP32CAM devices
          _scanResults = results.where((r) => 
            r.device.platformName.startsWith('ESP32CAM')
          ).toList();
        });
      });
      
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
        androidUsesFineLocation: true,
      );
      
      // Đợi 10 giây
      await Future.delayed(const Duration(seconds: 10));
      await FlutterBluePlus.stopScan();
      
      setState(() => _isScanning = false);
      
      if (_scanResults.isEmpty) {
        _showError("Không tìm thấy ESP32-CAM\nĐảm bảo ESP32 đã bật và chưa kết nối WiFi");
      }
    } catch (e) {
      setState(() => _isScanning = false);
      _showError("Lỗi scan: $e");
    }
  }
  
  // Connect to ESP32
  Future<void> _connectToDevice(BluetoothDevice device) async {
    setState(() {
      _isConnecting = true;
      _currentStep = 1;
    });
    
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      
      // Discover services
      List<BluetoothService> services = await device.discoverServices();
      
      // Tìm service và characteristics
      for (var service in services) {
        if (service.uuid.toString().toLowerCase() == serviceUUID.toLowerCase()) {
          for (var char in service.characteristics) {
            String charUUID = char.uuid.toString().toLowerCase();
            
            if (charUUID == ssidCharUUID.toLowerCase()) {
              _ssidChar = char;
            } else if (charUUID == passCharUUID.toLowerCase()) {
              _passChar = char;
            } else if (charUUID == statusCharUUID.toLowerCase()) {
              _statusChar = char;
              
              // Subscribe to status notifications
              await char.setNotifyValue(true);
              _statusSubscription = char.lastValueStream.listen((value) {
                String status = String.fromCharCodes(value);
                debugPrint("📥 Status: $status");
                
                if (status.startsWith("connected|")) {
                  String ip = status.split("|")[1];
                  setState(() {
                    _esp32IP = ip;
                    _currentStep = 3;
                  });
                  _showSuccessDialog(ip);
                } else if (status == "failed") {
                  _showError("Kết nối WiFi thất bại!\nKiểm tra SSID và Password");
                }
              });
            }
          }
        }
      }
      
      if (_ssidChar == null || _passChar == null || _statusChar == null) {
        throw Exception("Không tìm thấy BLE characteristics");
      }
      
      setState(() {
        _connectedDevice = device;
        _isConnecting = false;
        _currentStep = 2;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Đã kết nối: ${device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isConnecting = false);
      _showError("Lỗi kết nối: $e");
    }
  }
  
  // Send WiFi config via BLE
  Future<void> _sendWiFiConfig() async {
    if (_ssidController.text.isEmpty) {
      _showError("Vui lòng nhập SSID");
      return;
    }
    
    if (_ssidChar == null || _passChar == null) {
      _showError("Chưa kết nối BLE");
      return;
    }
    
    setState(() => _isConfiguring = true);
    
    try {
      // Gửi SSID
      await _ssidChar!.write(_ssidController.text.codeUnits);
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Gửi Password
      await _passChar!.write(_passwordController.text.codeUnits);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Đã gửi cấu hình!\nESP32 đang kết nối WiFi...'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }
      
      // Đợi notification từ ESP32
      // (sẽ nhận qua _statusSubscription)
      
    } catch (e) {
      setState(() => _isConfiguring = false);
      _showError("Lỗi gửi config: $e");
    }
  }
  
  // Disconnect BLE
  Future<void> _disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      setState(() {
        _connectedDevice = null;
        _ssidChar = null;
        _passChar = null;
        _statusChar = null;
        _currentStep = 0;
      });
    }
  }
  
  // Helper functions
  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }
  
  void _showSuccessDialog(String ip) {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('✅ Thành công!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ESP32-CAM đã kết nối WiFi!'),
              const SizedBox(height: 12),
              Text('IP: $ip', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pop(context, ip);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }
  
  String _getSignalIcon(int rssi) {
    if (rssi > -60) return '📶';
    if (rssi > -70) return '📡';
    return '📡';
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE WiFi Provisioning'),
        backgroundColor: Colors.deepPurple,
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
              tooltip: 'Ngắt kết nối',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Step Indicator
            _buildStepIndicator(),
            
            const SizedBox(height: 24),
            
            // Content
            if (_currentStep == 0) _buildScanView(),
            if (_currentStep == 1) _buildConnectingView(),
            if (_currentStep == 2) _buildConfigView(),
            if (_currentStep == 3) _buildDoneView(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStepIndicator() {
    return Row(
      children: [
        _buildStep(0, 'Scan', _currentStep >= 0),
        _buildStepLine(_currentStep >= 1),
        _buildStep(1, 'Kết nối', _currentStep >= 1),
        _buildStepLine(_currentStep >= 2),
        _buildStep(2, 'Cấu hình', _currentStep >= 2),
        _buildStepLine(_currentStep >= 3),
        _buildStep(3, 'Hoàn tất', _currentStep >= 3),
      ],
    );
  }
  
  Widget _buildStep(int step, String label, bool active) {
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active ? Colors.deepPurple : Colors.grey.shade300,
            ),
            child: Center(
              child: Text(
                '${step + 1}',
                style: TextStyle(
                  color: active ? Colors.white : Colors.grey.shade600,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: active ? Colors.deepPurple : Colors.grey.shade600,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStepLine(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        color: active ? Colors.deepPurple : Colors.grey.shade300,
      ),
    );
  }
  
  Widget _buildScanView() {
    return Column(
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Icon(Icons.bluetooth_searching, size: 48, color: Colors.blue.shade700),
                const SizedBox(height: 12),
                const Text(
                  'Đang quét thiết bị Bluetooth...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text('Đảm bảo ESP32-CAM đã bật và chưa kết nối WiFi'),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 16),
        
        if (_isScanning)
          const Center(child: CircularProgressIndicator())
        else if (_scanResults.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('Không tìm thấy ESP32-CAM'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Quét lại'),
                  ),
                ],
              ),
            ),
          )
        else
          ..._scanResults.map((result) {
            return Card(
              child: ListTile(
                leading: Icon(Icons.bluetooth, color: Colors.blue.shade700, size: 32),
                title: Text(
                  result.device.platformName,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('${_getSignalIcon(result.rssi)} ${result.rssi} dBm'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _connectToDevice(result.device),
              ),
            );
          }).toList(),
      ],
    );
  }
  
  Widget _buildConnectingView() {
    return Card(
      color: Colors.blue.shade50,
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Đang kết nối BLE...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
  
  Widget _buildConfigView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Đã kết nối BLE', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text(_connectedDevice?.platformName ?? ''),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Nhập WiFi nhà:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        TextField(
          controller: _ssidController,
          decoration: const InputDecoration(
            labelText: 'Tên WiFi (SSID)',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.wifi),
          ),
        ),
        
        const SizedBox(height: 16),
        
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Mật khẩu',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        ElevatedButton(
          onPressed: _isConfiguring ? null : _sendWiFiConfig,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.deepPurple,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: _isConfiguring
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                    SizedBox(width: 12),
                    Text('Đang gửi...'),
                  ],
                )
              : const Text('Gửi cấu hình', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }
  
  Widget _buildDoneView() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.check_circle, size: 64, color: Colors.green.shade700),
            const SizedBox(height: 16),
            const Text('Hoàn tất!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('IP: $_esp32IP'),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _scanSubscription?.cancel();
    _statusSubscription?.cancel();
    _ssidController.dispose();
    _passwordController.dispose();
    _disconnect();
    super.dispose();
  }
}
