# 🚀 HƯỚNG DẪN UPLOAD ESP32-CAM NHANH

## ❌ VẤN ĐỀ: Không thấy COM Port

### 🔧 GIẢI PHÁP NHANH:

#### 1. Kiểm tra Device Manager:
- **Windows + X** → **Device Manager**
- **Tìm "Ports (COM & LPT)"**
- **Có thấy "USB-SERIAL CH340 (COM3)" không?**

#### 2. Nếu KHÔNG có COM:
- **Tải driver CH340**: https://bit.ly/ch340-driver
- **Cài đặt** → **Restart máy**
- **Thử USB cable khác** (phải là data cable)

#### 3. Kết nối đúng:
```
USB-TTL → ESP32-CAM
VCC → 5V
GND → GND  
TX → U0R (GPIO3)
RX → U0T (GPIO1)
IO0 → GND (chỉ khi upload)
```

#### 4. Arduino IDE Settings:
```
Board: AI Thinker ESP32-CAM
Port: COM3 (port thật của bạn)
Upload Speed: 115200
```

#### 5. Upload:
1. **IO0 nối GND**
2. **Reset ESP32-CAM**
3. **Click Upload**
4. **Ngắt IO0 sau khi xong**

## ✅ THÀNH CÔNG KHI:
- Device Manager thấy COM port
- Arduino IDE thấy Port
- Upload 100% thành công
- Serial Monitor hiển thị output

## 🆘 NẾU VẪN KHÔNG ĐƯỢC:
- Thử máy tính khác
- Thử USB-TTL khác
- Kiểm tra ESP32-CAM có nguồn không