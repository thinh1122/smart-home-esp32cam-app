@echo off
chcp 65001 >nul
echo ============================================================
echo 🔍 KIỂM TRA IP ESP32-CAM
echo ============================================================
echo.

echo 📋 IP hiện tại trong code:
echo    - Python Server: 192.168.1.27
echo    - Test Script:   192.168.1.27
echo.

echo ============================================================
echo CÁCH 1: Xem từ Serial Monitor Arduino IDE
echo ============================================================
echo 1. Mở Arduino IDE
echo 2. Tools → Serial Monitor (Ctrl+Shift+M)
echo 3. Baud rate: 115200
echo 4. Reset ESP32 (nhấn nút RST)
echo 5. Tìm dòng: "✅ Connected! IP: 192.168.x.x"
echo.

echo ============================================================
echo CÁCH 2: Scan mạng WiFi (nếu biết ESP32 đã kết nối)
echo ============================================================
echo Đang quét mạng...
echo.

REM Lấy IP máy tính
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do (
    set IP=%%a
    set IP=!IP: =!
    echo 💻 IP máy tính: !IP!
)

echo.
echo Đang ping IP cũ (192.168.1.27)...
ping -n 1 -w 1000 192.168.1.27 >nul
if %errorlevel%==0 (
    echo ✅ ESP32 phản hồi tại: 192.168.1.27
    echo    → IP vẫn đúng, không cần thay đổi
) else (
    echo ❌ ESP32 không phản hồi tại 192.168.1.27
    echo    → IP có thể đã thay đổi
)

echo.
echo ============================================================
echo CÁCH 3: Kiểm tra Router Admin Panel
echo ============================================================
echo 1. Mở browser: http://192.168.1.1 (hoặc 192.168.0.1)
echo 2. Đăng nhập router (admin/admin hoặc xem mặt sau router)
echo 3. Tìm "Connected Devices" hoặc "DHCP Client List"
echo 4. Tìm device tên "ESP32CAM-xxxx"
echo.

echo ============================================================
echo CÁCH 4: Test HTTP endpoint
echo ============================================================
echo Đang test ESP32 HTTP server...
echo.

curl -s --connect-timeout 3 http://192.168.1.27:81/status >nul 2>&1
if %errorlevel%==0 (
    echo ✅ ESP32 HTTP server OK tại: http://192.168.1.27:81
    echo.
    echo 📊 Status:
    curl -s http://192.168.1.27:81/status
    echo.
) else (
    echo ❌ Không kết nối được ESP32 HTTP server
    echo    → Kiểm tra Serial Monitor để lấy IP mới
)

echo.
echo ============================================================
echo 📝 NẾU IP THAY ĐỔI - CẬP NHẬT TẠI:
echo ============================================================
echo 1. ESP32CAM/face_recognition_advanced.py (dòng 36)
echo 2. test_system.py (dòng 17)
echo.
echo Sau đó chạy: python test_system.py
echo.

pause
