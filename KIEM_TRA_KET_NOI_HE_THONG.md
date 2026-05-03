# 🔍 KIỂM TRA KẾT NỐI HỆ THỐNG

## 📊 TỔNG QUAN KẾT NỐI

```
Flutter App ──HTTP──> Python Server ──HTTP──> ESP32-CAM
(điện thoại)         (máy tính)              (phần cứng)
   :5000/stream         :81/stream
```

---

## 1️⃣ FLUTTER GỌI PYTHON

### 1.1. Cấu hình URL

**File:** `FLUTTER/lib/core/config/app_config.dart`

```dart
class AppConfig {
  // Lấy IP Python từ DeviceConfigService
  static String get aiBaseUrl => 
    DeviceConfigService.instance.aiBaseUrl;
  
  // Stream URL = Python relay
  static String get streamUrl => 
    hasAiServer ? '$aiBaseUrl/stream' : '';
  
  // Các endpoints khác
  static String get enrollUrl  => '$aiBaseUrl/enroll';
  static String get deleteUrl  => '$aiBaseUrl/delete';
  static String get membersUrl => '$aiBaseUrl/members';
  static String get configUrl  => '$aiBaseUrl/config';
  static String get statusUrl  => '$aiBaseUrl/status';
  static String get captureUrl => 
    DeviceConfigService.instance.captureUrl;
}
```

**Giải thích:**
- `aiBaseUrl` = `http://192.168.1.100:5000` (IP máy tính)
- `streamUrl` = `http://192.168.1.100:5000/stream`
- `captureUrl` = `http://192.168.1.112:81/capture` (ESP32 trực tiếp)

### 1.2. Lưu IP Python Server

**File:** `FLUTTER/lib/core/services/device_config_service.dart`

```dart
class DeviceConfigService {
  String _aiIp = '';      // IP máy tính chạy Python
  int _aiPort = 5000;     // Port Python server
  
  // Tạo base URL
  String get aiBaseUrl => 
    hasAiIp ? 'http://$_aiIp:$_aiPort' : '';
  
  // Lưu vào SharedPreferences
  Future<void> saveAiServer(String ip, {int port = 5000}) async {
    _aiIp = ip;
    _aiPort = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ai_server_ip', ip);
    await prefs.setInt('ai_server_port', port);
    aiServerNotifier.value = aiBaseUrl; // Notify listeners
  }
}
```

**Flow:**
1. User vào Settings → Nhập IP máy tính (VD: `192.168.1.100`)
2. `saveAiServer("192.168.1.100", port: 5000)`
3. Lưu vào SharedPreferences
4. `aiBaseUrl` = `http://192.168.1.100:5000`

### 1.3. Gọi Stream từ Python

**File:** `FLUTTER/lib/presentation/screens/camera/front_door_cam_screen.dart`

```dart
Widget _buildCameraFeed() {
  return Mjpeg(
    key: _streamKey,
    isLive: true,
    stream: AppConfig.streamUrl,  // ← Gọi Python relay
    error: (ctx, err, stack) => _buildStreamError(),
  );
}
```

**HTTP Request:**
```http
GET /stream HTTP/1.1
Host: 192.168.1.100:5000
Connection: keep-alive
```

**HTTP Response từ Python:**
```http
HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace;boundary=frame

--frame
Content-Type: image/jpeg
Content-Length: 15234

[JPEG data]
--frame
...
```

### 1.4. Gọi Snapshot từ ESP32

**File:** `FLUTTER/lib/presentation/screens/camera/front_door_cam_screen.dart`

```dart
Future<void> _takeSnapshot() async {
  // Gọi TRỰC TIẾP đến ESP32, không qua Python
  final res = await http.get(
    Uri.parse(AppConfig.captureUrl)  // ESP32 IP:81/capture
  ).timeout(const Duration(seconds: 5));
  
  if (res.statusCode == 200) {
    final jpegBytes = res.bodyBytes;
    // Hiển thị ảnh
  }
}
```

**HTTP Request:**
```http
GET /capture HTTP/1.1
Host: 192.168.1.112:81
```

**HTTP Response từ ESP32:**
```http
HTTP/1.1 200 OK
Content-Type: image/jpeg
Content-Length: 15234

[JPEG binary data]
```

### 1.5. Notify Python về ESP32 IP mới

**File:** `FLUTTER/lib/presentation/screens/devices/ble_wifi_provisioning_screen.dart`

```dart
void _notifyAiServer(String ip) {
  final url = '${AppConfig.aiBaseUrl}/config';
  http.post(
    Uri.parse(url),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'ip': ip, 'port': 81}),
  ).then((_) {
    debugPrint('AI server notified: ESP32 IP = $ip');
  }).catchError((e) {
    debugPrint('AI server notify failed (offline?): $e');
  });
}
```

**HTTP Request:**
```http
POST /config HTTP/1.1
Host: 192.168.1.100:5000
Content-Type: application/json

{"ip": "192.168.1.112", "port": 81}
```

---

## 2️⃣ PYTHON GỌI ESP32-CAM

### 2.1. Cấu hình ESP32 IP

**File:** `ESP32CAM/face_recognition_advanced.py`

```python
# CONFIG
ESP32_IP   = "192.168.1.27"   # ← Cập nhật IP ESP32 tại đây
ESP32_PORT = 81
```

**Cách lấy IP ESP32:**
1. Mở Serial Monitor trong Arduino IDE
2. Reset ESP32-CAM
3. Sau khi kết nối WiFi, sẽ thấy:
   ```
   ✅ Connected! IP: 192.168.1.112
   ```
4. Copy IP này vào Python code

### 2.2. MJPEG Relay Worker

**File:** `ESP32CAM/face_recognition_advanced.py`

```python
def relay_worker():
    """Kéo MJPEG stream từ ESP32, broadcast cho nhiều client."""
    global relay_frame
    print("📹 MJPEG relay worker started")
    
    while True:
        # Tạo URL stream từ ESP32
        url = f"http://{ESP32_IP}:{ESP32_PORT}/stream"
        print(f"📹 Relay connecting: {url}")
        
        try:
            # HTTP GET đến ESP32
            r = requests.get(url, stream=True, timeout=10)
            buf = b''
            
            # Đọc stream liên tục
            for chunk in r.iter_content(chunk_size=4096):
                buf += chunk
                
                # Parse JPEG boundaries
                while True:
                    start = buf.find(b'\xff\xd8')  # JPEG start
                    end   = buf.find(b'\xff\xd9')  # JPEG end
                    
                    if start == -1 or end == -1 or end < start:
                        break
                    
                    # Extract JPEG
                    jpg = buf[start:end + 2]
                    buf = buf[end + 2:]
                    
                    # Lưu frame mới nhất
                    with relay_lock:
                        relay_frame = jpg
                    
                    # Notify tất cả subscribers (Flutter clients)
                    with relay_sub_lock:
                        for ev in relay_subscribers:
                            ev.set()
        
        except Exception as e:
            print(f"⚠️ Relay worker error: {e} — retry in 2s")
            time.sleep(2)
```

**HTTP Request từ Python đến ESP32:**
```http
GET /stream HTTP/1.1
Host: 192.168.1.112:81
Connection: keep-alive
```

**HTTP Response từ ESP32:**
```http
HTTP/1.1 200 OK
Content-Type: multipart/x-mixed-replace;boundary=123456789000000000000987654321

--123456789000000000000987654321
Content-Type: image/jpeg
Content-Length: 15234

[JPEG data]
--123456789000000000000987654321
...
```

### 2.3. Flask Endpoint - Broadcast Stream

**File:** `ESP32CAM/face_recognition_advanced.py`

```python
@app.route('/stream')
def stream():
    """Broadcast MJPEG stream cho Flutter clients."""
    def generate():
        # Tạo event cho client này
        my_event = threading.Event()
        with relay_sub_lock:
            relay_subscribers.add(my_event)
        
        try:
            while True:
                # Chờ frame mới
                my_event.wait(timeout=5.0)
                my_event.clear()
                
                # Lấy frame từ relay
                with relay_lock:
                    if relay_frame is None:
                        continue
                    frame = relay_frame
                
                # Gửi frame cho Flutter client
                yield (b'--frame\r\n'
                       b'Content-Type: image/jpeg\r\n'
                       b'Content-Length: ' + str(len(frame)).encode() + b'\r\n\r\n'
                       + frame + b'\r\n')
        finally:
            # Cleanup
            with relay_sub_lock:
                relay_subscribers.discard(my_event)
    
    return Response(generate(),
                    mimetype='multipart/x-mixed-replace; boundary=frame')
```

**Flow:**
1. Flutter gọi `GET /stream`
2. Python tạo generator function
3. Generator chờ frame mới từ relay_worker
4. Khi có frame → gửi cho Flutter
5. Lặp lại

### 2.4. Capture Single Frame

**File:** `ESP32CAM/face_recognition_advanced.py`

```python
@app.route('/capture')
def capture():
    """Lấy 1 frame từ ESP32."""
    try:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/capture"
        r = requests.get(url, timeout=5)
        
        if r.status_code == 200:
            return Response(r.content, mimetype='image/jpeg')
        else:
            return jsonify({'error': 'ESP32 error'}), 500
    except Exception as e:
        return jsonify({'error': str(e)}), 500
```

**HTTP Request từ Python đến ESP32:**
```http
GET /capture HTTP/1.1
Host: 192.168.1.112:81
```

### 2.5. Update ESP32 IP Dynamically

**File:** `ESP32CAM/face_recognition_advanced.py`

```python
@app.route('/config', methods=['POST'])
def config():
    """Cập nhật ESP32 IP từ Flutter."""
    global ESP32_IP, ESP32_PORT
    data = request.get_json()
    
    if 'ip' in data:
        ESP32_IP = data['ip']
        print(f"🔄 ESP32 IP updated: {ESP32_IP}")
        
        # Restart relay worker với IP mới
        relay_restart_event.set()
    
    if 'port' in data:
        ESP32_PORT = data['port']
    
    return jsonify({
        'status': 'ok',
        'esp32_ip': ESP32_IP,
        'esp32_port': ESP32_PORT
    })
```

**HTTP Request từ Flutter:**
```http
POST /config HTTP/1.1
Host: 192.168.1.100:5000
Content-Type: application/json

{"ip": "192.168.1.112", "port": 81}
```

---

## 🔄 FLOW HOÀN CHỈNH

### Stream Video Flow

```
┌─────────────────────────────────────────────────────────────┐
│ ESP32-CAM                                                   │
├─────────────────────────────────────────────────────────────┤
│ 1. Camera capture frame                                     │
│ 2. Encode JPEG                                              │
│ 3. Send via HTTP /stream                                    │
│    → multipart/x-mixed-replace                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ HTTP GET :81/stream
┌─────────────────────────────────────────────────────────────┐
│ Python AI Server (Relay Worker)                            │
├─────────────────────────────────────────────────────────────┤
│ 1. requests.get(ESP32_IP:81/stream)                        │
│ 2. Parse MJPEG boundaries                                   │
│ 3. Extract JPEG frames                                      │
│ 4. Store latest frame in relay_frame                        │
│ 5. Notify all subscribers                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ HTTP GET :5000/stream
┌─────────────────────────────────────────────────────────────┐
│ Flutter App (Mjpeg Widget)                                  │
├─────────────────────────────────────────────────────────────┤
│ 1. HTTP GET to Python :5000/stream                         │
│ 2. Receive multipart/x-mixed-replace                        │
│ 3. Parse JPEG boundaries                                    │
│ 4. Decode JPEG → Image                                      │
│ 5. Render on Canvas                                         │
└─────────────────────────────────────────────────────────────┘
```

### Snapshot Flow

```
┌─────────────────────────────────────────────────────────────┐
│ Flutter App                                                 │
├─────────────────────────────────────────────────────────────┤
│ User bấm "Snapshot"                                         │
│ http.get(ESP32_IP:81/capture)  ← Gọi TRỰC TIẾP ESP32      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ HTTP GET :81/capture
┌─────────────────────────────────────────────────────────────┐
│ ESP32-CAM                                                   │
├─────────────────────────────────────────────────────────────┤
│ 1. Camera capture 1 frame                                   │
│ 2. Encode JPEG                                              │
│ 3. Return JPEG bytes                                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ JPEG bytes
┌─────────────────────────────────────────────────────────────┐
│ Flutter App                                                 │
├─────────────────────────────────────────────────────────────┤
│ 1. Receive JPEG bytes                                       │
│ 2. Image.memory(bytes)                                      │
│ 3. Show dialog                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## ✅ KIỂM TRA KẾT NỐI

### Test 1: ESP32 → Browser

```bash
# Mở browser, truy cập:
http://192.168.1.112:81/stream

# Kết quả mong đợi:
✅ Thấy video từ camera
❌ Lỗi → ESP32 chưa chạy hoặc IP sai
```

### Test 2: Python → ESP32

```bash
# Chạy Python server
python face_recognition_advanced.py

# Kiểm tra log:
✅ "📹 Relay connecting: http://192.168.1.112:81/stream"
✅ Không có lỗi "Connection refused"
❌ Lỗi → ESP32_IP sai hoặc ESP32 offline
```

### Test 3: Python Relay → Browser

```bash
# Mở browser, truy cập:
http://localhost:5000/stream

# Kết quả mong đợi:
✅ Thấy video từ ESP32 (qua Python relay)
❌ Lỗi → Python chưa kết nối được ESP32
```

### Test 4: Flutter → Python

```dart
// Trong Flutter app
debugPrint('Stream URL: ${AppConfig.streamUrl}');
// Phải thấy: http://192.168.1.100:5000/stream

// Vào tab Camera
// Kết quả mong đợi:
✅ Thấy video
❌ "Camera offline" → AI Server IP chưa cấu hình
❌ "Chưa cấu hình ESP32" → hasAiIp = false
```

### Test 5: End-to-End

```bash
# 1. ESP32 chạy
Serial Monitor: "✅ Connected! IP: 192.168.1.112"

# 2. Python chạy
Terminal: "✅ MQTT connected"

# 3. Flutter chạy
App: Tab Camera → Thấy video ✅
```

---

## 🐛 DEBUG COMMANDS

### Kiểm tra ESP32 IP

```bash
# Serial Monitor ESP32
✅ Connected! IP: 192.168.1.112

# Ping từ máy tính
ping 192.168.1.112
```

### Kiểm tra Python Server

```bash
# Kiểm tra port 5000
netstat -an | findstr 5000

# Kết quả mong đợi:
TCP    0.0.0.0:5000           0.0.0.0:0              LISTENING
```

### Kiểm tra Flutter Config

```dart
// Trong Flutter app, thêm debug:
@override
void initState() {
  super.initState();
  debugPrint('=== DEBUG CONFIG ===');
  debugPrint('AI Base URL: ${AppConfig.aiBaseUrl}');
  debugPrint('Stream URL: ${AppConfig.streamUrl}');
  debugPrint('Capture URL: ${AppConfig.captureUrl}');
  debugPrint('Has AI Server: ${AppConfig.hasAiServer}');
  debugPrint('==================');
}
```

### Test HTTP Requests

```bash
# Test ESP32 stream
curl http://192.168.1.112:81/stream

# Test Python relay
curl http://localhost:5000/stream

# Test Python status
curl http://localhost:5000/status
```

---

## 📊 KẾT LUẬN

### ✅ Flutter gọi Python ĐÚNG khi:

1. **Cấu hình:**
   - `DeviceConfigService` lưu AI Server IP
   - `AppConfig.streamUrl` = `http://AI_IP:5000/stream`

2. **Stream:**
   - `Mjpeg` widget gọi `AppConfig.streamUrl`
   - HTTP GET đến Python relay

3. **Snapshot:**
   - `http.get(AppConfig.captureUrl)`
   - Gọi TRỰC TIẾP ESP32 (không qua Python)

### ✅ Python gọi ESP32 ĐÚNG khi:

1. **Cấu hình:**
   - `ESP32_IP` = IP thật của ESP32
   - `ESP32_PORT` = 81

2. **Relay:**
   - `relay_worker()` gọi `http://ESP32_IP:81/stream`
   - Parse MJPEG → Lưu frame → Broadcast

3. **Dynamic Update:**
   - Flutter POST `/config` → Python update `ESP32_IP`
   - Relay worker restart với IP mới

### 🎯 Checklist Hoàn Chỉnh:

- [ ] ESP32_IP trong Python code đúng
- [ ] AI Server IP trong Flutter app đúng
- [ ] ESP32 đã kết nối WiFi
- [ ] Python server đang chạy
- [ ] Firewall không block port 5000
- [ ] ESP32 và máy tính cùng mạng WiFi
