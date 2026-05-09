# 🏠 Smart Home ESP32-CAM App

Flutter app for ESP32-CAM face recognition smart home system with MQTT communication.

## ✨ Features

- 📱 **Face Recognition**: Real-time face detection and recognition
- 🔐 **Bluetooth Provisioning**: Easy WiFi setup for ESP32-CAM
- 📡 **MQTT Communication**: Real-time device control via HiveMQ/Mosquitto
- 🎯 **Smart Door Control**: Automatic door unlock for recognized faces
- 📊 **Activity Monitoring**: View access logs and system status
- 🌐 **Multi-platform**: Android, iOS, and Web support

## 🚀 Quick Start

### Prerequisites

- Flutter SDK 3.24.3+
- Android Studio / Xcode
- ESP32-CAM hardware
- Python AI server running

### Installation

1. **Clone repository**
   ```bash
   git clone <your-repo-url>
   cd FLUTTER
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure settings**
   Edit `lib/config.dart` with your settings:
   ```dart
   // MQTT Broker (HiveMQ or Mosquitto)
   static const String hivemqHost = 'your-mqtt-broker.com';
   static const String hivemqUsername = 'your-username';
   static const String hivemqPassword = 'your-password';
   
   // ESP32-CAM IP
   static const String esp32IP = '192.168.1.100';
   
   // Python AI Server
   static const String pythonAIUrl = 'http://192.168.1.101:5000';
   ```

4. **Run the app**
   ```bash
   flutter run
   ```

## 📱 Sideloadly Installation

### For Android:
1. Download APK from [Releases](../../releases)
2. Install Sideloadly from [sideloadly.io](https://sideloadly.io)
3. Connect Android device with USB debugging enabled
4. Drag APK to Sideloadly and install

### For iOS:
1. Download IPA from [Releases](../../releases)
2. Install Sideloadly from [sideloadly.io](https://sideloadly.io)
3. Connect iPhone/iPad to computer
4. Sign with Apple ID in Sideloadly
5. Drag IPA to Sideloadly and install

## 🔧 Configuration

### ESP32-CAM Setup
1. Flash ESP32-CAM with provided Arduino code
2. Power on ESP32-CAM
3. Connect via Bluetooth using the app
4. Configure WiFi credentials
5. ESP32-CAM will auto-connect on future boots

### MQTT Broker
- **HiveMQ Cloud**: Free 15-day trial, easy setup
- **Mosquitto**: Self-hosted or public broker
- **AWS IoT Core**: Production-grade (paid)

### Python AI Server
1. Install dependencies: `pip install -r requirements.txt`
2. Run server: `python face_recognition_advanced.py`
3. Server will be available at `http://localhost:5000`

## 📡 MQTT Topics

| Topic | Description |
|-------|-------------|
| `home/face_recognition/result` | Face recognition results |
| `home/face_recognition/alert` | Stranger detection alerts |
| `home/devices/door/*/command` | Door control commands |
| `home/devices/light/*/command` | Light control commands |
| `home/logs/activity` | System activity logs |

## 🏗️ Architecture

```
Flutter App ←→ MQTT Broker ←→ Python AI ←→ ESP32-CAM
     ↓              ↓              ↓           ↓
  UI Control    Message Hub    Face AI    Camera Stream
```

## 🔒 Permissions

### Android
- Camera: Face enrollment and recognition
- Location: Bluetooth device discovery
- Storage: Save user data and logs

### iOS
- Camera: Face enrollment and recognition
- Bluetooth: ESP32-CAM provisioning
- Local Network: ESP32-CAM communication

## 🐛 Troubleshooting

### Common Issues

**ESP32-CAM not found**
- Ensure ESP32-CAM is powered and in provisioning mode
- Check Bluetooth is enabled on phone
- Try restarting ESP32-CAM

**MQTT connection failed**
- Verify broker credentials in `config.dart`
- Check network connectivity
- Try switching to Mosquitto public broker for testing

**Face recognition not working**
- Ensure Python AI server is running
- Check ESP32-CAM IP address is correct
- Verify camera stream is accessible

**App crashes on startup**
- Check Flutter version compatibility
- Run `flutter clean && flutter pub get`
- Verify all dependencies are installed

## 📦 Build from Source

### Android APK
```bash
flutter build apk --release --split-per-abi
```

### iOS IPA
```bash
flutter build ios --release --no-codesign
# Then create IPA manually or use Xcode
```

### Web
```bash
flutter build web --release
```

## 🤝 Contributing

1. Fork the repository
2. Create feature branch: `git checkout -b feature/amazing-feature`
3. Commit changes: `git commit -m 'Add amazing feature'`
4. Push to branch: `git push origin feature/amazing-feature`
5. Open Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Flutter team for the amazing framework
- ESP32 community for hardware support
- HiveMQ for MQTT cloud service
- MediaPipe for face detection AI

## 📞 Support

- 📧 Email: your-email@example.com
- 🐛 Issues: [GitHub Issues](../../issues)
- 📖 Wiki: [Project Wiki](../../wiki)

---

**Made with ❤️ for Smart Home enthusiasts**