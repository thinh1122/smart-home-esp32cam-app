# Hướng dẫn đẩy code lên GitHub

Tài liệu này ghi lại các lệnh Git đã sử dụng để đẩy project lên GitHub.

---

## 📋 Các lệnh đã chạy

### 1. Kiểm tra Git đã cài đặt chưa
```bash
git --version
```
**Chức năng**: Kiểm tra phiên bản Git đã cài trên máy. Nếu chưa có thì cần cài Git trước.

---

### 2. Khởi tạo Git repository
```bash
git init
```
**Chức năng**: Tạo một Git repository mới trong thư mục hiện tại. Lệnh này tạo folder `.git/` để Git theo dõi các thay đổi.

---

### 3. Kiểm tra trạng thái Git
```bash
git status
```
**Chức năng**: Xem trạng thái hiện tại của repository - file nào đã thay đổi, file nào chưa được track, file nào đã staged.

---

### 4. Thêm file vào staging area
```bash
git add ESP32CAM/ lib/ README.md FACE_ESP32CAM.md pubspec.yaml pubspec.lock .gitignore analysis_options.yaml .metadata
```
**Chức năng**: Thêm các file/folder vào staging area để chuẩn bị commit. Chỉ những file được `add` mới được commit.

**Các cách dùng khác:**
- `git add .` - Thêm tất cả file trong thư mục hiện tại
- `git add *.dart` - Thêm tất cả file .dart
- `git add file.txt` - Thêm 1 file cụ thể

---

### 5. Commit các thay đổi
```bash
git commit -m "Initial commit: ESP32-CAM Face Recognition Smart Home System with BLE WiFi Provisioning"
```
**Chức năng**: Lưu các thay đổi đã staged vào lịch sử Git với một message mô tả.

**Giải thích:**
- `-m "message"` - Thêm commit message trực tiếp
- Nếu không có `-m`, Git sẽ mở text editor để nhập message

---

### 6. Thêm remote repository
```bash
git remote add origin https://github.com/thinh1122/smarthome_DATN.git
```
**Chức năng**: Liên kết repository local với repository trên GitHub.

**Giải thích:**
- `origin` - Tên mặc định cho remote repository (có thể đặt tên khác)
- URL - Địa chỉ repository trên GitHub

**Kiểm tra remote:**
```bash
git remote -v
```

---

### 7. Đổi tên branch
```bash
git branch -M main
```
**Chức năng**: Đổi tên branch hiện tại thành `main`.

**Giải thích:**
- Git cũ tạo branch mặc định là `master`
- GitHub hiện tại dùng `main` làm branch mặc định
- `-M` - Force rename (ghi đè nếu đã tồn tại)

---

### 8. Push code lên GitHub
```bash
git push -u origin main
```
**Chức năng**: Đẩy code từ local lên GitHub repository.

**Giải thích:**
- `origin` - Tên remote repository
- `main` - Tên branch cần push
- `-u` (hoặc `--set-upstream`) - Thiết lập tracking, lần sau chỉ cần `git push`

---

## 🔄 Quy trình làm việc với Git (sau này)

### Khi có thay đổi code mới:

```bash
# 1. Kiểm tra file nào đã thay đổi
git status

# 2. Thêm file vào staging
git add .                    # Thêm tất cả
# hoặc
git add file1.dart file2.py  # Thêm từng file

# 3. Commit với message
git commit -m "Mô tả thay đổi"

# 4. Push lên GitHub
git push
```

---

## 📥 Clone repository về máy khác

```bash
git clone https://github.com/thinh1122/smarthome_DATN.git
```
**Chức năng**: Tải toàn bộ repository từ GitHub về máy local.

---

## 🔍 Các lệnh Git hữu ích khác

### Xem lịch sử commit
```bash
git log
git log --oneline          # Xem ngắn gọn
git log --graph --oneline  # Xem dạng đồ thị
```

### Xem thay đổi chưa commit
```bash
git diff                   # Xem thay đổi chưa staged
git diff --staged          # Xem thay đổi đã staged
```

### Hủy thay đổi
```bash
git restore file.txt       # Hủy thay đổi chưa staged
git restore --staged file.txt  # Bỏ file khỏi staging
git reset HEAD~1           # Hủy commit cuối (giữ thay đổi)
```

### Tạo branch mới
```bash
git branch feature-name    # Tạo branch mới
git checkout feature-name  # Chuyển sang branch đó
# hoặc
git checkout -b feature-name  # Tạo và chuyển luôn
```

### Merge branch
```bash
git checkout main          # Chuyển về main
git merge feature-name     # Merge feature vào main
```

### Pull code mới từ GitHub
```bash
git pull origin main       # Kéo code mới về
```

### Xem remote repository
```bash
git remote -v              # Xem danh sách remote
git remote show origin     # Xem chi tiết remote
```

---

## 🚫 File .gitignore

File `.gitignore` giúp Git bỏ qua các file không cần thiết:

```gitignore
# Build files
/build/
/android/app/debug
/android/app/release

# Dependencies
node_modules/
.dart_tool/

# Database & temp files
*.db
temp/
img/

# IDE
.idea/
.vscode/
```

---

## ⚠️ Lưu ý quan trọng

1. **Không commit file nhạy cảm**: 
   - API keys, passwords, tokens
   - Database files với dữ liệu thật
   - File cấu hình có thông tin cá nhân

2. **Viết commit message rõ ràng**:
   - ✅ "Fix: Sửa lỗi nhận diện khuôn mặt khi đeo kính"
   - ✅ "Add: Thêm tính năng BLE WiFi Provisioning"
   - ❌ "update"
   - ❌ "fix bug"

3. **Commit thường xuyên**: 
   - Commit sau mỗi tính năng hoàn thành
   - Không chờ đến cuối ngày mới commit

4. **Pull trước khi Push**:
   - Nếu làm việc nhóm, luôn `git pull` trước khi `git push`

---

## 🔗 Repository của project này

**URL**: https://github.com/thinh1122/smarthome_DATN.git

**Cấu trúc đã push**:
```
├── ESP32CAM/
│   ├── esp32cam_ble_provisioning/
│   ├── esp32cam_optimized/
│   ├── face_recognition_advanced.py
│   ├── relay_server.js
│   ├── package.json
│   └── requirements_advanced.txt
├── lib/
│   ├── ble_wifi_provisioning_screen.dart
│   ├── front_door_cam.dart
│   ├── home_dashboard.dart
│   └── ...
├── README.md
├── FACE_ESP32CAM.md
├── pubspec.yaml
└── .gitignore
```

---

## 📚 Tài liệu tham khảo

- [Git Documentation](https://git-scm.com/doc)
- [GitHub Guides](https://guides.github.com/)
- [Git Cheat Sheet](https://education.github.com/git-cheat-sheet-education.pdf)

---

---

## 🚀 Build Flutter App tự động với GitHub Actions

### Bước 1: Tạo file workflow
```bash
mkdir -p .github/workflows
```
**Chức năng**: Tạo thư mục để chứa file cấu hình GitHub Actions.

---

### Bước 2: Tạo file `.github/workflows/flutter-build.yml`
File này chứa cấu hình để GitHub tự động build APK (Android) và IPA (iOS).

**Nội dung file**: Xem file `.github/workflows/flutter-build.yml`

**Chức năng**:
- ✅ Tự động build APK khi push code lên GitHub
- ✅ Tự động build IPA cho iOS
- ✅ Tự động build AAB (Android App Bundle) cho Google Play
- ✅ Tạo Release tự động khi có tag version

---

### Bước 3: Push file workflow lên GitHub
```bash
# Thêm file workflow vào Git
git add .github/workflows/flutter-build.yml

# Commit với message
git commit -m "Add GitHub Actions workflow for Flutter build (APK & IPA)"

# Push lên GitHub
git push origin main
```

**Chức năng**: Đẩy file cấu hình lên GitHub để kích hoạt tự động build.

---

### Bước 4: Xem quá trình build

1. Vào repository: https://github.com/thinh1122/smarthome_DATN
2. Click tab **"Actions"**
3. Xem workflow **"Flutter Build APK & IPA"** đang chạy
4. Đợi 5-10 phút để build xong

---

### Bước 5: Tải file APK/IPA

Sau khi build xong (màu xanh ✅):

1. Click vào workflow đã chạy xong
2. Scroll xuống phần **"Artifacts"**
3. Tải các file:
   - **android-apk** → File APK để cài trên Android
   - **android-aab** → File AAB để đăng Google Play Store
   - **ios-ipa** → File IPA cho iPhone/iPad

---

## 🎯 Các cách trigger build

### Cách 1: Tự động build khi push code
```bash
git add .
git commit -m "Update code"
git push origin main
```
→ GitHub Actions sẽ **TỰ ĐỘNG** build APK & IPA

---

### Cách 2: Build với version tag (Tạo Release)
```bash
# Tạo tag version
git tag v1.0.0

# Push tag lên GitHub
git push origin v1.0.0
```
→ GitHub Actions sẽ:
- ✅ Build APK, AAB, IPA
- ✅ Tự động tạo **GitHub Release**
- ✅ Đính kèm file vào Release

**Tải file từ Release**:
1. Vào tab **"Releases"** trên GitHub
2. Click vào version (ví dụ: `v1.0.0`)
3. Tải file từ phần **"Assets"**

---

### Cách 3: Chạy thủ công (Manual)
1. Vào GitHub → Tab **"Actions"**
2. Click workflow **"Flutter Build APK & IPA"**
3. Click nút **"Run workflow"** (bên phải)
4. Chọn branch **"main"**
5. Click **"Run workflow"** (xanh lá)

→ Workflow sẽ chạy ngay lập tức

---

## 📱 Cách cài APK lên điện thoại Android

### Cách 1: Tải trực tiếp từ GitHub (trên điện thoại)
1. Mở trình duyệt trên điện thoại
2. Vào GitHub → Actions → Tải APK
3. Mở file APK → Cài đặt
4. Nếu bị chặn: **Cài đặt → Bảo mật → Cho phép cài từ nguồn không xác định**

### Cách 2: Tải về máy tính rồi chuyển sang điện thoại
1. Tải APK từ GitHub về máy tính
2. Kết nối điện thoại với máy tính (USB)
3. Copy file APK vào điện thoại
4. Mở File Manager → Tìm file APK → Cài đặt

---

## 🍎 Cách cài IPA lên iPhone/iPad

⚠️ **Lưu ý**: File IPA từ GitHub Actions không có chữ ký (unsigned), không thể cài trực tiếp lên iPhone thật.

### Cách 1: Dùng Xcode (Cần Mac)
1. Kết nối iPhone với Mac
2. Mở Xcode
3. Window → Devices and Simulators
4. Kéo file IPA vào iPhone

### Cách 2: Build local với signing (Khuyến nghị)
```bash
# Trên Mac
flutter build ios --release
# Sau đó dùng Xcode để sign và export IPA
```

---

## 📊 Xem log build

Nếu build bị lỗi:
1. Vào **Actions** → Click vào workflow bị lỗi
2. Click vào job (Android/iOS)
3. Xem log chi tiết từng bước
4. Sửa lỗi → Push lại → GitHub Actions tự động build lại

---

## 🔧 Tùy chỉnh build

### Thay đổi Flutter version
Sửa file `.github/workflows/flutter-build.yml`:
```yaml
flutter-version: '3.24.0'  # Đổi thành version bạn muốn
```

### Chỉ build Android (bỏ iOS)
Xóa hoặc comment phần `build-ios` trong file workflow.

### Chỉ build khi có tag
Xóa phần `push: branches: main` trong file workflow.

---

## ✅ Tóm tắt quy trình

```
1. Viết code Flutter
2. git add . && git commit -m "message" && git push
3. GitHub Actions tự động build APK & IPA
4. Đợi 5-10 phút
5. Tải file từ Artifacts
6. Cài APK lên điện thoại Android
```

---

**Tạo bởi**: Nguyễn Phùng Thịnh  
**Ngày**: 10/04/2026  
**Project**: ESP32-CAM Smart Home Face Recognition System
