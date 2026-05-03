# 🎥 CÁCH HOẠT ĐỘNG ESP32-CAM CHI TIẾT

## 📋 TỔNG QUAN

ESP32-CAM trong dự án này có 2 chế độ hoạt động:
1. **BLE Provisioning Mode** - Cấu hình WiFi lần đầu
2. **Camera Streaming Mode** - Stream video sau khi đã có WiFi

---

## 🔄 FLOW HOẠT ĐỘNG TỔNG THỂ

```
┌─────────────────────────────────────────────────────────────┐
│                    ESP32-CAM BOOT                           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ Đọc WiFi đã lưu?      │
                └───────────────────────┘
                    │              │
              ✅ Có WiFi      ❌ Chưa có WiFi
                    │              │
                    ▼              ▼
        ┌──────────────────┐  ┌──────────────────┐
        │ CAMERA MODE      │  │ BLE MODE         │
        │ - Kết nối WiFi   │  │ - Quét WiFi      │
        │ - Init camera    │  │ - Start BLE      │
        │ - Start HTTP     │  │ - Chờ Flutter    │
        │ - Stream MJPEG   │  │ - Nhận SSID/Pass │
        └──────────────────┘  └──────────────────┘
                │                      │
                │                      ▼
                │              ┌──────────────────┐
                │              │ Kết nối WiFi     │
                │              │ Lưu credentials  │
                │              │ Restart ESP32    │
                │              └──────────────────┘
                │                      │
                └──────────────────────┘
                            │
                            ▼
                ┌───────────────────────┐
                │ STREAMING READY       │
                │ LED ON                │
                │ http://IP:81/stream   │
                └───────────────────────┘
```

---

## 🚀 BƯỚC 1: KHỞI ĐỘNG (setup())

### 1.1. Khởi tạo cơ bản
```cpp
void setup() {
  Serial.begin(115200);  // Debug console
  pinMode(BOOT_PIN, INPUT_PULLUP);  // IO0 cho factory reset
  pinMode(LED_PIN, OUTPUT);         // LED GPIO4
  digitalWrite(LED_PIN, LOW);       // Tắt LED
}
```

### 1.2. Đọc WiFi đã lưu
```cpp
void loadAndConnect() {
  prefs.begin("wifi", true);  // Mở Preferences (EEPROM)
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();
  
  if (ssid.isEmpty()) {
    // Chưa có WiFi → Chuyển sang BLE mode
    return;
  }
  
  // Có WiFi → Thử kết nối
  WiFi.begin(ssid.c_str(), pass.c_str());
  WiFi.setSleep(false);  // ⚡ TẮT POWER SAVE → Stream mượt
}
```

**Tại sao tắt WiFi sleep?**
- Power save mode làm WiFi ngủ → frame bị drop
- Tắt sleep → WiFi luôn active → stream ổn định

---

## 📡 BƯỚC 2A: CAMERA MODE (Đã có WiFi)

### 2.1. Khởi tạo Camera
```cpp
bool initCamera() {
  camera_config_t cfg = {};
  
  // ⚙️ Cấu hình pins (AI Thinker ESP32-CAM)
  cfg.pin_d0 = Y2_GPIO_NUM;  // Data pins
  cfg.pin_d1 = Y3_GPIO_NUM;
  // ... (8 data pins total)
  
  cfg.pin_xclk = XCLK_GPIO_NUM;    // Clock
  cfg.pin_pclk = PCLK_GPIO_NUM;    // Pixel clock
  cfg.pin_vsync = VSYNC_GPIO_NUM;  // Vertical sync
  cfg.pin_href = HREF_GPIO_NUM;    // Horizontal ref
  
  // 📸 Cấu hình camera
  cfg.xclk_freq_hz = 10000000;     // 10MHz (ổn định, tiết kiệm điện)
  cfg.pixel_format = PIXFORMAT_JPEG;  // Output JPEG
  cfg.frame_size = FRAMESIZE_QVGA;    // 320x240 pixels
  cfg.jpeg_quality = 15;              // 10=best, 63=worst
  cfg.fb_count = 1;                   // 1 frame buffer
  cfg.grab_mode = CAMERA_GRAB_LATEST; // ⚡ Luôn lấy frame mới nhất
  
  return esp_camera_init(&cfg) == ESP_OK;
}
```

**Tại sao CAMERA_GRAB_LATEST?**
- Mode mặc định: Queue frames → lag khi client chậm
- GRAB_LATEST: Bỏ qua frame cũ → luôn lấy frame mới nhất → không lag

### 2.2. Khởi động HTTP Server
```cpp
void startCameraServer() {
  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  cfg.server_port = 81;           // Port 81 (không phải 80)
  cfg.max_open_sockets = 4;       // Tối đa 4 client
  cfg.stack_size = 8192;          // 8KB stack
  cfg.recv_wait_timeout = 10;     // Timeout 10s
  
  httpd_start(&httpd, &cfg);
  
  // Đăng ký 3 endpoints
  httpd_register_uri_handler(httpd, &stream_uri);   // /stream
  httpd_register_uri_handler(httpd, &capture_uri);  // /capture
  httpd_register_uri_handler(httpd, &status_uri);   // /status
}
```

### 2.3. MJPEG Stream Handler
```cpp
static esp_err_t stream_handler(httpd_req_t* req) {
  // Set HTTP headers
  httpd_resp_set_type(req, "multipart/x-mixed-replace;boundary=...");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  
  TickType_t lastFrame = xTaskGetTickCount();
  
  while (true) {
    // 1. Lấy frame từ camera
    camera_fb_t* fb = esp_camera_fb_get();
    if (!fb) continue;
    
    // 2. Gửi boundary
    httpd_resp_send_chunk(req, BOUNDARY, strlen(BOUNDARY));
    
    // 3. Gửi JPEG header
    char hdr[64];
    snprintf(hdr, sizeof(hdr), 
      "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n", 
      fb->len);
    httpd_resp_send_chunk(req, hdr, strlen(hdr));
    
    // 4. Gửi JPEG data
    httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    
    // 5. Trả frame buffer về pool
    esp_camera_fb_return(fb);
    
    // 6. ⏱️ Throttle FPS: Chờ đủ 100ms (10 FPS)
    vTaskDelayUntil(&lastFrame, pdMS_TO_TICKS(100));
  }
}
```

**MJPEG Format:**
```
--BOUNDARY
Content-Type: image/jpeg
Content-Length: 15234

[JPEG binary data]
--BOUNDARY
Content-Type: image/jpeg
Content-Length: 15678

[JPEG binary data]
--BOUNDARY
...
```

### 2.4. Capture Handler (Single Frame)
```cpp
static esp_err_t capture_handler(httpd_req_t* req) {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) {
    httpd_resp_send_500(req);
    return ESP_FAIL;
  }
  
  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  
  return ESP_OK;
}
```

**Sử dụng:**
- Python AI server gọi `/capture` để lấy 1 frame
- Nhẹ hơn stream (không cần maintain connection)

---

## 🔵 BƯỚC 2B: BLE MODE (Chưa có WiFi)

### 2.1. Quét WiFi Networks
```cpp
void initBLE() {
  // 1. Quét WiFi trước khi start BLE
  WiFi.mode(WIFI_STA);
  int n = WiFi.scanNetworks();
  
  String list = "";
  for (int i = 0; i < min(n, 10); i++) {
    if (WiFi.SSID(i).length() > 0) {
      list += WiFi.SSID(i) + ";";  // Ngăn cách bằng dấu ;
    }
  }
  WiFi.scanDelete();
  
  // 2. Tắt WiFi để giải phóng RAM cho BLE
  WiFi.mode(WIFI_OFF);
  delay(500);
}
```

**Tại sao tắt WiFi trước khi start BLE?**
- ESP32 RAM hạn chế (~400KB)
- WiFi + BLE cùng lúc → thiếu RAM → crash
- Tắt WiFi → giải phóng ~50KB RAM

### 2.2. Tạo BLE Device Name
```cpp
// Lấy MAC address
uint8_t mac[6];
WiFi.macAddress(mac);

// Tạo tên unique: ESP32CAM-A1B2
String name = "ESP32CAM-" + 
              String(mac[4], HEX) + 
              String(mac[5], HEX);
name.toUpperCase();
```

### 2.3. Khởi tạo BLE Server
```cpp
BLEDevice::init(name.c_str());
BLEServer* srv = BLEDevice::createServer();
srv->setCallbacks(new BLEConn());  // Connection callbacks

BLEService* svc = srv->createService(SERVICE_UUID);
```

### 2.4. Tạo BLE Characteristics
```cpp
// 1. SSID Characteristic (Write)
auto* ssidChar = svc->createCharacteristic(
  SSID_UUID, 
  BLECharacteristic::PROPERTY_WRITE
);
ssidChar->setCallbacks(new SSIDcb());

// 2. Password Characteristic (Write)
auto* passChar = svc->createCharacteristic(
  PASS_UUID,
  BLECharacteristic::PROPERTY_WRITE
);
passChar->setCallbacks(new PASScb());

// 3. Status Characteristic (Read + Notify)
pStatus = svc->createCharacteristic(
  STATUS_UUID,
  BLECharacteristic::PROPERTY_READ | 
  BLECharacteristic::PROPERTY_NOTIFY
);
pStatus->addDescriptor(new BLE2902());  // Enable notifications
pStatus->setValue("ready");

// 4. WiFi List Characteristic (Read)
pWifiList = svc->createCharacteristic(
  WIFILIST_UUID,
  BLECharacteristic::PROPERTY_READ
);
pWifiList->setValue(list.c_str());  // Danh sách WiFi đã quét
```

### 2.5. Start BLE Advertising
```cpp
svc->start();
BLEAdvertising* adv = BLEDevice::getAdvertising();
adv->addServiceUUID(SERVICE_UUID);
adv->setScanResponse(true);
BLEDevice::startAdvertising();
```

**BLE Advertising:**
- ESP32 broadcast tên "ESP32CAM-XXXX"
- Flutter app scan và tìm thấy
- User bấm connect

---

## 📲 BƯỚC 3: BLE PROVISIONING FLOW

### 3.1. Flutter App Connect
```
Flutter App                    ESP32-CAM
    │                              │
    │──── BLE Connect ────────────>│
    │<──── Connected ──────────────│
    │                              │
    │──── Read WiFi List ─────────>│
    │<──── "WiFi1;WiFi2;WiFi3" ────│
```

### 3.2. User Chọn WiFi và Nhập Password
```
Flutter App                    ESP32-CAM
    │                              │
    │──── Write SSID ─────────────>│ (SSIDcb triggered)
    │                              │ rxSSID = "MyWiFi"
    │                              │
    │──── Write Password ─────────>│ (PASScb triggered)
    │                              │ rxPass = "12345678"
    │                              │ wifiReceived = true
```

### 3.3. ESP32 Kết Nối WiFi
```cpp
// Trong loop()
if (wifiReceived) {
  wifiReceived = false;
  
  // 1. Notify Flutter: "connecting"
  pStatus->setValue("connecting");
  pStatus->notify();
  
  // 2. Thử kết nối WiFi
  if (connectWiFi(rxSSID, rxPass)) {
    // 3. Lưu vào EEPROM
    prefs.begin("wifi", false);
    prefs.putString("ssid", rxSSID);
    prefs.putString("pass", rxPass);
    prefs.end();
    
    // 4. Notify Flutter: "connected|192.168.1.100"
    String s = "connected|" + WiFi.localIP().toString();
    pStatus->setValue(s.c_str());
    pStatus->notify();
    
    // 5. Restart để chuyển sang Camera mode
    delay(1500);
    ESP.restart();
  } else {
    // Kết nối thất bại
    pStatus->setValue("failed");
    pStatus->notify();
  }
}
```

### 3.4. Restart và Chuyển Sang Camera Mode
```
ESP32 Restart
    │
    ▼
loadAndConnect()
    │
    ├─ Đọc WiFi từ EEPROM: "MyWiFi"
    ├─ Kết nối WiFi thành công
    ├─ Init camera
    ├─ Start HTTP server
    └─ LED ON → Ready!
```

---

## 🔁 BƯỚC 4: LOOP() - Chạy Liên Tục

### 4.1. Factory Reset Check
```cpp
void checkFactoryReset() {
  if (digitalRead(BOOT_PIN) != LOW) return;
  
  unsigned long t = millis();
  while (digitalRead(BOOT_PIN) == LOW) {
    // Nhấp nháy LED
    digitalWrite(LED_PIN, (millis() - t) / 500 % 2);
    
    // Giữ ≥ 3 giây → Reset
    if (millis() - t >= 3000) {
      prefs.begin("wifi", false);
      prefs.clear();  // Xóa WiFi đã lưu
      prefs.end();
      ESP.restart();  // Restart → BLE mode
    }
  }
}
```

### 4.2. WiFi Watchdog
```cpp
// Kiểm tra mỗi 5 giây
if (WiFi.status() != WL_CONNECTED && httpd != nullptr) {
  Serial.println("⚠️ WiFi lost — reconnecting...");
  
  // Đọc WiFi đã lưu
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();
  
  // Thử kết nối lại
  if (!ssid.isEmpty()) {
    connectWiFi(ssid, pass);
  }
}

delay(5000);  // Check mỗi 5s
```

---

## 🎯 TỐI ƯU HÓA QUAN TRỌNG

### 1. WiFi.setSleep(false)
```cpp
WiFi.setSleep(false);  // Tắt power save
```
**Lý do:**
- Power save → WiFi ngủ → frame drop
- Tắt sleep → stream mượt mà

### 2. CAMERA_GRAB_LATEST
```cpp
cfg.grab_mode = CAMERA_GRAB_LATEST;
```
**Lý do:**
- Mode mặc định: Queue frames → lag
- GRAB_LATEST: Bỏ frame cũ → real-time

### 3. Frame Rate Throttling
```cpp
vTaskDelayUntil(&lastFrame, pdMS_TO_TICKS(100));  // 10 FPS
```
**Lý do:**
- Không throttle → ESP32 quá tải
- 10 FPS → cân bằng mượt mà & ổn định

### 4. Single Frame Buffer
```cpp
cfg.fb_count = 1;
```
**Lý do:**
- 2 buffers → tốn RAM, không cần thiết
- 1 buffer + GRAB_LATEST → đủ dùng

### 5. QVGA Resolution
```cpp
cfg.frame_size = FRAMESIZE_QVGA;  // 320x240
```
**Lý do:**
- VGA (640x480) → frame lớn → chậm
- QVGA → nhỏ gọn, đủ cho nhận diện

---

## 📊 MEMORY USAGE

```
Total RAM: ~400KB
├─ WiFi Stack: ~50KB
├─ Camera Buffer: ~20KB (QVGA JPEG)
├─ HTTP Server: ~10KB
├─ BLE Stack: ~50KB (khi active)
└─ Free: ~270KB
```

**Chiến lược:**
- Không chạy WiFi + BLE cùng lúc
- Tắt WiFi trước khi start BLE
- Restart để chuyển mode

---

## 🔌 HTTP ENDPOINTS

### 1. /stream (MJPEG Stream)
```
GET http://192.168.1.100:81/stream
Response: multipart/x-mixed-replace
FPS: 10 frames/second
```

### 2. /capture (Single Frame)
```
GET http://192.168.1.100:81/capture
Response: image/jpeg
Size: ~15-20KB
```

### 3. /status (JSON Status)
```
GET http://192.168.1.100:81/status
Response: {
  "status": "ok",
  "ip": "192.168.1.100",
  "fps": 10
}
```

---

## 🐛 ERROR HANDLING

### 1. Camera Init Failed
```cpp
if (esp_camera_init(&cfg) != ESP_OK) {
  Serial.println("❌ Camera init failed");
  return false;
}
```
**Nguyên nhân:**
- Pins sai
- Camera module lỗi
- Thiếu nguồn

### 2. WiFi Connection Failed
```cpp
if (WiFi.status() != WL_CONNECTED) {
  Serial.println("❌ WiFi failed → BLE mode");
  WiFi.disconnect(true);
}
```
**Nguyên nhân:**
- SSID/Password sai
- Router xa
- Tín hiệu yếu

### 3. HTTP Server Failed
```cpp
if (httpd_start(&httpd, &cfg) != ESP_OK) {
  Serial.println("❌ HTTP server failed");
}
```
**Nguyên nhân:**
- Port 81 bị chiếm
- Thiếu RAM
- Config sai

---

## 💡 TIPS & TRICKS

### 1. Debug qua Serial Monitor
```cpp
Serial.begin(115200);
Serial.println("✅ Camera OK");
Serial.printf("IP: %s\n", WiFi.localIP().toString().c_str());
```

### 2. LED Status Indicator
```cpp
digitalWrite(LED_PIN, HIGH);  // Streaming ready
digitalWrite(LED_PIN, LOW);   // Not ready
```

### 3. Factory Reset
- Giữ nút BOOT (IO0) 3 giây
- LED nhấp nháy
- Xóa WiFi đã lưu
- Restart → BLE mode

### 4. Test Stream
```bash
# Browser
http://192.168.1.100:81/stream

# VLC Media Player
Network Stream → http://192.168.1.100:81/stream

# Python
import requests
r = requests.get('http://192.168.1.100:81/capture')
with open('frame.jpg', 'wb') as f:
    f.write(r.content)
```

---

## 🎓 KẾT LUẬN

ESP32-CAM hoạt động theo 2 mode:
1. **BLE Mode:** Cấu hình WiFi lần đầu
2. **Camera Mode:** Stream video sau khi có WiFi

**Ưu điểm:**
- ✅ Không cần hardcode WiFi
- ✅ Tự động reconnect
- ✅ Stream ổn định 10 FPS
- ✅ Tiết kiệm RAM
- ✅ Factory reset dễ dàng

**Hạn chế:**
- ❌ Chỉ 1 client stream trực tiếp (giải quyết bằng Python relay)
- ❌ Không có AI onboard (giải quyết bằng Python server)
- ❌ RAM hạn chế (400KB)

**Giải pháp:**
- Python relay cho multi-client
- Python AI cho face recognition
- MQTT cho communication
