import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:wifi_scan/wifi_scan.dart'; // ⭐ THÊM MỚI
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
  int _currentStep = 0; // 0: Scan, 1: Connect, 2: WiFi List, 3: Verify WiFi, 4: Password, 5: Done
  bool _isVerifyingWiFi = false; // ⭐ THÊM MỚI - Đang verify WiFi với ESP32
  
  List<ScanResult> _scanResults = [];
  List<WiFiAccessPoint> _wifiNetworks = []; // ⭐ THAY ĐỔI - Dùng WiFiAccessPoint
  String? _selectedSSID; // ⭐ THÊM MỚI - WiFi đã chọn
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
                    _currentStep = 5; // Step 5 là Done
                  });
                  
                  // ⭐ THAY ĐỔI - Tự động đóng sau 2s
                  _showSuccessAndClose(ip);
                } else if (status == "failed") {
                  _showError("WiFi connection failed!\nCheck SSID and Password");
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
        _currentStep = 2; // ⭐ THAY ĐỔI - Chuyển đến WiFi list
      });
      
      // ⭐ THÊM MỚI - Scan WiFi networks
      _scanWiFiNetworks();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Connected: ${device.platformName}'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      setState(() => _isConnecting = false);
      _showError("Lỗi kết nối: $e");
    }
  }
  
  // ⭐ THAY ĐỔI - Scan WiFi từ điện thoại (TỐI ƯU)
  Future<void> _scanWiFiNetworks() async {
    try {
      // Kiểm tra quyền WiFi
      final canScan = await WiFiScan.instance.canGetScannedResults();
      if (canScan != CanGetScannedResults.yes) {
        _showError("WiFi scan permission denied");
        return;
      }
      
      // Scan WiFi networks từ điện thoại
      await WiFiScan.instance.startScan();
      await Future.delayed(const Duration(seconds: 3)); // Đợi scan xong
      
      final networks = await WiFiScan.instance.getScannedResults();
      
      setState(() {
        // Lọc và sắp xếp theo signal strength
        _wifiNetworks = networks
            .where((network) => network.ssid.isNotEmpty) // Bỏ SSID trống
            .toSet() // Loại bỏ duplicate
            .toList()
          ..sort((a, b) => b.level.compareTo(a.level)); // Sắp xếp theo signal
      });
      
    } catch (e) {
      _showError("WiFi scan failed: $e");
      setState(() => _wifiNetworks = []);
    }
  }
  
  // ⭐ THAY ĐỔI - Chọn WiFi và verify với ESP32
  void _selectWiFi(WiFiAccessPoint network) async {
    setState(() {
      _selectedSSID = network.ssid;
      _ssidController.text = network.ssid;
      _currentStep = 3; // Chuyển đến verify WiFi
      _isVerifyingWiFi = true;
    });
    
    // Verify WiFi với ESP32
    await _verifyWiFiWithESP32(network.ssid);
  }
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
        _wifiNetworks.clear(); // ⭐ THÊM MỚI
        _selectedSSID = null; // ⭐ THÊM MỚI
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
  
  // ⭐ THAY ĐỔI - Hiển thị thành công và tự động đóng sau 2s
  void _showSuccessAndClose(String ip) {
    if (mounted) {
      // Hiển thị snackbar thành công
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('✅ Connection Successful!', style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('Device IP: $ip'),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      
      // Tự động đóng màn hình sau 2s
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.pop(context, {
            'success': true,
            'deviceIP': ip,
            'deviceName': _connectedDevice?.platformName ?? 'ESP32CAM',
            'wifiSSID': _selectedSSID ?? _ssidController.text,
          });
        }
      });
    }
  }
  
  // ⭐ GIỮ LẠI - Dialog cũ cho trường hợp cần thiết
  void _showSuccessDialog(String ip) {
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('✅ Success!'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ESP32-CAM connected to WiFi!'),
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
  
  // ⭐ QR Code Scanner - Sẽ implement thật sau
  Future<void> _scanQRCode() async {
    try {
      // TODO: Implement real QR scanner
      // Mở màn hình QR scanner thật
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('QR Scanner will be implemented'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      _showError("QR Scanner error: $e");
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
        title: const Text('Add Device'),
        backgroundColor: Colors.deepPurple,
        actions: [
          if (_connectedDevice != null)
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Content dựa theo step
            if (_currentStep == 0) _buildScanView(),
            if (_currentStep == 1) _buildConnectingView(),
            if (_currentStep == 2) _buildWiFiListView(),
            if (_currentStep == 3) _buildVerifyingView(), // ⭐ THÊM MỚI
            if (_currentStep == 4) _buildPasswordView(), // ⭐ THAY ĐỔI
            if (_currentStep == 5) _buildDoneView(), // ⭐ THAY ĐỔI
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
        // Scanning status
        if (_isScanning)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Scanning for devices...'),
                ],
              ),
            ),
          )
        else if (_scanResults.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('No devices found'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _startScan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Scan Again'),
                  ),
                ],
              ),
            ),
          ),
        
        // Device list
        if (_scanResults.isNotEmpty) ...[
          const SizedBox(height: 16),
          ..._scanResults.map((result) {
            return Card(
              child: ListTile(
                leading: const Icon(Icons.bluetooth, color: Colors.blue, size: 32),
                title: Text(result.device.platformName),
                subtitle: Text('${_getSignalIcon(result.rssi)} ${result.rssi} dBm'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _connectToDevice(result.device),
              ),
            );
          }).toList(),
        ],
        
        // QR Code option
        const SizedBox(height: 24),
        Card(
          color: Colors.orange.shade50,
          child: InkWell(
            onTap: _scanQRCode,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.qr_code_scanner, color: Colors.orange, size: 32),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Scan QR Code', style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Connect using QR code', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, size: 16),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildConnectingView() {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Connecting...'),
          ],
        ),
      ),
    );
  }
  
  // ⭐ THÊM MỚI - WiFi List View
  Widget _buildWiFiListView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 12),
                Text(_connectedDevice != null 
                  ? 'Connected: ${_connectedDevice?.platformName ?? ''}' 
                  : 'Connected via QR Code'), // ⭐ THAY ĐỔI - Hỗ trợ QR
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Select WiFi Network:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        
        if (_wifiNetworks.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 16),
                  Text('Scanning WiFi networks...'),
                ],
              ),
            ),
          )
        else
          ..._wifiNetworks.map((network) {
            return Card(
              child: ListTile(
                leading: Icon(
                  _getWiFiIcon(network.level), 
                  color: _getSignalColor(network.level),
                ),
                title: Text(network.ssid),
                subtitle: Text('${_getSignalStrength(network.level)} • ${_getSecurityType(network.capabilities)}'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () => _selectWiFi(network),
              ),
            );
          }).toList(),
        
        const SizedBox(height: 16),
        
        // Manual input option - THAY ĐỔI thành "Other..."
        Card(
          color: Colors.grey.shade50,
          child: ListTile(
            leading: const Icon(Icons.more_horiz, color: Colors.grey),
            title: const Text('Other...'),
            subtitle: const Text('Enter WiFi name and password manually'),
            trailing: const Icon(Icons.arrow_forward_ios),
            onTap: () {
              setState(() {
                _selectedSSID = null; // ⭐ Đánh dấu là manual input
                _currentStep = 4; // ⭐ THAY ĐỔI - Thẳng đến password (bỏ qua verify)
                _ssidController.clear();
                _passwordController.clear();
              });
            },
          ),
        ),
      ],
    );
  }
  
  // ⭐ THÊM MỚI - Verifying WiFi View
  Widget _buildVerifyingView() {
    return Column(
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.wifi_find, color: Colors.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Verifying WiFi', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                      Text('Checking if ESP32 can see "$_selectedSSID"'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text('ESP32 is scanning for "$_selectedSSID"...'),
                const SizedBox(height: 8),
                const Text(
                  'This ensures ESP32 can connect to the selected network',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
  
  // ⭐ THAY ĐỔI - Password View (tách riêng từ buildConfigView)
  Widget _buildPasswordView() {
    bool isManualInput = _selectedSSID == null && _ssidController.text.isEmpty;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hiển thị WiFi đã chọn (nếu có)
        if (_selectedSSID != null) ...[
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.wifi, color: Colors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Selected Network', style: TextStyle(color: Colors.blue.shade800, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            // ⭐ THÊM MỚI - Hiển thị connection method
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _connectedDevice != null ? Colors.blue.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _connectedDevice != null ? 'BLE' : 'QR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _connectedDevice != null ? Colors.blue.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        Text(_selectedSSID!),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 2),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Enter Password:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ] else ...[
          // Manual input mode
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Manual Input', style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            // ⭐ THÊM MỚI - Hiển thị connection method
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _connectedDevice != null ? Colors.blue.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                _connectedDevice != null ? 'BLE' : 'QR',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _connectedDevice != null ? Colors.blue.shade700 : Colors.orange.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Text('Enter WiFi details manually'),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _currentStep = 2),
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('WiFi Configuration:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
        
        const SizedBox(height: 16),
        
        // SSID input (chỉ hiện khi manual input)
        if (_selectedSSID == null) ...[
          TextField(
            controller: _ssidController,
            decoration: const InputDecoration(
              labelText: 'WiFi Name (SSID)',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.wifi),
              hintText: 'Enter WiFi network name',
            ),
          ),
          const SizedBox(height: 16),
        ],
        
        // Password input (luôn hiện)
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock),
            hintText: _selectedSSID != null ? 'Enter WiFi password' : 'Enter WiFi password',
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
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
                      Text('Connecting...'),
                    ],
                  )
                : const Text('Connect to WiFi'),
          ),
        ),
      ],
    );
  }
  
  // ⭐ THAY ĐỔI - Helper functions cho WiFi thật từ điện thoại
  IconData _getWiFiIcon(int level) {
    if (level > -50) return Icons.wifi;
    if (level > -70) return Icons.wifi_2_bar;
    return Icons.wifi_1_bar;
  }
  
  Color _getSignalColor(int level) {
    if (level > -50) return Colors.green;
    if (level > -70) return Colors.orange;
    return Colors.red;
  }
  
  String _getSignalStrength(int level) {
    if (level > -50) return 'Strong';
    if (level > -70) return 'Good';
    return 'Weak';
  }
  
  String _getSecurityType(String capabilities) {
    if (capabilities.contains('WPA3')) return 'WPA3';
    if (capabilities.contains('WPA2')) return 'WPA2';
    if (capabilities.contains('WPA')) return 'WPA';
    if (capabilities.contains('WEP')) return 'WEP';
    return 'Open';
  }
  
  Widget _buildDoneView() {
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.check_circle, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            const Text('Connection Successful!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text('Device IP: $_esp32IP'),
            const SizedBox(height: 16),
            const Text(
              'Closing automatically...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
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
