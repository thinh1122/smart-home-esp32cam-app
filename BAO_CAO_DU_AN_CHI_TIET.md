# 📊 BÁO CÁO DỰ ÁN: HỆ THỐNG SMART HOME ESP32-CAM VỚI NHẬN DIỆN KHUÔN MẶT

## 📋 THÔNG TIN DỰ ÁN

**Tên dự án:** Smart Home ESP32-CAM Face Recognition System  
**Công nghệ:** ESP32-CAM, Python AI, Flutter, MQTT  
**Mục tiêu:** Xây dựng hệ thống nhà thông minh với camera giám sát, nhận diện khuôn mặt, và điều khiển thiết bị qua MQTT

---

## 🎯 TỔNG QUAN HỆ THỐNG

### Kiến trúc tổng thể

```
┌─────────────────┐      ┌──────────────────┐      ┌─────────────────┐
│   ESP32-CAM     │◄────►│  Python AI       │◄────►│  Flutter App    │
│  (Camera)       │ WiFi │  (Face AI)       │ MQTT │  (Control UI)   │
│  - MJPEG Stream │      │  - Recognition   │      │  - Dashboard    │
│  - BLE Provision│      │  - MJPEG Relay   │      │  - Camera View  │
└─────────────────┘      └──────────────────┘      └─────────────────┘
         │                        │                         │
         └────────────────────────┴─────────────────────────┘
                          MQTT Broker
                     (broker.hivemq.com)
```

### Luồng hoạt động chính

1. **Setup ban đầu:** ESP32-CAM được cấu hình WiFi qua BLE Provisioning
2. **Camera Stream:** ESP32 stream MJPEG → Python relay → Flutter app
3. **Face Recognition:** Python AI tự động nhận diện khuôn mặt mỗi 3 giây
4. **MQTT Communication:** Kết quả nhận diện được publish qua MQTT
5. **Device Control:** Flutter app điều khiển đèn/cửa qua MQTT real-time

---

## 🔧 THÀNH PHẦN HỆ THỐNG

### 1. ESP32-CAM (Hardware Layer)

**Chức năng chính:**
- Stream camera MJPEG 8-10 FPS ổn định
- BLE WiFi Provisioning (cấu hình WiFi không cần code)
- Tối ưu tránh quá tải (WiFi.setSleep off, CAMERA_GRAB_LATEST)

**Firmware:** `esp32cam_ble_provisioning.ino`

**Đặc điểm kỹ thuật:**

- **Board:** AI Thinker ESP32-CAM
- **Camera:** OV2640 (2MP)
- **Resolution:** SVGA (800x600) cho stream
- **Frame Rate:** 8-10 FPS
- **WiFi:** 802.11 b/g/n 2.4GHz
- **BLE:** Bluetooth 4.2 cho provisioning

**Tính năng nổi bật:**

1. **BLE WiFi Provisioning:**
   - Không cần hardcode WiFi credentials
   - Cấu hình qua Flutter app bằng Bluetooth
   - Lưu WiFi vào EEPROM, tự kết nối lại khi khởi động
   - Hỗ trợ quét danh sách WiFi từ ESP32

2. **MJPEG Stream tối ưu:**
   - Single connection stream (ESP32 chỉ chịu 1 client)
   - Python relay giải quyết vấn đề multi-client
   - Frame buffer CAMERA_GRAB_LATEST tránh lag
   - WiFi.setSleep(false) đảm bảo stream mượt

3. **HTTP Endpoints:**
   - `/stream` - MJPEG stream
   - `/capture` - Single frame capture
   - BLE characteristics cho WiFi config

**Code structure:**
```cpp
// BLE UUIDs
SERVICE_UUID   = "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
SSID_UUID      = "beb5483e-36e1-4688-b7f5-ea07361b26a8"
PASS_UUID      = "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
STATUS_UUID    = "d8de624e-140f-4a22-8594-e2216b84a5f2"
WIFILIST_UUID  = "2b8c9e50-7182-4f32-8414-b49911e0eb7e"
```

---

### 2. Python AI Server (Intelligence Layer)

**Chức năng chính:**
- MJPEG Relay: Kéo 1 stream từ ESP32, broadcast cho N client
- Face Recognition: MediaPipe + SSIM matching
- MQTT Publisher: Gửi kết quả nhận diện real-time
- REST API: Enroll, delete, members management

**File:** `face_recognition_advanced.py`

**Công nghệ sử dụng:**
- **Flask:** Web server (port 5000)
- **MediaPipe:** Face detection
- **OpenCV:** Image processing
- **SSIM:** Structural similarity matching
- **Paho MQTT:** MQTT client
- **SQLite:** Member database

**Kiến trúc multi-threading:**

```python
# 3 worker threads chạy song song:
1. relay_worker()        # Kéo MJPEG từ ESP32
2. recognition_worker()  # Nhận diện khuôn mặt mỗi 3s
3. Flask HTTP server     # REST API endpoints
```

**Tính năng nổi bật:**

1. **MJPEG Relay System:**
   - Giải quyết vấn đề ESP32 chỉ chịu 1 kết nối stream
   - Kéo 1 stream từ ESP32, lưu frame mới nhất
   - Broadcast frame cho nhiều client (Flutter, browser)
   - Sử dụng threading.Event để đồng bộ

2. **Face Recognition Pipeline:**
   ```python
   Frame → MediaPipe Detection → Face Crop → 
   Template Matching (SSIM) → MQTT Publish
   ```
   - Interval: 3 giây giữa mỗi lần check
   - Stable time: 2 giây mặt phải giữ yên
   - Match threshold: 50% similarity
   - Cooldown: 10 giây không nhận diện lại

3. **MQTT Integration:**
   - Broker: broker.hivemq.com (public)
   - Topics:
     - `home/face_recognition/result` - Kết quả nhận diện
     - `home/face_recognition/alert` - Cảnh báo người lạ
     - `home/system/log` - System logs

4. **REST API Endpoints:**
   ```
   GET  /stream              # MJPEG stream relay
   GET  /capture             # Single frame
   POST /enroll              # Thêm khuôn mặt mới
   POST /delete              # Xóa member
   GET  /members             # Danh sách members
   POST /config              # Cập nhật ESP32 IP
   GET  /status              # Server status
   ```

**Database Schema (SQLite):**
```sql
CREATE TABLE members (
    id INTEGER PRIMARY KEY,
    name TEXT NOT NULL,
    role TEXT,
    enrolled_at TIMESTAMP,
    template_path TEXT
);
```

**Tối ưu hóa:**
- Frame caching để tránh pull liên tục từ ESP32
- Template pre-loading khi server start
- MQTT auto-reconnect với exponential backoff
- Error handling cho ESP32 offline

---

### 3. Flutter App (User Interface Layer)

**Chức năng chính:**
- Dashboard điều khiển thiết bị
- Camera viewer với face recognition overlay
- BLE WiFi provisioning wizard
- Members management
- Activity logs
- Push notifications

**Công nghệ sử dụng:**
- **Flutter 3.24.3** - Cross-platform framework
- **Dart 3.0+** - Programming language
- **flutter_blue_plus** - BLE communication
- **mqtt_client** - MQTT protocol
- **flutter_mjpeg** - MJPEG stream viewer
- **sqflite** - Local database
- **wifi_scan** - WiFi network scanning

**Kiến trúc ứng dụng:**

```
lib/
├── core/
│   ├── config/
│   │   └── app_config.dart          # MQTT, API endpoints
│   ├── services/
│   │   ├── mqtt_service.dart        # MQTT client singleton
│   │   ├── device_config_service.dart # IP configuration
│   │   ├── database_helper.dart     # SQLite wrapper
│   │   └── notification_service.dart # Push notifications
│   └── theme/
│       └── app_theme.dart           # Dark theme design
├── data/
│   └── models/
│       └── log_model.dart           # Activity log model
└── presentation/
    └── screens/
        ├── main_screen.dart         # Bottom navigation
        ├── dashboard/
        │   └── home_dashboard.dart  # Device cards
        ├── camera/
        │   └── front_door_cam_screen.dart # MJPEG viewer
        ├── devices/
        │   ├── add_device_screen.dart
        │   └── ble_wifi_provisioning_screen.dart
        ├── members/
        │   └── members_screen.dart  # Face management
        └── lights/
            └── living_room_light_screen.dart
```

**Tính năng chi tiết:**

#### 3.1. BLE WiFi Provisioning Screen

**Flow 6 bước:**
1. **Scan:** Quét BLE devices (ESP32CAM_XXXXXX)
2. **Connect:** Kết nối BLE với ESP32
3. **WiFi List:** Hiển thị danh sách WiFi (từ điện thoại hoặc ESP32)
4. **Verify:** Xác nhận ESP32 thấy được WiFi đã chọn
5. **Password:** Nhập password WiFi
6. **Done:** ESP32 kết nối WiFi thành công, trả về IP

**Đặc điểm:**
- Hybrid WiFi scanning: Ưu tiên điện thoại, fallback ESP32
- Manual entry option cho iOS (không scan được WiFi)
- Real-time status updates qua BLE notifications
- Auto-save ESP32 IP vào SharedPreferences
- Auto-notify Python AI server về IP mới

**BLE Communication:**
```dart
// Write SSID
await ssidChar.write(ssid.codeUnits);

// Write Password
await passChar.write(password.codeUnits);

// Listen status
statusChar.lastValueStream.listen((value) {
  final status = String.fromCharCodes(value);
  if (status.startsWith('connected|')) {
    final ip = status.split('|')[1];
    // Save IP and close
  }
});
```

#### 3.2. Camera Screen

**Tính năng:**
- MJPEG stream từ Python relay (không phải ESP32 trực tiếp)
- Face recognition overlay real-time
- Reconnect button
- Live badge indicator
- Activity logs
- Snapshot capture

**Stream handling:**
```dart
Mjpeg(
  key: _streamKey,  // Force rebuild on reconnect
  isLive: true,
  stream: AppConfig.streamUrl,  // Python relay URL
  error: (ctx, err, stack) => _buildStreamError(),
)
```

**MQTT Integration:**
```dart
MQTTService().faceRecognitionStream.listen((event) {
  final topic = event['topic'];
  final data = event['data'];
  
  if (topic == 'home/face_recognition/result') {
    // Hiển thị kết quả nhận diện
    setState(() => _recognizedFaces = [data]);
  } else if (topic == 'home/face_recognition/alert') {
    // Cảnh báo người lạ
    NotificationService.instance.showStrangerAlert();
  }
});
```

#### 3.3. Dashboard Screen

**Device Cards:**
- Front Door Cam (ESP32-CAM)
- Living Room Light (MQTT controlled)
- Smart Door Lock (MQTT controlled)
- Add Device button

**MQTT Control:**
```dart
// Turn on light
MQTTService().controlLight('living_room', true);

// Unlock door
MQTTService().controlDoor('front_door', 'unlock');
```

#### 3.4. Members Management

**Chức năng:**
- Danh sách members với avatar
- Thêm member mới (enroll face)
- Xóa member
- View member details

**API Integration:**
```dart
// Enroll new face
final response = await http.post(
  Uri.parse('${AppConfig.enrollUrl}'),
  body: jsonEncode({
    'name': name,
    'role': role,
    'images': [base64Image1, base64Image2, base64Image3]
  }),
);
```

#### 3.5. Device Configuration Service

**Dynamic IP Management:**
- Lưu ESP32 IP sau BLE provisioning
- Lưu Python AI Server IP (manual config)
- SharedPreferences persistence
- ValueNotifier để notify UI khi IP thay đổi

```dart
class DeviceConfigService {
  String _esp32Ip = '';
  String _aiIp = '';
  
  String get esp32BaseUrl => 'http://$_esp32Ip:81';
  String get aiBaseUrl => 'http://$_aiIp:5000';
  String get streamUrl => '$aiBaseUrl/stream';
  
  Future<void> saveEsp32Ip(String ip) async {
    _esp32Ip = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp32_ip', ip);
  }
}
```

#### 3.6. MQTT Service

**Singleton Pattern:**
```dart
class MQTTService {
  static final _instance = MQTTService._internal();
  factory MQTTService() => _instance;
  
  MqttServerClient? _client;
  bool _isConnected = false;
  
  // Broadcast streams
  final _faceRecognitionController = 
    StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get faceRecognitionStream => 
    _faceRecognitionController.stream;
}
```

**Auto-reconnect:**
```dart
void _onDisconnected() {
  _isConnected = false;
  Future.delayed(const Duration(seconds: 5), () {
    if (!_isConnected) connect();
  });
}
```

---

## 🚀 DEPLOYMENT & CI/CD

### GitHub Actions Workflow

**File:** `.github/workflows/build-flutter.yml`

**Build Matrix:**
- ✅ Android APK (ubuntu-latest)
- ✅ iOS IPA (macos-latest, no-codesign)
- ✅ Web Build (ubuntu-latest)

**Workflow Steps:**
1. Checkout code
2. Setup Flutter 3.24.3
3. Install dependencies (`flutter pub get`)
4. Build release artifacts
5. Upload artifacts
6. Create GitHub Release (auto-tag)

**Artifacts:**
- `android-apk/app-release.apk`
- `ios-ipa/SmartHome.ipa`
- `web-build/web-build.zip`

**Trigger:**
- Push to `main` or `master` branch
- Manual workflow dispatch

**Installation:**
- Android: Direct APK install
- iOS: Sideloadly (no Apple Developer Account needed)
- Web: Deploy to hosting service

---

## 📊 TÍNH NĂNG ĐÃ HOÀN THIỆN

### ✅ ESP32-CAM
- [x] MJPEG stream 8-10 FPS ổn định
- [x] BLE WiFi Provisioning
- [x] Tối ưu tránh quá tải
- [x] Auto-reconnect WiFi
- [x] HTTP endpoints (/stream, /capture)

### ✅ Python AI Server
- [x] MJPEG Relay (1→N clients)
- [x] Face Recognition (MediaPipe + SSIM)
- [x] MQTT Publisher
- [x] REST API (enroll, delete, members)
- [x] SQLite database
- [x] Multi-threading architecture
- [x] Auto-reconnect MQTT

### ✅ Flutter App
- [x] Dashboard với device cards
- [x] Camera viewer + face overlay
- [x] BLE WiFi provisioning wizard
- [x] Members management
- [x] Activity logs (SQLite)
- [x] Push notifications
- [x] MQTT real-time control
- [x] Dynamic IP configuration
- [x] Dark theme UI
- [x] Multi-platform (Android, iOS, Web)

### ✅ DevOps
- [x] GitHub Actions CI/CD
- [x] Auto-build APK/IPA/Web
- [x] GitHub Releases
- [x] Documentation

---

## 🔬 TESTING & VALIDATION

### Test Cases

**1. BLE Provisioning:**
- ✅ Scan ESP32 devices
- ✅ Connect via BLE
- ✅ WiFi list display
- ✅ Password input
- ✅ ESP32 connect WiFi
- ✅ IP return to app

**2. Camera Stream:**
- ✅ MJPEG stream display
- ✅ Reconnect on error
- ✅ Multi-client support (via relay)
- ✅ Frame rate stability

**3. Face Recognition:**
- ✅ Face detection accuracy
- ✅ Template matching
- ✅ MQTT publish latency
- ✅ Stranger alert
- ✅ Member recognition

**4. MQTT Communication:**
- ✅ Connect to broker
- ✅ Subscribe topics
- ✅ Publish messages
- ✅ Auto-reconnect
- ✅ Message delivery

**5. Device Control:**
- ✅ Light on/off
- ✅ Door lock/unlock
- ✅ Real-time response

---

## 📈 PERFORMANCE METRICS

### ESP32-CAM
- **Stream FPS:** 8-10 FPS
- **Frame delay:** <100ms
- **WiFi reconnect:** <5s
- **Memory usage:** ~60% (240KB/400KB)

### Python AI Server
- **Face detection:** ~200ms/frame
- **Template matching:** ~50ms/face
- **MQTT publish:** <10ms
- **Relay latency:** <50ms

### Flutter App
- **App startup:** <2s
- **MQTT connect:** <3s
- **Stream load:** <1s
- **BLE scan:** ~10s
- **UI responsiveness:** 60 FPS

---

## 🛠️ CÔNG NGHỆ SỬ DỤNG

### Hardware
- ESP32-CAM (AI Thinker)
- OV2640 Camera (2MP)
- USB-TTL Adapter

### Firmware
- Arduino IDE
- ESP32 Board Package
- ESP32 Camera Library
- BLE Library

### Backend
- Python 3.8+
- Flask (Web server)
- MediaPipe (Face detection)
- OpenCV (Image processing)
- Paho MQTT (MQTT client)
- SQLite (Database)

### Frontend
- Flutter 3.24.3
- Dart 3.0+
- flutter_blue_plus (BLE)
- mqtt_client (MQTT)
- flutter_mjpeg (Stream)
- sqflite (Local DB)

### Infrastructure
- MQTT Broker: broker.hivemq.com
- GitHub Actions (CI/CD)
- GitHub Releases (Distribution)

---

## 📝 HƯỚNG DẪN SỬ DỤNG

### Setup ESP32-CAM
1. Upload firmware `esp32cam_ble_provisioning.ino`
2. Power on ESP32-CAM
3. LED sẽ nhấp nháy (BLE advertising mode)

### Setup Python AI Server
1. Install dependencies: `pip install -r requirements_advanced.txt`
2. Update ESP32 IP in `face_recognition_advanced.py`
3. Run server: `python face_recognition_advanced.py`
4. Server chạy tại `http://0.0.0.0:5000`

### Setup Flutter App
1. Download APK/IPA từ GitHub Releases
2. Install bằng Sideloadly (iOS) hoặc direct install (Android)
3. Mở app → Tab "Devices"
4. Bấm "+" → Chọn "BLE WiFi Setup"
5. Scan → Connect ESP32 → Chọn WiFi → Nhập password
6. ESP32 kết nối WiFi thành công
7. Vào Settings → Cấu hình AI Server IP (IP máy tính chạy Python)
8. Vào tab "Camera" → Xem stream

### Enroll Face
1. Tab "Members" → Bấm "+"
2. Nhập tên và vai trò
3. Chụp 3 ảnh khuôn mặt từ các góc khác nhau
4. Bấm "Save"
5. Face template được lưu vào database

### Test Recognition
1. Đứng trước camera ESP32
2. Python AI tự động nhận diện mỗi 3 giây
3. Kết quả hiển thị trên Flutter app
4. Notification push khi có người được nhận diện

---

## 🔮 HƯỚNG PHÁT TRIỂN

### Tính năng mở rộng
- [ ] Multi-camera support
- [ ] Cloud storage (AWS S3)
- [ ] Advanced AI (deep learning)
- [ ] Voice control (Google Assistant)
- [ ] Automation rules (IFTTT-like)
- [ ] Web dashboard
- [ ] User authentication
- [ ] Role-based access control

### Tối ưu hóa
- [ ] Edge AI on ESP32 (TensorFlow Lite)
- [ ] H.264 video encoding
- [ ] WebRTC streaming
- [ ] Redis caching
- [ ] Load balancing
- [ ] Kubernetes deployment

---

## 👥 TEAM & CONTRIBUTION

**Developer:** Nguyen Phung Thinh  
**Repository:** https://github.com/thinh1122/smarthome_DATN  
**License:** MIT

---

## 📞 SUPPORT

**Issues:** https://github.com/thinh1122/smarthome_DATN/issues  
**Documentation:** https://github.com/thinh1122/smarthome_DATN/wiki

---

**Made with ❤️ for Smart Home enthusiasts**
