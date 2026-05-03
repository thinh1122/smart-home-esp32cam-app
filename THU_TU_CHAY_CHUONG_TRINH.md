# 🚀 THỨ TỰ CHẠY CHƯƠNG TRÌNH

## 📋 TÓM TẮT NHANH

```
1. ESP32-CAM (phần cứng)
   ↓
2. Python AI Server (máy tính)
   ↓
3. Flutter App (điện thoại)
```

---

## 🎯 THỨ TỰ CHI TIẾT

### ⚡ BƯỚC 1: ESP32-CAM (BẮT BUỘC - CHẠY TRƯỚC TIÊN)

**Tại sao phải chạy trước?**
- ESP32 là nguồn cung cấp video
- Python server cần kéo stream từ ESP32
- Không có ESP32 → Python không có gì để relay

**Cách chạy:**

#### 1.1. Upload firmware (chỉ làm 1 lần)
```bash
# Arduino IDE
1. Mở file: ESP32CAM/esp32cam_ble_provisioning/esp32cam_ble_provisioning.ino
2. Board: AI Thinker ESP32-CAM
3. Port: COM3 (port của bạn)
4. Upload Speed: 115200
5. Click Upload
```

#### 1.2. Cấp nguồn cho ESP32
```
Cắm USB hoặc nguồn 5V
    ↓
ESP32 boot
    ↓
Kiểm tra Serial Monitor (115200 baud)
```

#### 1.3. Kiểm tra trạng thái

**Nếu chưa có WiFi (lần đầu):**
```
🔵 BLE: ESP32CAM-A1B2
✅ BLE ready — waiting for Flutter app
```
→ LED nhấp nháy → Chế độ BLE Provisioning

**Nếu đã có WiFi:**
```
📂 Saved WiFi: MyWiFi
🔌 Connecting.....
✅ Connected! IP: 192.168.1.112
✅ Camera OK
✅ Stream: http://192.168.1.112:81/stream
✅ Capture: http://192.168.1.112:81/capture
```
→ LED sáng liên tục → Chế độ Camera Streaming

#### 1.4. Test ESP32 stream (optional)
```bash
# Mở browser, truy cập:
http://192.168.1.112:81/stream

# Phải thấy video từ camera
```

**✅ ESP32 READY khi:**
- LED sáng liên tục (không nhấp nháy)
- Serial Monitor hiển thị IP
- Browser thấy được stream

---

### 🐍 BƯỚC 2: PYTHON AI SERVER (BẮT BUỘC - CHẠY SAU ESP32)

**Tại sao phải chạy sau ESP32?**
- Python cần kéo stream từ ESP32
- Nếu ESP32 chưa chạy → Python báo lỗi "ESP32 không phản hồi"

**Cách chạy:**

#### 2.1. Cài dependencies (chỉ làm 1 lần)
```bash
cd ESP32CAM
pip install -r requirements_advanced.txt
```

#### 2.2. Cập nhật IP ESP32
```python
# Mở file: ESP32CAM/face_recognition_advanced.py
# Tìm dòng:
ESP32_IP = "192.168.1.35"  # ← Thay bằng IP ESP32 của bạn

# Lấy IP từ Serial Monitor ESP32 (bước 1.3)
```

#### 2.3. Chạy Python server
```bash
cd ESP32CAM
python face_recognition_advanced.py
```

#### 2.4. Kiểm tra log

**Log thành công:**
```
🚀 Face Recognition Server started on http://0.0.0.0:5000
📹 MJPEG relay worker started
📡 MQTT connecting to broker.hivemq.com:1883
✅ MQTT connected
🤖 Recognition worker started
```

**Log lỗi (ESP32 chưa chạy):**
```
⚠️ ESP32-CAM lỗi: Connection refused
⚠️ Relay worker error: [Errno 111] Connection refused
```
→ Quay lại bước 1, kiểm tra ESP32

#### 2.5. Test Python relay (optional)
```bash
# Mở browser, truy cập:
http://localhost:5000/stream

# Phải thấy video từ ESP32 (qua relay)
```

#### 2.6. Kiểm tra status
```bash
# Mở browser:
http://localhost:5000/status

# Phải thấy JSON:
{
  "esp32": "192.168.1.112:81",
  "mqtt": true,
  "recognition_phase": "idle",
  "templates": 0
}
```

**✅ PYTHON READY khi:**
- Log hiển thị "MQTT connected"
- Log hiển thị "Recognition worker started"
- Browser thấy được stream từ localhost:5000
- Không có lỗi "ESP32 không phản hồi"

---

### 📱 BƯỚC 3: FLUTTER APP (TÙY CHỌN - CHẠY CUỐI CÙNG)

**Tại sao chạy cuối?**
- Flutter cần Python server để lấy stream
- Flutter cần ESP32 để BLE provisioning (nếu chưa có WiFi)

**Cách chạy:**

#### 3.1. Build app (nếu chưa có)
```bash
cd FLUTTER
flutter pub get
flutter run
```

Hoặc download APK/IPA từ GitHub Releases

#### 3.2. Cấu hình AI Server IP (chỉ làm 1 lần)

**Lấy IP máy tính:**
```bash
# Windows
ipconfig

# Tìm dòng:
IPv4 Address. . . . . . . . . . . : 192.168.1.100
```

**Trong Flutter app:**
1. Vào tab **Devices**
2. Bấm **Settings** hoặc **Cấu hình AI Server**
3. Nhập:
   - AI Server IP: `192.168.1.100` (IP máy tính)
   - AI Server Port: `5000`
4. Bấm **Save**

#### 3.3. Xem camera stream
1. Vào tab **Camera**
2. Đợi 2-3 giây
3. Phải thấy video từ ESP32

**Nếu không thấy video:**
- Kiểm tra Python server có chạy không
- Kiểm tra AI Server IP đã đúng chưa
- Bấm nút **Refresh** (góc trên bên phải)

**✅ FLUTTER READY khi:**
- Tab Camera hiển thị video
- Góc trên trái có badge "Relay Connected"
- Không có lỗi "Camera offline"

---

## 🔄 FLOW HOẠT ĐỘNG HOÀN CHỈNH

### Lần đầu tiên (chưa có WiFi)

```
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 1: ESP32-CAM                                           │
├─────────────────────────────────────────────────────────────┤
│ 1. Cắm nguồn ESP32                                          │
│ 2. ESP32 boot → BLE mode (LED nhấp nháy)                   │
│ 3. Serial Monitor: "BLE ready"                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 2: Flutter App (BLE Provisioning)                     │
├─────────────────────────────────────────────────────────────┤
│ 1. Mở Flutter app                                           │
│ 2. Tab Devices → Bấm "+"                                    │
│ 3. Chọn "BLE WiFi Setup"                                    │
│ 4. Scan → Chọn ESP32CAM-XXXX                                │
│ 5. Chọn WiFi → Nhập password                                │
│ 6. ESP32 kết nối WiFi → Trả về IP                          │
│ 7. ESP32 restart → Camera mode                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 3: Python AI Server                                    │
├─────────────────────────────────────────────────────────────┤
│ 1. Cập nhật ESP32_IP trong face_recognition_advanced.py    │
│ 2. python face_recognition_advanced.py                     │
│ 3. Đợi log "MQTT connected"                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 4: Flutter App (Cấu hình AI Server)                   │
├─────────────────────────────────────────────────────────────┤
│ 1. Chạy ipconfig → Lấy IP máy tính                         │
│ 2. Flutter app → Settings → AI Server                       │
│ 3. Nhập IP máy tính + port 5000                            │
│ 4. Save                                                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 5: Xem Camera                                          │
├─────────────────────────────────────────────────────────────┤
│ 1. Tab Camera                                                │
│ 2. Thấy video stream ✅                                      │
└─────────────────────────────────────────────────────────────┘
```

### Các lần sau (đã có WiFi)

```
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 1: ESP32-CAM                                           │
├─────────────────────────────────────────────────────────────┤
│ 1. Cắm nguồn                                                 │
│ 2. Tự động kết nối WiFi (đã lưu)                            │
│ 3. LED sáng → Ready                                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 2: Python AI Server                                    │
├─────────────────────────────────────────────────────────────┤
│ 1. python face_recognition_advanced.py                     │
│ 2. Đợi "MQTT connected"                                      │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ BƯỚC 3: Flutter App                                         │
├─────────────────────────────────────────────────────────────┤
│ 1. Mở app                                                    │
│ 2. Tab Camera → Thấy video ✅                                │
└─────────────────────────────────────────────────────────────┘
```

---

## ⚠️ LỖI THƯỜNG GẶP

### Lỗi 1: Python báo "ESP32 không phản hồi"

**Nguyên nhân:** ESP32 chưa chạy hoặc IP sai

**Giải pháp:**
1. Kiểm tra ESP32 có nguồn không
2. Kiểm tra Serial Monitor ESP32 có hiển thị IP không
3. Cập nhật ESP32_IP trong Python code
4. Restart Python server

### Lỗi 2: Flutter không thấy camera

**Nguyên nhân:** Python server chưa chạy hoặc AI Server IP sai

**Giải pháp:**
1. Kiểm tra Python server có chạy không
2. Kiểm tra AI Server IP trong Flutter app
3. Chạy `ipconfig` để lấy IP máy tính
4. Cập nhật AI Server IP trong Flutter
5. Bấm nút Refresh

### Lỗi 3: ESP32 không kết nối WiFi

**Nguyên nhân:** SSID/Password sai hoặc WiFi xa

**Giải pháp:**
1. Factory reset ESP32 (giữ nút BOOT 3 giây)
2. Làm lại BLE Provisioning
3. Kiểm tra SSID/Password đúng chưa
4. Đưa ESP32 gần router

---

## 📝 CHECKLIST TRƯỚC KHI CHẠY

### Hardware
- [ ] ESP32-CAM có nguồn 5V
- [ ] USB-TTL adapter (nếu cần upload code)
- [ ] Điện thoại Android/iOS
- [ ] Máy tính (chạy Python)

### Software
- [ ] Arduino IDE (upload ESP32)
- [ ] Python 3.8+ (chạy AI server)
- [ ] Flutter SDK (build app) hoặc APK/IPA đã build
- [ ] Dependencies đã cài (`pip install -r requirements_advanced.txt`)

### Network
- [ ] ESP32 và máy tính cùng mạng WiFi
- [ ] Firewall không block port 5000
- [ ] Router không block ESP32

### Configuration
- [ ] ESP32_IP đã cập nhật trong Python code
- [ ] AI Server IP đã cấu hình trong Flutter app
- [ ] WiFi credentials đã provisioning cho ESP32

---

## 🎯 SCRIPT TỰ ĐỘNG (WINDOWS)

### Tạo file `start_system.bat`

```batch
@echo off
echo ========================================
echo SMART HOME ESP32-CAM STARTUP
echo ========================================
echo.

echo [1/3] Checking ESP32-CAM...
echo Please make sure ESP32-CAM is powered on
echo and connected to WiFi (LED should be ON)
pause

echo.
echo [2/3] Starting Python AI Server...
cd ESP32CAM
start cmd /k "python face_recognition_advanced.py"
timeout /t 5

echo.
echo [3/3] Starting Flutter App...
cd ..\FLUTTER
start cmd /k "flutter run"

echo.
echo ========================================
echo SYSTEM STARTED!
echo ========================================
echo.
echo Python Server: http://localhost:5000
echo ESP32 Stream: http://192.168.1.112:81/stream
echo.
pause
```

### Cách dùng:
```bash
# Double-click file start_system.bat
# Hoặc chạy trong Command Prompt:
start_system.bat
```

---

## 🎓 KẾT LUẬN

**Thứ tự bắt buộc:**
1. ✅ **ESP32-CAM** (nguồn video)
2. ✅ **Python AI Server** (relay + AI)
3. ✅ **Flutter App** (UI)

**Không được đảo thứ tự vì:**
- Python cần ESP32 để lấy stream
- Flutter cần Python để hiển thị video
- ESP32 độc lập, không phụ thuộc ai

**Mẹo:**
- Để ESP32 luôn cắm nguồn (tự động kết nối WiFi)
- Tạo script tự động chạy Python khi máy tính boot
- Dùng APK/IPA thay vì `flutter run` để tiện hơn

**Lưu ý:**
- ESP32 chỉ cần chạy 1 lần (trừ khi mất điện)
- Python cần chạy mỗi khi máy tính restart
- Flutter app có thể đóng/mở bất cứ lúc nào
