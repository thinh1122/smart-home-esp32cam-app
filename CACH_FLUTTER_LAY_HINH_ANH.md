# 📱 CÁCH FLUTTER LẤY HÌNH ẢNH TỪ ESP32-CAM

## 🎯 TỔNG QUAN

Flutter **KHÔNG** lấy hình ảnh trực tiếp từ ESP32-CAM!  
Thay vào đó, Flutter lấy từ **Python AI Server** (relay).

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│  ESP32-CAM  │─────>│ Python Relay │─────>│ Flutter App │
│  (1 stream) │ WiFi │ (broadcast)  │ HTTP │ (display)   │
└─────────────┘      └──────────────┘      └─────────────┘
     :81/stream          :5000/stream         Mjpeg widget
```

**Lý do:**
- ESP32-CAM chỉ chịu **1 kết nối stream** duy nhất
- Python relay kéo 1 stream từ ESP32, broadcast cho nhiều client
- Flutter, browser, app khác đều lấy từ Python relay

---

## 🔄 FLOW HOẠT ĐỘNG CHI TIẾT

### Bước 1: Cấu hình IP Python Server

```dart
// File: lib/core/services/device_config_service.dart
class DeviceConfigService {
  String _aiIp = '';      // IP máy tính chạy Python
  int _aiPort = 5000;     // Port Python server
  
  // Lưu vào SharedPreferences
  Future<void> saveAiServer(String ip, {int port = 5000}) async {
    _aiIp = ip;
    _aiPort = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_server_ip', ip);
    await prefs.setInt('ai_server_port', port);
  }
  
  // Tạo URL stream
  String get aiBaseUrl => 'http://$_aiIp:$_aiPort';
}
```

**User cấu hình:**
1. Vào Settings → AI Server Configuration
2. Nhập IP máy tính (VD: `192.168.1.100`)
3. Port: `5000`
4. Bấm Save

### Bước 2: Tạo Stream URL

```dart
// File: lib/core/config/app_config.dart
class AppConfig {
  // Lấy IP từ DeviceConfigService
  static String get aiBaseUrl => 
    DeviceConfigService.instance.aiBaseUrl;
  
  // Stream URL = Python relay URL
  static String get streamUrl => 
    hasAiServer ? '$aiBaseUrl/stream' : '';
  
  // VD: http://192.168.1.100:5000/stream
}
```

### Bước 3: Hiển thị Stream trong Flutter

```dart
// File: lib/presentation/screens/camera/front_door_cam_screen.dart
Widget _buildCameraFeed() {
  return Mjpeg(
    key: _streamKey,           // Unique key để force rebuild
    isLive: true,              // Live stream mode
    stream: AppConfig.streamUrl, // Python relay URL
    error: (ctx, err, stack) {
      // Xử lý lỗi khi stream offline
      return _buildStreamError();
    },
  );
}
```

---

## 📦 THƯ VIỆN MJPEG

### Package: flutter_mjpeg

```yaml
# pubspec.yaml
dependencies:
  flutter_mjpeg: ^2.0.4
```

### Cách hoạt động

```dart
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

Mjpeg(
  isLive: true,
  stream: 'http://192.168.1.100:5000/stream',
  error: (context, error, stackTrace) {
    return Center(child: Text('Stream offline'));
  },
)
```

**Bên trong flutter_mjpeg:**
1. Mở HTTP connection đến URL
2. Đọc multipart/x-mixed-replace response
3. Parse JPEG boundaries
4. Decode JPEG thành Image
5. Render lên Canvas
6. Lặp lại cho frame tiếp theo

---

## 🔍 CHI TIẾT MJPEG PROTOCOL

### HTTP Request
```http
GET /stream HTTP/1.1
Host: 192.168.1.100:5000
Connection: keep-alive
```

### HTTP Response
```http
HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace;boundary=frame
Cache-Control: no-cache

--frame
Content-Type: image/jpeg
Content-Length: 15234

[JPEG binary data 15234 bytes]
--frame
Content-Type: image/jpeg
Content-Length: 15678

[JPEG binary data 15678 bytes]
--frame
...
```

### Flutter Parse Flow
```
HTTP Stream
    │
    ▼
┌─────────────────┐
│ Read chunk      │
│ (4096 bytes)    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Find boundary   │
│ "--frame"       │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Extract JPEG    │
│ (between        │
│  boundaries)    │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Decode JPEG     │
│ → Image         │
└─────────────────┘
    │
    ▼
┌─────────────────┐
│ Render on       │
│ Canvas          │
└─────────────────┘
    │
    └──> Repeat
```

---

## 🎨 UI IMPLEMENTATION

### Camera Feed Widget

```dart
Widget _buildCameraFeed() {
  return ClipRRect(
    borderRadius: BorderRadius.circular(28),
    child: Container(
      height: 240,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. MJPEG Stream (background)
          if (AppConfig.streamUrl.isNotEmpty)
            Mjpeg(
              key: _streamKey,
              isLive: true,
              stream: AppConfig.streamUrl,
              error: (ctx, err, stack) => _buildStreamError(),
            ),
          
          // 2. Corner marks (overlay)
          Positioned(top: 14, left: 14, 
            child: _cornerMark(top: true, left: true)),
          
          // 3. Info pills (overlay)
          Positioned(
            top: 36, left: 36,
            child: _glassPill(Icons.wifi_rounded, 
              'Relay Connected', AppColors.info),
          ),
          
          // 4. Face recognition overlay
          if (_recognizedFaces.isNotEmpty)
            Positioned(
              bottom: 14, left: 14, right: 14,
              child: _buildFaceOverlay(),
            ),
        ],
      ),
    ),
  );
}
```

### Stream Key (Force Rebuild)

```dart
Key _streamKey = UniqueKey();

void _reconnectStream() {
  setState(() {
    _streamKey = UniqueKey();  // Tạo key mới
    // → Flutter rebuild Mjpeg widget
    // → Đóng connection cũ, mở connection mới
  });
}
```

**Khi nào cần reconnect?**
- User bấm nút Refresh
- AI Server IP thay đổi
- Stream bị lỗi
- App resume từ background

---

## 📸 SNAPSHOT (Single Frame)

### Lấy 1 frame tĩnh

```dart
Future<void> _takeSnapshot() async {
  try {
    // 1. HTTP GET đến /capture endpoint
    final res = await http.get(
      Uri.parse(AppConfig.captureUrl)
    ).timeout(const Duration(seconds: 5));
    
    if (res.statusCode == 200) {
      // 2. Response body = JPEG bytes
      final jpegBytes = res.bodyBytes;
      
      // 3. Hiển thị preview
      showDialog(
        context: context,
        builder: (_) => Dialog(
          child: Image.memory(jpegBytes, fit: BoxFit.contain),
        ),
      );
      
      // 4. Lưu log
      await DatabaseHelper.instance.addLog(
        'Snapshot', 'Chụp ảnh thủ công'
      );
    }
  } catch (e) {
    _showBanner('Không thể chụp ảnh', AppColors.error);
  }
}
```

**Capture URL:**
```dart
// AppConfig.captureUrl
// → DeviceConfigService.instance.captureUrl
// → 'http://$_esp32Ip:81/capture'
// VD: http://192.168.1.112:81/capture
```

**Lưu ý:**
- Snapshot lấy **trực tiếp từ ESP32**, không qua Python
- Nhanh hơn stream (1 request = 1 frame)
- Dùng cho chụp ảnh thủ công

---

## 🔄 AUTO-RECONNECT

### Listen AI Server IP Change

```dart
@override
void initState() {
  super.initState();
  // Listen khi AI Server IP thay đổi
  DeviceConfigService.instance.aiServerNotifier
    .addListener(_onAiServerChanged);
}

void _onAiServerChanged() {
  if (mounted) {
    setState(() {
      _streamKey = UniqueKey();  // Force rebuild stream
    });
  }
}

@override
void dispose() {
  DeviceConfigService.instance.aiServerNotifier
    .removeListener(_onAiServerChanged);
  super.dispose();
}
```

### ValueNotifier Pattern

```dart
// File: device_config_service.dart
class DeviceConfigService {
  final aiServerNotifier = ValueNotifier<String>('');
  
  Future<void> saveAiServer(String ip, {int port = 5000}) async {
    _aiIp = ip;
    _aiPort = port;
    // ... save to SharedPreferences
    
    // Notify listeners
    aiServerNotifier.value = aiBaseUrl;
  }
}
```

---

## ⚠️ ERROR HANDLING

### Stream Error Widget

```dart
Widget _buildStreamError() {
  final hasIp = DeviceConfigService.instance.hasAiIp;
  
  return Container(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          hasIp ? Icons.videocam_off_rounded 
                : Icons.wifi_off_rounded,
          color: Colors.white24,
          size: 44,
        ),
        const SizedBox(height: 12),
        Text(
          hasIp ? 'Camera offline' 
                : 'Chưa cấu hình ESP32',
          style: TextStyle(color: Colors.white54),
        ),
        const SizedBox(height: 4),
        Text(
          hasIp ? AppConfig.streamUrl 
                : 'Vào Devices → Cấu hình AI Server',
          style: TextStyle(color: Colors.white30, fontSize: 10),
        ),
        const SizedBox(height: 16),
        // Reconnect button
        ElevatedButton(
          onPressed: _reconnectStream,
          child: Text('Reconnect'),
        ),
      ],
    ),
  );
}
```

### Các trường hợp lỗi

**1. Chưa cấu hình AI Server IP:**
```dart
if (!DeviceConfigService.instance.hasAiIp) {
  return Text('Vào Settings → Cấu hình AI Server');
}
```

**2. Python server offline:**
```dart
// Mjpeg widget tự động gọi error callback
error: (ctx, err, stack) {
  return Text('Python server offline');
}
```

**3. Network timeout:**
```dart
// HTTP client tự động timeout sau 30s
// Mjpeg widget sẽ trigger error callback
```

---

## 🎭 FACE RECOGNITION OVERLAY

### MQTT Integration

```dart
void _listenMQTT() {
  MQTTService().connect().then((_) {
    _mqttFaceSub = MQTTService()
      .faceRecognitionStream
      .listen((event) {
        final topic = event['topic'] as String;
        final data = event['data'] as Map<String, dynamic>;
        
        if (topic == 'home/face_recognition/result') {
          // Cập nhật UI với kết quả nhận diện
          setState(() {
            _recognizedFaces = [data];
          });
          
          // Tự xóa sau 8 giây
          Future.delayed(Duration(seconds: 8), () {
            if (mounted) {
              setState(() => _recognizedFaces = []);
            }
          });
        }
      });
  });
}
```

### Face Overlay Widget

```dart
Widget _buildFaceOverlay() {
  final face = _recognizedFaces.first;
  final name = face['name'] as String;
  final matched = face['matched'] as bool;
  final confidence = face['confidence'] as double;
  
  return Container(
    padding: EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: matched ? Colors.green.withOpacity(0.25)
                     : Colors.red.withOpacity(0.25),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(
          matched ? Icons.check_circle_rounded 
                  : Icons.warning_amber_rounded,
          color: matched ? Colors.green : Colors.red,
        ),
        SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(name, style: TextStyle(
              color: matched ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            )),
            if (matched)
              Text(
                'Độ chính xác: ${(confidence * 100).toStringAsFixed(0)}%',
                style: TextStyle(color: Colors.white60, fontSize: 10),
              ),
          ],
        ),
      ],
    ),
  );
}
```

---

## 📊 PERFORMANCE

### Frame Rate
```
Python Relay: 10 FPS (từ ESP32)
    ↓
Flutter Mjpeg: 10 FPS (hiển thị)
    ↓
UI Render: 60 FPS (smooth animation)
```

### Latency
```
ESP32 capture: ~50ms
    ↓
Python relay: ~50ms
    ↓
Network: ~50ms
    ↓
Flutter decode: ~30ms
    ↓
Total: ~180ms (acceptable)
```

### Memory Usage
```
JPEG frame: ~15-20KB
Flutter buffer: ~3 frames = 60KB
Total: <100KB (very light)
```

---

## 🔧 TROUBLESHOOTING

### 1. Stream không hiển thị

**Kiểm tra:**
```dart
debugPrint('Stream URL: ${AppConfig.streamUrl}');
// Phải thấy: http://192.168.1.100:5000/stream
```

**Nguyên nhân:**
- Chưa cấu hình AI Server IP
- Python server chưa chạy
- Firewall block port 5000

### 2. Stream lag/giật

**Nguyên nhân:**
- WiFi yếu
- Python server quá tải
- ESP32 quá tải

**Giải pháp:**
- Giảm FPS trong ESP32 (10 → 5 FPS)
- Giảm resolution (QVGA → QQVGA)
- Tăng JPEG quality (15 → 20)

### 3. Stream đen/trắng

**Nguyên nhân:**
- ESP32 camera chưa init
- Thiếu ánh sáng
- Camera module lỗi

**Giải pháp:**
- Kiểm tra Serial Monitor ESP32
- Tăng brightness trong camera config
- Thay camera module

---

## 💡 BEST PRACTICES

### 1. Dispose Stream Properly

```dart
@override
void dispose() {
  _mqttFaceSub?.cancel();  // Cancel MQTT subscription
  // Mjpeg widget tự động dispose HTTP connection
  super.dispose();
}
```

### 2. Handle App Lifecycle

```dart
@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.paused) {
    // App vào background → pause stream
    setState(() => _isStreamActive = false);
  } else if (state == AppLifecycleState.resumed) {
    // App trở lại → resume stream
    setState(() {
      _isStreamActive = true;
      _streamKey = UniqueKey();  // Reconnect
    });
  }
}
```

### 3. Cache Stream URL

```dart
// Không tạo URL mỗi lần build
static String? _cachedStreamUrl;

String get streamUrl {
  _cachedStreamUrl ??= '$aiBaseUrl/stream';
  return _cachedStreamUrl!;
}
```

### 4. Timeout Handling

```dart
Mjpeg(
  stream: AppConfig.streamUrl,
  timeout: Duration(seconds: 10),  // Timeout sau 10s
  error: (ctx, err, stack) {
    if (err is TimeoutException) {
      return Text('Connection timeout');
    }
    return Text('Stream error');
  },
)
```

---

## 🎓 KẾT LUẬN

**Flutter lấy hình ảnh qua 3 bước:**

1. **Cấu hình:** User nhập IP Python server
2. **Stream:** Mjpeg widget kết nối đến Python relay
3. **Display:** Parse MJPEG → Decode JPEG → Render

**Ưu điểm:**
- ✅ Multi-client support (qua Python relay)
- ✅ Real-time streaming (10 FPS)
- ✅ Low latency (~180ms)
- ✅ Low memory (<100KB)
- ✅ Auto-reconnect

**Hạn chế:**
- ❌ Cần Python server chạy
- ❌ Cần cấu hình IP thủ công
- ❌ Phụ thuộc network

**Giải pháp tương lai:**
- mDNS auto-discovery
- WebRTC streaming
- P2P connection
