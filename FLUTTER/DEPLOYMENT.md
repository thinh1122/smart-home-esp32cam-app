# 🚀 Deployment Guide

## 📋 Pre-deployment Checklist

### ✅ Code Ready
- [ ] All features implemented and tested
- [ ] No compilation errors (`flutter analyze`)
- [ ] Dependencies updated (`flutter pub get`)
- [ ] Config values set in `lib/config.dart`

### ✅ GitHub Setup
- [ ] Repository created on GitHub
- [ ] Code pushed to `main` branch
- [ ] GitHub Actions enabled
- [ ] Secrets configured (if needed)

### ✅ Build Configuration
- [ ] Android permissions in `AndroidManifest.xml`
- [ ] iOS permissions in `Info.plist`
- [ ] App name and version in `pubspec.yaml`
- [ ] Icons and splash screens configured

---

## 🔧 GitHub Actions Deployment

### 1. Push to GitHub
```bash
git add .
git commit -m "🚀 Ready for deployment"
git push origin main
```

### 2. Monitor Build
- Go to your GitHub repository
- Click **Actions** tab
- Watch the build process
- Download artifacts when complete

### 3. Build Outputs
| Platform | File | Use Case |
|----------|------|----------|
| Android | `SmartHome-Android-arm64.apk` | Sideloadly installation |
| iOS | `SmartHome-iOS.ipa` | Sideloadly installation |
| Web | `web-build.zip` | Web hosting |

---

## 📱 Sideloadly Installation

### Android Installation

1. **Download Sideloadly**
   - Visit [sideloadly.io](https://sideloadly.io)
   - Download for Windows/Mac/Linux

2. **Prepare Android Device**
   ```
   Settings → About Phone → Tap "Build Number" 7 times
   Settings → Developer Options → Enable "USB Debugging"
   ```

3. **Install APK**
   - Connect device via USB
   - Open Sideloadly
   - Drag `SmartHome-Android-arm64.apk` to Sideloadly
   - Click "Start Sideloading"
   - Wait for installation to complete

### iOS Installation

1. **Requirements**
   - Apple ID (free or paid developer account)
   - iPhone/iPad with iOS 12+
   - Sideloadly installed

2. **Install IPA**
   - Connect iPhone via USB
   - Open Sideloadly
   - Enter Apple ID credentials
   - Drag `SmartHome-iOS.ipa` to Sideloadly
   - Click "Start Sideloading"
   - Trust developer profile on device

3. **Trust App**
   ```
   Settings → General → VPN & Device Management
   → Developer App → Trust "Your Apple ID"
   ```

---

## 🔄 Automated Deployment

### GitHub Actions Workflow

The `.github/workflows/build-flutter.yml` automatically:

1. **Triggers on**:
   - Push to `main` branch
   - Pull requests
   - Manual workflow dispatch

2. **Build Process**:
   - Setup Flutter environment
   - Install dependencies
   - Run code analysis
   - Execute tests
   - Build for all platforms
   - Create GitHub release
   - Upload artifacts

3. **Artifacts**:
   - Android APK (arm64, armeabi-v7a, x86_64)
   - iOS IPA (unsigned)
   - Web build files

### Release Management

Each successful build creates:
- **Git tag**: `v{build_number}`
- **Release notes**: Auto-generated with features
- **Download links**: Direct APK/IPA downloads

---

## 🛠️ Local Testing

### Quick Test Build
```bash
# Windows
build_test.bat

# Mac/Linux
chmod +x build_test.sh
./build_test.sh
```

### Manual Build Commands
```bash
# Get dependencies
flutter pub get

# Analyze code
flutter analyze

# Test (optional)
flutter test

# Build Android APK
flutter build apk --release --split-per-abi

# Build iOS (Mac only)
flutter build ios --release --no-codesign

# Build Web
flutter build web --release
```

---

## 📊 Build Optimization

### APK Size Reduction
```bash
# Split APKs by architecture
flutter build apk --release --split-per-abi

# Enable R8 obfuscation
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

### Performance Optimization
- Enable tree-shaking: `--tree-shake-icons`
- Optimize images: Use WebP format
- Minimize dependencies: Remove unused packages
- Code splitting: Lazy load heavy features

---

## 🔐 Security Considerations

### Code Obfuscation
```bash
flutter build apk --release --obfuscate --split-debug-info=build/debug-info
```

### API Keys Protection
- Never commit API keys to Git
- Use environment variables
- Implement key rotation
- Use GitHub Secrets for CI/CD

### Network Security
- Use HTTPS/WSS for all connections
- Implement certificate pinning
- Validate server certificates
- Encrypt sensitive data

---

## 📈 Monitoring & Analytics

### Crash Reporting
- Firebase Crashlytics
- Sentry integration
- Custom error logging

### Usage Analytics
- Firebase Analytics
- Custom event tracking
- Performance monitoring

### Update Management
- In-app update prompts
- Version checking
- Rollback capabilities

---

## 🚨 Troubleshooting

### Common Build Issues

**Gradle build failed**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk
```

**iOS build failed**
```bash
cd ios
rm -rf Pods Podfile.lock
pod install
cd ..
flutter clean
flutter build ios
```

**Dependencies conflict**
```bash
flutter pub deps
flutter pub upgrade --major-versions
```

### Sideloadly Issues

**"App not installed" on Android**
- Enable "Install from Unknown Sources"
- Check available storage space
- Try different USB cable/port

**"Unable to install" on iOS**
- Verify Apple ID credentials
- Check device storage
- Trust developer certificate
- Try different Apple ID

---

## 📞 Support

### Getting Help
- 📖 [Flutter Documentation](https://flutter.dev/docs)
- 🐛 [GitHub Issues](../../issues)
- 💬 [Discord Community](https://discord.gg/flutter)
- 📧 Email: support@yourapp.com

### Reporting Issues
When reporting issues, include:
- Device model and OS version
- Flutter version (`flutter --version`)
- Error logs and screenshots
- Steps to reproduce

---

**Happy Deploying! 🎉**