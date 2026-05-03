# 🔍 DEBUG CAMERA KHÔNG HIỂN THỊ

## VẤN ĐỀ: Camera không hiển thị trong Flutter app

### NGUYÊN NHÂN:
Flutter app lấy stream từ **Python AI Server** (port 5000), KHÔNG phải từ ESP32 trực tiếp!

```
Flutter App → Python AI Server (port 5000) → ESP32-CAM (port 81)
            ↑ /stream endpoint
```

---

## ✅ CHECKLIST DEBUG:

### 1. KIỂM TRA PYTHON SERVER ĐANG CHẠY:

```bash
# Mở Command Prompt/Terminal mới
cd ESP32CAM
python face_recognition_advanced.py
```

**Kết quả mong đợi:**
```
🚀 Face Recognition Server started on http://0.0.0.0:5000
📹 MJPEG relay worker started
📡 MQTT connecting to broker.hivemq.com:1883
```

**Nếu lỗi:**
- Cài dependencies: `pip install -r requirements_advanced.txt`
- Kiểm tra Python version: `python --version` (cần 3.8+)

---

### 2. KIỂM TRA ESP32 IP TRONG PYTHON SERVER:

**Mở file:** `ESP32CAM/face_recognition_advanced.py`

**Tìm dòng:**
```python
ESP32_IP = "192.168.1.35"  # ← Phải đúng IP ESP32 của bạn
```

**Cách lấy IP ESP32:**
1. Mở Serial Monitor trong Arduino IDE
2. Reset ESP32-CAM
3. Sau khi kết nối WiFi, sẽ thấy: `✅ WiFi connected! IP: 192.168.x.x`
4. Copy IP này vào Python server

---

### 3. TEST PYTHON SERVER STREAM:

**Mở trình duyệt, truy cập:**
```
http://localhost:5000/stream
```

**Kết quả mong đợi:**
- Thấy camera stream từ ESP32
- Nếu lỗi "ESP32 không phản hồi" → Kiểm tra ESP32_IP

---

### 4. CẤU HÌNH AI SERVER TRONG FLUTTER APP:

**Trong Flutter app:**
1. Vào màn hình **Settings** hoặc **Devices**
2. Tìm mục **"AI Server Configuration"**
3. Nhập:
   - **AI Server IP**: `192.168.x.x` (IP máy tính chạy Python)
   - **AI Server Port**: `5000`
4. Bấm **Save**

**Hoặc kiểm tra code:**
```dart
// File: FLUTTER/lib/core/services/device_config_service.dart
// Phải có IP được lưu:
String get aiIp => _aiIp;  // Không được rỗng!
```

---

### 5. TEST STREAM TỪ FLUTTER:

**Sau khi cấu hình AI Server:**
1. Vào màn hình **Front Door Cam**
2. Bấm nút **Refresh** (góc trên bên phải)
3. Đợi 3-5 giây

**Kết quả mong đợi:**
- Thấy camera stream
- Góc trên trái có badge "Relay Connected"

**Nếu vẫn lỗi:**
- Kiểm tra log trong Python server
- Kiểm tra firewall có block port 5000 không

---

## 🐛 CÁC LỖI THƯỜNG GẶP:

### Lỗi 1: "Camera offline"
**Nguyên nhân:** Python server không chạy hoặc chưa cấu hình IP
**Giải pháp:** 
- Chạy Python server: `python face_recognition_advanced.py`
- Cấu hình AI Server IP trong app

### Lỗi 2: "Chưa cấu hình ESP32"
**Nguyên nhân:** Chưa lưu AI Server IP trong app
**Giải pháp:**
- Vào Settings → AI Server Configuration
- Nhập IP máy tính chạy Python (VD: 192.168.1.100)

### Lỗi 3: Python server báo "ESP32 không phản hồi"
**Nguyên nhân:** ESP32_IP sai hoặc ESP32 chưa kết nối WiFi
**Giải pháp:**
- Kiểm tra ESP32 đã kết nối WiFi chưa (Serial Monitor)
- Cập nhật ESP32_IP trong `face_recognition_advanced.py`
- Restart Python server

### Lỗi 4: Stream lag/chậm
**Nguyên nhân:** ESP32 quá tải hoặc WiFi yếu
**Giải pháp:**
- Giảm FPS trong ESP32 code (hiện tại: 10 FPS)
- Kiểm tra tín hiệu WiFi ESP32
- Dùng Relay Server để tối ưu

---

## 📝 FLOW HOẠT ĐỘNG ĐÚNG:

```
1. ESP32-CAM kết nối WiFi (qua BLE Provisioning)
   ↓
2. Python AI Server chạy, kéo stream từ ESP32
   ↓
3. Flutter app cấu hình AI Server IP
   ↓
4. Flutter app lấy stream từ Python (http://AI_IP:5000/stream)
   ↓
5. Camera hiển thị trong app ✅
```

---

## 🔧 SCRIPT TEST NHANH:

### Test ESP32 stream trực tiếp:
```bash
# Mở trình duyệt:
http://192.168.1.35:81/stream
# (Thay 192.168.1.35 bằng IP ESP32 của bạn)
```

### Test Python relay:
```bash
# Mở trình duyệt:
http://localhost:5000/stream
```

### Test từ Flutter:
```dart
// Trong app, kiểm tra log:
debugPrint('Stream URL: ${AppConfig.streamUrl}');
// Phải thấy: http://192.168.x.x:5000/stream
```

---

## 💡 LƯU Ý QUAN TRỌNG:

1. **Python server PHẢI chạy trước** khi mở Flutter app
2. **ESP32 và máy tính phải cùng mạng WiFi**
3. **Firewall có thể block port 5000** → Tắt firewall để test
4. **ESP32 chỉ chịu 1 kết nối stream** → Dùng Python relay để nhiều client

---

## 🆘 VẪN KHÔNG ĐƯỢC?

Gửi cho tôi:
1. Log từ Python server (copy toàn bộ terminal output)
2. IP ESP32 (từ Serial Monitor)
3. IP máy tính chạy Python (chạy `ipconfig` trên Windows)
4. Screenshot lỗi trong Flutter app
