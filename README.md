# ESP32-CAM Smart Home Face Recognition System

Hệ thống nhà thông minh với nhận diện khuôn mặt sử dụng ESP32-CAM, Python AI, và Flutter.

## 🚀 Tính năng

- **Nhận diện khuôn mặt** với MediaPipe và Template Matching
- **BLE WiFi Provisioning** - Cấu hình WiFi qua Bluetooth
- **Motion Detection** - Phát hiện chuyển động bằng Frame Diff
- **Real-time Streaming** - Stream video trực tiếp từ ESP32-CAM
- **Flutter Mobile App** - Giao diện điều khiển trên điện thoại

## 📁 Cấu trúc thư mục

```
├── ESP32CAM/                          # Backend & Firmware
│   ├── esp32cam_ble_provisioning/     # ESP32 BLE WiFi Provisioning
│   ├── esp32cam_optimized/            # ESP32 Camera Firmware (tối ưu)
│   ├── face_recognition_advanced.py   # Python AI Server
│   ├── relay_server.js                # Node.js Relay Server
│   └── requirements_advanced.txt      # Python dependencies
│
└── lib/                               # Flutter App
    ├── ble_wifi_provisioning_screen.dart
    ├── front_door_cam.dart
    ├── home_dashboard.dart
    └── ...
```

## 🛠️ Cài đặt

### 1. ESP32-CAM Firmware

1. Mở Arduino IDE
2. Cài đặt ESP32 board support
3. Upload `ESP32CAM/esp32cam_ble_provisioning/esp32cam_ble_provisioning.ino`

### 2. Python AI Server

```bash
cd ESP32CAM
pip install -r requirements_advanced.txt
python face_recognition_advanced.py
```

### 3. Node.js Relay Server

```bash
cd ESP32CAM
npm install
npm start
```

### 4. Flutter App

```bash
flutter pub get
flutter run
```

## 📖 Hướng dẫn sử dụng

Chi tiết xem file [FACE_ESP32CAM.md](FACE_ESP32CAM.md)

## 🔧 Cấu hình

- **ESP32-CAM IP**: Cấu hình trong `relay_server.js`
- **Relay Server IP**: Cấu hình trong `lib/front_door_cam.dart`
- **Recognition Threshold**: 0.50 (50%) trong `face_recognition_advanced.py`

## 📦 Dependencies

### ESP32
- ESP32 Camera Driver
- WiFi
- BLE (Bluetooth Low Energy)

### Python
- Flask
- OpenCV
- MediaPipe
- NumPy
- Pillow

### Node.js
- Express
- WebSocket
- Axios

### Flutter
- flutter_mjpeg
- flutter_blue_plus
- sqflite
- http

## 📝 License

MIT License

## 👤 Author

Nguyễn Phùng Thịnh
