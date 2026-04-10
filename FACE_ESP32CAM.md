# HỆ THỐNG NHẬN DIỆN KHUÔN MẶT ESP32-CAM

## 📋 TỔNG QUAN HỆ THỐNG

Hệ thống nhận diện khuôn mặt sử dụng ESP32-CAM, AI Python, Relay Server Node.js và Flutter App.

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐      ┌──────────────┐
│  ESP32-CAM  │─────▶│ Relay Server │─────▶│  Python AI  │─────▶│   Database   │
│  (Camera)   │      │   (Node.js)  │      │  (MediaPipe)│      │  (SQLite)    │
└─────────────┘      └──────────────┘      └─────────────┘      └──────────────┘
       │                     │                      │                     │
       └─────────────────────┴──────────────────────┴─────────────────────┘
                                      │
                               ┌──────▼──────┐
                               │ Flutter App │
                               │   (Mobile)  │
                               └─────────────┘
```

---

## 🔧 CẤU TRÚC HỆ THỐNG

### 1. ESP32-CAM (Hardware + Firmware)
**File:** `ESP32CAM/esp32cam_optimized/esp32cam_optimized.ino`

**Chức năng:**
- Stream video MJPEG realtime
- Chụp ảnh single frame
- Cung cấp HTTP endpoints

**Thư viện sử dụng:**
```cpp
#include "esp_camera.h"  // Camera driver
#include <WiFi.h>        // WiFi connection
```

**Cấu hình camera:**
- Resolution: QVGA (320x240)
- JPEG Quality: 12 (cao)
- Frame Buffer: 2 (double buffering)
- Clock: 10MHz
- Target FPS: 10

**Endpoints:**
- `GET /stream` → MJPEG stream
- `GET /capture` → Single frame JPEG
- `GET /status` → Camera status
- `GET /config?quality=X&brightness=Y` → Runtime config


---

### 2. Relay Server (Node.js)
**File:** `ESP32CAM/relay_server.js`

**Chức năng:**
- Lấy frame từ ESP32-CAM và broadcast cho nhiều client
- Proxy requests giữa Flutter và Python AI
- Quản lý tần suất stream thông minh

**Thư viện sử dụng:**
```javascript
const express = require('express');      // Web server
const http = require('http');            // HTTP server
const WebSocket = require('ws');         // WebSocket cho stream
const axios = require('axios');          // HTTP client
```

**Tần suất stream:**
- Khởi động: 1 FPS (1 frame/giây)
- Có face: 2 FPS (0.5s/frame)
- Không có face: 1 FPS
- Quá tải: 0.1 FPS (10s/frame)

**Endpoints:**
- `GET /stream` → MJPEG stream (100ms interval)
- `GET /capture` → Single frame từ ESP32
- `POST /recognize` → Proxy đến Python AI
- `POST /auto_capture_compare` → Nhận diện 4 ảnh
- `POST /enroll` → Đăng ký user
- `GET /members` → Danh sách user
- `POST /delete` → Xóa user
- `GET /status` → Server status


---

### 3. Python AI Server
**File:** `ESP32CAM/face_recognition_advanced.py`

**Chức năng:**
- Motion Detection (Frame Diff)
- Face Detection (MediaPipe)
- Face Recognition (Template Matching)
- Database management (SQLite)

**Thư viện sử dụng:**
```python
import cv2                    # OpenCV 4.8.1.78 - Image processing
import numpy                  # 1.26.4 - Array operations
import mediapipe as mp        # 0.10.9 - Face detection
import sqlite3                # Built-in - Database
from flask import Flask       # 3.0.0 - Web server
from PIL import Image         # 10.1.0 - Image enhancement
from skimage.metrics import ssim  # 0.21.0 - Image similarity
```

**Công nghệ AI:**
1. **Frame Diff Motion Detection**
   - So sánh 2 frame liên tiếp
   - Threshold: 25 (pixel difference)
   - Min pixels: 500 (để coi là có chuyển động)

2. **MediaPipe Face Detection**
   - Model: Long range (model_selection=1)
   - Confidence threshold: 0.5
   - Min face size: 50x50 pixels

3. **Template Matching**
   - Method: TM_CCOEFF_NORMED + SSIM + Histogram
   - Recognition threshold: 0.50 (50%)
   - Template size: 160x160 grayscale

**Endpoints:**
- `POST /recognize` → Motion + Face detection
- `POST /auto_capture_compare` → So sánh 4 ảnh
- `POST /enroll` → Đăng ký khuôn mặt
- `GET /members` → Danh sách thành viên
- `POST /delete` → Xóa thành viên
- `GET /status` → Trạng thái hệ thống


---

### 4. Flutter App (Mobile)
**File:** `lib/front_door_cam.dart`

**Chức năng:**
- Hiển thị stream từ Relay Server
- Phát hiện và nhận diện khuôn mặt
- Đăng ký user mới
- Quản lý danh sách user

**Thư viện sử dụng:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  http: ^1.1.0              # HTTP requests
  cupertino_icons: ^1.0.2   # iOS icons
```

**Widgets chính:**
- `Image.network()` → Hiển thị MJPEG stream
- `Timer.periodic()` → Gửi frame định kỳ để nhận diện
- `http.get()` / `http.post()` → API calls
- `ScaffoldMessenger` → Hiển thị thông báo

**State Management:**
- `_isRecognizing` → Đang nhận diện
- `_isCapturing` → Đang chụp ảnh (tránh spam)
- `_faceDetectedTime` → Thời điểm phát hiện face
- `_faceStable` → Face đã ổn định 2 giây
- `_recognizedFaces` → Danh sách face đã nhận diện


---

## 🔄 LUỒNG XỬ LÝ NHẬN DIỆN

### Sơ đồ chi tiết:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 1. Hiển thị stream MJPEG từ Relay Server                     │  │
│  │    └─▶ Image.network('http://relay:8080/stream')             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 2. Timer mỗi 1 giây: Chụp frame và gửi nhận diện            │  │
│  │    └─▶ GET /capture → POST /recognize                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                       RELAY SERVER (Node.js)                        │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 3. Nhận request từ Flutter                                   │  │
│  │    ├─▶ /capture: Lấy frame từ ESP32-CAM                      │  │
│  │    └─▶ /recognize: Proxy đến Python AI                       │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                       PYTHON AI SERVER                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 4. Nhận ảnh base64 từ Relay                                  │  │
│  │    └─▶ Decode ảnh → BGR image                                │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 5. MOTION DETECTION (Frame Diff)                            │  │
│  │    ├─▶ Chuyển sang grayscale 160x120                         │  │
│  │    ├─▶ So sánh với frame trước                               │  │
│  │    ├─▶ Đếm pixel thay đổi > 500?                             │  │
│  │    └─▶ Nếu KHÔNG có motion → Return (bỏ qua)                 │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 6. FACE DETECTION (MediaPipe)                                │  │
│  │    ├─▶ MediaPipe detect với confidence > 0.5                 │  │
│  │    ├─▶ Filter face size >= 50x50                             │  │
│  │    └─▶ Return face bounding boxes                            │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 7. Nhận response: motion=true, face_count=1                  │  │
│  │    └─▶ Hiển thị khung focus quanh khuôn mặt                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 8. Kiểm tra ổn định 2 giây                                   │  │
│  │    ├─▶ Lần 1: Bắt đầu đếm thời gian                          │  │
│  │    ├─▶ Lần 2-N: Kiểm tra duration < 2s?                      │  │
│  │    └─▶ Nếu >= 2s → Bắt đầu chụp                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```


---

## 📸 LUỒNG CHỤP VÀ NHẬN DIỆN (Sau khi ổn định 2s)

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 9. Chụp 4 ảnh liên tiếp (delay 500ms)                        │  │
│  │    ├─▶ Ảnh 1: Dùng luôn ảnh test                             │  │
│  │    ├─▶ Ảnh 2: GET /capture (delay 500ms)                     │  │
│  │    ├─▶ Ảnh 3: GET /capture (delay 500ms)                     │  │
│  │    └─▶ Ảnh 4: GET /capture                                   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 10. Gửi 4 ảnh base64 đến Python AI                           │  │
│  │     └─▶ POST /auto_capture_compare                           │  │
│  │         Body: { images_base64: [img1, img2, img3, img4] }    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                       PYTHON AI SERVER                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 11. Decode 4 ảnh và lưu tạm vào /temp                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 12. Xử lý từng ảnh                                            │  │
│  │     ├─▶ Enhance (brightness, contrast, sharpness)            │  │
│  │     ├─▶ Detect face với MediaPipe                            │  │
│  │     ├─▶ Extract template 160x160 grayscale                   │  │
│  │     └─▶ Lưu vào captured_templates[]                         │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 13. So sánh với database                                     │  │
│  │     ├─▶ Load known_face_templates từ DB                      │  │
│  │     ├─▶ For each captured template:                          │  │
│  │     │   └─▶ Compare với tất cả templates trong DB            │  │
│  │     │       ├─▶ TM_CCOEFF_NORMED (40%)                       │  │
│  │     │       ├─▶ SSIM (40%)                                    │  │
│  │     │       └─▶ Histogram Correlation (20%)                  │  │
│  │     ├─▶ Tìm best match với score > 0.50                      │  │
│  │     └─▶ Return result                                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 14. Xóa ảnh tạm trong /temp                                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 15. Nhận kết quả                                              │  │
│  │     ├─▶ matched=true → Hiển thị "Xin chào [Tên]!"            │  │
│  │     │   └─▶ SnackBar màu xanh (4 giây)                        │  │
│  │     └─▶ matched=false → Hiển thị "CẢNH BÁO: Người lạ!"       │  │
│  │         └─▶ SnackBar màu đỏ (5 giây)                          │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 16. Reset state và tiếp tục stream                           │  │
│  │     ├─▶ _isCapturing = false                                 │  │
│  │     ├─▶ _faceStable = false                                  │  │
│  │     └─▶ _faceDetectedTime = null                             │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```


---

## 👤 LUỒNG ĐĂNG KÝ USER MỚI

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 1. User nhấn nút "Thành viên" → Mở form đăng ký              │  │
│  │    └─▶ Nhập: Tên, ID, Role                                   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 2. Chụp 3 góc độ (pose 1, 2, 3)                              │  │
│  │    ├─▶ Pose 1: Nhìn thẳng                                    │  │
│  │    ├─▶ Pose 2: Nghiêng trái                                  │  │
│  │    └─▶ Pose 3: Nghiêng phải                                  │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 3. Gửi từng ảnh đến Python AI                                │  │
│  │    └─▶ POST /enroll                                          │  │
│  │        Body: {                                                │  │
│  │          name: "thinh",                                       │  │
│  │          id: "1",                                             │  │
│  │          role: "Thành viên",                                  │  │
│  │          pose: 1/2/3,                                         │  │
│  │          image_base64: "..."                                  │  │
│  │        }                                                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                       PYTHON AI SERVER                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 4. Decode ảnh và kiểm tra có face không                      │  │
│  │    ├─▶ MediaPipe detect face                                 │  │
│  │    └─▶ Nếu không có face → Return error                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 5. Lưu ảnh vào /img                                           │  │
│  │    └─▶ img/thinh_pose1.jpg                                   │  │
│  │    └─▶ img/thinh_pose2.jpg                                   │  │
│  │    └─▶ img/thinh_pose3.jpg                                   │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 6. Lưu vào database                                           │  │
│  │    └─▶ INSERT INTO members (id, name, role, avatar,          │  │
│  │                              pose1, pose2, pose3)             │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 7. Load lại templates                                         │  │
│  │    ├─▶ Đọc ảnh từ /img                                        │  │
│  │    ├─▶ Detect face và extract template                       │  │
│  │    └─▶ Lưu vào known_face_templates[]                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 8. Hiển thị thông báo "Đã học góc X/3"                       │  │
│  │    └─▶ Sau khi học xong 3 góc → Hoàn tất                     │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```


---

## 🗑️ LUỒNG XÓA USER

```
┌─────────────────────────────────────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 1. User nhấn nút xóa trên card member                         │  │
│  │    └─▶ Hiển thị dialog xác nhận                              │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 2. Gửi request xóa đến Python AI                             │  │
│  │    └─▶ POST /delete                                          │  │
│  │        Body: { id: "1", name: "thinh" }                      │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                       PYTHON AI SERVER                              │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 3. Tìm user trong database                                    │  │
│  │    └─▶ SELECT * FROM members WHERE id=? OR name=?            │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 4. Xóa file ảnh                                               │  │
│  │    ├─▶ os.remove(img/thinh_pose1.jpg)                        │  │
│  │    ├─▶ os.remove(img/thinh_pose2.jpg)                        │  │
│  │    └─▶ os.remove(img/thinh_pose3.jpg)                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 5. Xóa khỏi database                                          │  │
│  │    └─▶ DELETE FROM members WHERE id=?                        │  │
│  └──────────────────────────────────────────────────────────────┘  │
│                              │                                      │
│  ┌──────────────────────────▼──────────────────────────────────┐  │
│  │ 6. Load lại templates                                         │  │
│  │    └─▶ load_known_faces()                                    │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────┬───────────────────────────────────────┘
                              │
┌─────────────────────────────▼───────────────────────────────────────┐
│                         FLUTTER APP                                 │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │ 7. Reload danh sách members                                   │  │
│  │    └─▶ GET /members                                           │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
```


---

## 📊 DATABASE SCHEMA

**File:** `ESP32CAM/members.db` (SQLite)

```sql
CREATE TABLE members (
    id          TEXT PRIMARY KEY,      -- User ID
    name        TEXT NOT NULL,         -- Tên user
    role        TEXT DEFAULT 'Thành viên',  -- Vai trò
    avatar      TEXT,                  -- Đường dẫn avatar
    pose1       TEXT,                  -- Đường dẫn ảnh góc 1
    pose2       TEXT,                  -- Đường dẫn ảnh góc 2
    pose3       TEXT,                  -- Đường dẫn ảnh góc 3
    enrolled_at TEXT                   -- Thời gian đăng ký
);
```

**Ví dụ dữ liệu:**
```
id: "1"
name: "thinh"
role: "Thành viên"
avatar: null
pose1: "img/thinh_pose1.jpg"
pose2: "img/thinh_pose2.jpg"
pose3: "img/thinh_pose3.jpg"
enrolled_at: "2026-04-10T15:00:00"
```

---

## 🔧 CẤU HÌNH HỆ THỐNG

### IP Addresses:
- **ESP32-CAM:** `192.168.110.38:81`
- **Relay Server:** `192.168.110.101:8080`
- **Python AI:** `127.0.0.1:5000` (localhost)

### WiFi:
- **SSID:** `PI Coffee 24h`
- **Password:** `77778888`

### Thư mục:
- **Ảnh đăng ký:** `ESP32CAM/img/`
- **Ảnh tạm:** `ESP32CAM/temp/` (tự động xóa)
- **Database:** `ESP32CAM/members.db`


---

## ⚙️ THAM SỐ TỐI ƯU HÓA

### Motion Detection:
- **MOTION_THRESHOLD:** 25 (pixel difference)
- **MIN_MOTION_PIXELS:** 500 (số pixel thay đổi tối thiểu)
- **Frame size:** 160x120 (resize nhỏ để tính nhanh)

### Face Detection:
- **MediaPipe confidence:** 0.5 (50%)
- **Min face size:** 50x50 pixels
- **Model:** Long range (model_selection=1)

### Face Recognition:
- **Template size:** 160x160 grayscale
- **Recognition threshold:** 0.50 (50%)
- **Matching methods:**
  - TM_CCOEFF_NORMED: 40%
  - SSIM: 40%
  - Histogram Correlation: 20%

### Stream:
- **ESP32-CAM FPS:** 10
- **Relay idle:** 1 FPS
- **Relay with face:** 2 FPS
- **MJPEG interval:** 100ms (10 FPS)

### Timing:
- **Face stability:** 2 giây
- **Capture delay:** 500ms giữa các ảnh
- **Recognition timeout:** 10 giây

---

## 🚀 CÁCH CHẠY HỆ THỐNG

### 1. Flash ESP32-CAM:
```bash
# Mở Arduino IDE
# File → Open → ESP32CAM/esp32cam_optimized/esp32cam_optimized.ino
# Tools → Board → AI Thinker ESP32-CAM
# Tools → Port → COMx
# Upload
```

### 2. Chạy Python AI Server:
```bash
cd ESP32CAM
pip install -r requirements_advanced.txt
python face_recognition_advanced.py
```

### 3. Chạy Relay Server:
```bash
cd ESP32CAM
npm install
npm start
# hoặc: node relay_server.js
```

### 4. Chạy Flutter App:
```bash
flutter pub get
flutter run
```

---

## 🐛 DEBUG & TROUBLESHOOTING

### Kiểm tra Python AI:
```bash
curl http://127.0.0.1:5000/status
```

### Kiểm tra Relay Server:
```bash
curl http://192.168.110.101:8080/status
```

### Kiểm tra ESP32-CAM:
```bash
curl http://192.168.110.38:81/status
```

### Log Python:
- `🎯 Motion: True/False (X pixels) → Y faces`
- `🔍 So sánh X templates với Y templates trong DB...`
- `📊 So sánh với [name]: XX.X%`
- `✅ Nhận diện thành công: [name] | Độ tin cậy: XX%`

### Log Relay:
- `📸 X frames | Lỗi liên tiếp: 0`
- `⚡ Tần suất: X.XX FPS (reason)`
- `⚠️ ESP32-CAM lỗi X/5: timeout`

---

## 📝 LƯU Ý

1. **ESP32-CAM cần nguồn 5V-2A** - nguồn yếu sẽ gây timeout
2. **WiFi cần mạnh** - cường độ > -70 dBm
3. **Ánh sáng đủ** - không quá tối hoặc quá sáng
4. **Khoảng cách 30-50cm** - quá gần hoặc quá xa sẽ giảm độ chính xác
5. **Đăng ký 3 góc độ** - tăng độ chính xác nhận diện
6. **Threshold có thể điều chỉnh** - giảm xuống 0.45 nếu khó nhận diện

---

**Tác giả:** Nguyen Phung Thinh  
**Ngày tạo:** 10/04/2026  
**Version:** 1.0
