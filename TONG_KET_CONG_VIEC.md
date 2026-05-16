# Tong Ket Cong Viec - He Thong Smart Home IoT

Ngay: 13/05/2026  
Du an: Do An Tot Nghiep - Smart Home Face Recognition  
Sinh vien: Nguyen Phung Thinh  

---

## I. ESP32-CAM

Ngon ngu: C++ (Arduino Framework)  
File chinh: ESP32CAM/esp32cam_ble_provisioning/esp32cam_ble_provisioning.ino  

---

### 1. BLE WiFi Provisioning

Muc dich: Lan dau su dung, nguoi dung khong can nhap IP hay cau hinh thu cong. Mo app Flutter, quet BLE, chon thiet bi, nhap WiFi la xong.

Ky thuat su dung:
- Thu vien BLEDevice, BLEServer, BLEUtils, BLE2902 cua Arduino ESP32
- Tao GATT Service voi UUID co dinh de Flutter nhan dang
- 4 Characteristic:
  - SSID (WRITE): Flutter ghi ten WiFi vao day
  - PASS (WRITE): Flutter ghi mat khau vao day, sau do bat co wifiReceived
  - STATUS (READ + NOTIFY): ESP32 notify trang thai "connecting" / "connected IP" / "failed" ve Flutter
  - WIFILIST (READ): Flutter doc danh sach WiFi xung quanh de hien thi cho nguoi dung chon

Quy trinh chi tiet:
- Khi khoi dong, kiem tra Preferences (NVS) xem da co WiFi luu chua
- Neu chua co: tat WiFi, bat BLE, bat dau quang ba
- Scan WiFi truoc khi bat BLE, luu vao bien s wifi list dang "SSID1;SSID2;..."
- Flutter ket noi BLE, doc WIFILIST, hien danh sach cho nguoi chon
- Nguoi dung chon WiFi + nhap mat khau, Flutter ghi vao SSID characteristic roi PASS characteristic
- ESP32 nhan PASS xong, bat co wifiReceived = true
- Trong loop(): phat hien co -> goi connectWiFi() -> notify STATUS ve Flutter
- Neu ket noi thanh cong: luu vao Preferences, delay 1.5s, restart
- Sau restart: doc WiFi tu Preferences, ket noi truc tiep, khong can BLE nua

Xu ly loi:
- Neu WiFi that bai: notify "failed" ve Flutter, cho nguoi dung nhap lai
- BLE tu dong quang ba lai (startAdvertising) khi Flutter ngat ket noi

---

### 2. MJPEG Stream (Port 81)

Muc dich: Truyen video truc tiep tu camera den Flutter de hien thi realtime.

Ky thuat su dung:
- ESP HTTP Server (esp httpd) tao HTTP server tren port 81
- Dinh dang multipart/x-mixed-replace boundary chuan MJPEG
- Moi frame duoc gui kem Content-Type image/jpeg va Content-Length

Cau hinh quan trong:
- max open sockets = 1: chi cho phep 1 ket noi dong thoi tren port 81
  - Ly do: neu 2 ket noi cung nhan stream, moi frame duoc gui 2 lan, Flutter nhan frame bi nhan doi, stream bi lag gap doi
- STREAM FPS = 5: toc do 5 frame/giay
  - Ly do: giam bang thong, nhuong tai nguyen WiFi cho Python AI goi /capture
  - Neu de 8fps: /capture bi timeout lien tuc vi ESP32 qua ban

Xu ly frame:
- Lay frame tu camera buffer bang esp camera fb get()
- Gui boundary header, roi Content-Type, roi du lieu JPEG
- Tra frame bang esp camera fb return() ngay sau khi gui
- delay FRAME DELAY MS = 200ms giua cac frame (1000/5fps)

---

### 3. Camera Capture cho AI (Port 80)

Muc dich: Python AI server goi HTTP GET /capture de lay 1 frame JPEG xu ly nhan dien.

Ky thuat su dung:
- HTTP server rieng tren port 80, endpoint /capture
- Tach biet hoan toan voi port 81 de khong anh huong stream Flutter

Co che lay frame:
- Retry 20 lan x 50ms (tong 1000ms) cho den khi co frame
- Neu sau 1000ms van khong co frame: tra HTTP 503
- Tra frame JPEG truc tiep, khong wrap them gi

Ly do can retry:
- Camera dang lien tuc cap nhat buffer cho stream
- Doi khi frame dang duoc su dung boi stream handler
- Retry dam bao lay duoc frame hieu le

---

### 4. Camera Config Toi Uu

Muc dich: Chay on dinh, tranh loi FB-OVF (Frame Buffer Overflow) xuat hien tren Serial.

Van de gap phai:
- Loi cam hal: FB-OVF lien tuc tren Serial Monitor
- Python /capture bi timeout thuong xuyen
- Stream Flutter bi lag tang dan theo thoi gian

Cac thay doi da lam:

- fb count = 4 (tang tu 2):
  - Bo dem 4 frame, camera co cho luu frame moi trong khi frame cu dang duoc doc
  - Tranh OVF khi stream va capture cung hoat dong

- CAMERA GRAB LATEST:
  - Tu dong bo qua frame cu, luon lay frame moi nhat
  - Khong de frame cu chiem buffer gay OVF

- jpeg quality dong bo:
  - cfg.jpeg quality = 12 va s->set quality(s, 12) phai bang nhau
  - Truoc do: cfg = 12 nhung sensor bi override thanh 8, gay bat dong bo

- Static IP 192.168.1.200:
  - Python hardcode IP nay, khong can tim kiem qua mDNS
  - mDNS esp32cam.local van hoat dong cho Flutter

- Da tung thu va bo:
  - drainTask: task rieng lien tuc goi fb get/return -> tieu thu het buffer, /capture khong lay duoc frame -> xoa
  - max open sockets = 2: gui moi frame 2 lan, Flutter lag gap doi -> xoa

---

## II. ESP32-S3

Ngon ngu: C (ESP-IDF Framework)  
File chinh: ESP32S3/esp32s3_relay_mqtt/main/main.c  
Cau truc du an: CMake (ESP-IDF), khong dung Arduino IDE  

---

### 1. Cau Truc Du An ESP-IDF

Muc dich: Dung ESP-IDF chinh thuc thay Arduino IDE de co the build, flash, monitor truc tiep trong VS Code.

Cau truc thu muc:
- esp32s3 relay mqtt/
  - CMakeLists.txt: khai bao project cho CMake
  - sdkconfig.defaults: cau hinh mac dinh (bat NimBLE, WiFi buffer, MQTT buffer)
  - main/
    - CMakeLists.txt: dang ky component main
    - main.c: toan bo firmware

Cong cu:
- ESP-IDF extension trong VS Code cua Espressif
- Build/Flash/Monitor bang thanh cong cu phia duoi VS Code
- Khong can Arduino IDE, khong can PlatformIO

Thu vien dung san trong ESP-IDF (khong can cai them):
- mqtt client.h: MQTT client
- cJSON.h: parse va tao JSON
- esp adc cal.h: tinh chinh ADC chinh xac
- esp wifi.h: WiFi STA mode
- NimBLE: BLE GATT server

---

### 2. BLE WiFi Provisioning

Muc dich: Lan dau su dung, Flutter quet thay "ESP32S3 Relay-XXXX", gui WiFi, ESP32-S3 tu dong ket noi va luu lai.

Ky thuat su dung:
- NimBLE (Nordic Semiconductor BLE stack, built-in ESP-IDF)
- NimBLE nhe hon Bluedroid, phu hop cho thiet bi co it RAM
- GATT server voi cung UUID voi ESP32-CAM de Flutter reuse toan bo code provisioning

4 Characteristic (cung UUID voi ESP32-CAM):
- SSID (WRITE / WRITE NO RSP): Flutter ghi ten WiFi
- PASS (WRITE / WRITE NO RSP): Flutter ghi mat khau, bat co s ble got creds
- STATUS (READ + NOTIFY): notify "connecting" / "connected IP" / "failed"
- WIFILIST (READ): danh sach WiFi xung quanh dang "SSID1;SSID2;..."

Ten BLE: ESP32S3 Relay-XXXX
- XXXX = 2 byte cuoi dia chi MAC WiFi
- Flutter filter startsWith("ESP32") -> tu dong nhan ca ESP32CAM va ESP32S3 Relay

Quy trinh chi tiet:
- Boot -> doc NVS tim WiFi da luu
- Neu khong co: vao BLE mode
- Scan WiFi (WIFI STA + esp wifi scan start) -> luu vao s wifi list
- Tat WiFi, khoi tao NimBLE, bat quang ba
- ble provision task chay song song, cho s ble got creds = true
- Nhan du SSID + PASS -> notify "connecting" -> ket noi WiFi
- Ket noi thanh cong: notify "connected|IP" -> luu NVS -> delay 1.5s -> esp restart()
- Sau restart: WiFi co san trong NVS -> ket noi truc tiep -> MQTT -> relay -> ACS712

---

### 3. Relay Control qua MQTT

Muc dich: Flutter bam nut ON/OFF tren app, den thuc te sang/tat.

Ky thuat su dung:
- gpio config(): cau hinh GPIO 2 la OUTPUT
- gpio set level(): dat muc HIGH (1) hoac LOW (0)
- esp mqtt client subscribe(): lang nghe topic command

MQTT Topic:
- Subscribe: home/devices/light/living room/command
- Format nhan: {"state": "ON"} hoac {"state": "OFF"}
- Publish state: home/devices/light/living room/state voi retain = true
  - Retain dam bao Flutter nhan duoc trang thai hien tai ngay khi mo app, du ESP32-S3 da gui tu truoc

Will message:
- Khi ESP32-S3 mat ket noi dot ngot, broker tu dong gui {"state":"OFFLINE"} len topic state
- Flutter hien thi thiet bi offline

---

### 4. Do Dong Dien ACS712

Muc dich: Hien thi cong suat dien thuc te cua thiet bi dang duoc kiem soat (bong den, quat,...).

Phan cung:
- ACS712-5A: cam bien dong dien, nguong nhay 185 mV/A
- Dau ra analog noi vao GPIO 34 (ADC1 Channel 6 tren ESP32-S3)
- Diem zero = VCC/2 = 1650 mV khi khong co tai

Ky thuat su dung:
- adc1 config width(ADC WIDTH BIT 12): do phan giai 12-bit (0 - 4095)
- adc1 config channel atten(ADC ATTEN DB 11): dai do day du 0 - 3.3V
- esp adc cal characterize(): tinh chinh ADC, bu loi phi tuyen cua ESP32
- esp adc cal raw to voltage(): chuyen raw ADC -> mV chinh xac

Cach tinh dong dien:
- Lay trung binh 50 mau, moi mau cach nhau 200 microsecond
- Chuyen raw -> mV bang ham tinh chinh
- Dong dien (A) = (voltage mV - 1650) / 185
- Lay gia tri tuyet doi (ABS) vi dong co the am tuy chieu
- Loai bo nhieu: neu dong < 0.05A thi cho bang 0

Cach tinh cong suat:
- Cong suat (W) = dong (A) x 220V

Publish moi 2 giay:
- Topic: home/devices/light/living room/power
- Format: {"current": 0.52, "watt": 114, "state": "ON", "ts": 12345}

---

### 5. MQTT Watchdog va Reconnect

Muc dich: ESP32-S3 tu phuc hoi khi mat mang, khong can khoi dong lai thu cong.

Co che:
- mqtt event handler nhan MQTT EVENT DISCONNECTED -> dat s mqtt connected = false
- esp mqtt client tu dong thu ket noi lai (built-in ESP-IDF MQTT client)
- WiFi event handler xu ly WIFI EVENT STA DISCONNECTED -> goi esp wifi connect() lai
- Toi da WIFI MAX RETRY = 10 lan thu

Log online:
- Moi lan ket noi MQTT thanh cong: publish log "ESP32-S3 living room online" len topic home/logs/activity
- Flutter hien thi log nay tren man hinh System Logs

---

## III. Flutter

Ngon ngu: Dart (Flutter Framework)  
Thu muc chinh: FLUTTER/lib/  

---

### 1. BLE WiFi Provisioning Screen

File: lib/presentation/screens/devices/ble wifi provisioning screen.dart  

Muc dich: Giao dien provisioning dung chung cho ca ESP32-CAM va ESP32-S3, nguoi dung chi can lam 1 lan.

Ky thuat su dung:
- flutter blue plus: thu vien BLE cho Flutter
- FlutterBluePlus.startScan(): quet thiet bi BLE xung quanh
- Loc thiet bi: r.device.platformName.startsWith('ESP32')
  - Tu dong nhan ca "ESP32CAM-XXXX" va "ESP32S3 Relay-XXXX"
- Hien danh sach thiet bi tim thay, nguoi dung chon 1

Quy trinh sau khi chon thiet bi:
- Ket noi BLE
- Kham pha services va characteristics
- Doc WIFILIST characteristic -> parse bang ";" -> hien danh sach WiFi
- Nguoi dung chon WiFi + nhap mat khau
- Ghi SSID vao SSID characteristic
- Ghi PASS vao PASS characteristic
- Subscribe notify STATUS characteristic
- Nhan "connecting": hien thi loading
- Nhan "connected|192.168.x.x": hien thi thanh cong + IP
- Nhan "failed": hien thi loi, cho nhap lai
- Tra ket qua ve man hinh truoc: {success, deviceIP, deviceName, wifiSSID}

---

### 2. MJPEG Stream Widget

File: lib/presentation/widgets/live mjpeg.dart  

Muc dich: Hien thi video truc tiep tu ESP32-CAM khong bi lag tang dan theo thoi gian.

Van de goc re (da phat hien va sua):
- BytesBuilder.toBytes() sao chep toan bo buffer moi khi them chunk
- Buffer tang 1MB/phut -> sau 10 phut lag rat nang -> app bi chet
- Sua bang List int + removeRange()

Ky thuat su dung:
- http.Client() mo ket noi HTTP streaming
- Lang nghe tung chunk du lieu bang Stream<List int>
- Dung List int lam buffer (khong sao chep khi them du lieu)
- Nguong xa 128KB: neu buffer > 128KB thi clear() tranh tran bo nho

Cach parse MJPEG:
- Tim SOI marker (FFD8 FF): vi tri bat dau frame JPEG
- Tim tu marker SOI cuoi cung (tranh doc frame cu)
- Tim EOI marker (FF D9): vi tri ket thuc frame JPEG
- Cat doan tu SOI den EOI+2 -> Uint8List -> hien thi
- removeRange(0, vi tri sau EOI): xoa phan da xu ly, giu phan chua xu ly

---

### 3. MQTT Service

File: lib/core/services/mqtt service.dart  

Muc dich: Trung tam xu ly tat ca thong tin realtime: trang thai thiet bi, nhan dien khuon mat, cong suat dien, log he thong.

Ky thuat su dung:
- mqtt client package (Dart)
- Singleton pattern: chi co 1 instance MQTTService trong toan bo app
- Broadcast StreamController: nhieu widget co the lang nghe cung luc

5 stream rieng biet:
- faceRecognitionStream: ket qua nhan dien khuon mat (ten, do chinh xac)
- deviceStateStream: trang thai relay ON/OFF
- devicePowerStream: cong suat Watt + dong dien Ampere
- systemLogsStream: log hoat dong tu ESP32 va Python
- faceBboxStream: toa do bounding box khuon mat de ve khung

Topics da subscribe:
- home/face recognition/result: ket qua nhan dien
- home/face recognition/alert: canh bao khuon mat la
- home/face recognition/bbox: toa do khung khuon mat
- home/devices/+/+/state: trang thai moi thiet bi (wildcard)
- home/logs/activity: log he thong
- home/server/ip: IP Python AI server
- home/devices/+/+/power: cong suat moi thiet bi (wildcard)

Route tin nhan:
- topic.endsWith('/power') -> devicePowerStream
- topic.startsWith('home/face recognition/') -> faceRecognitionStream
- topic == 'home/face recognition/bbox' -> faceBboxStream
- topic.startsWith('home/devices/') -> deviceStateStream
- topic.startsWith('home/logs/') -> systemLogsStream
- topic == 'home/server/ip' -> tu dong cap nhat AI server

Tu dong reconnect:
- onDisconnected: doi 5 giay roi goi connect() lai
- Will message: publish {status: offline} khi mat ket noi

---

### 4. Dashboard va Hien Thi Cong Suat

File: lib/presentation/screens/dashboard/home dashboard.dart  

Muc dich: Man hinh chinh hien thi tong quan he thong, nut dieu khien relay, cong suat realtime.

Tinh nang them moi:
- Bien livingRoomWatt: luu cong suat hien tai cua den phong khach
- StreamSubscription powerSub: lang nghe devicePowerStream
- Khi nhan du lieu moi: cap nhat livingRoomWatt -> setState() -> UI tu cap nhat
- Hien thi chip "Cong suat: XW" voi bieu tuong bolt tren thanh thong ke

Dieu khien relay:
- MQTTService.controlLight(roomName, turnOn): gui lenh ON/OFF
- UI cap nhat ngay lap tuc (optimistic update)
- ESP32-S3 publish state retain -> MQTTService nhan -> cap nhat chinh xac

---

### 5. AI Server Tu Dong Cau Hinh

Muc dich: Nguoi dung khong can nhap IP Python AI server thu cong moi khi IP thay doi.

Co che:
- Python publish {"ip": "192.168.x.x", "port": 5000} len topic home/server/ip voi retain = true
- Retain: Flutter nhan duoc ngay khi mo app, du Python da gui tu truoc
- MQTTService nhan tin nhan -> goi DeviceConfigService.instance.saveAiServer(ip, port)
- Toan bo app tu dong dung IP moi cho moi request den AI server

---

### 6. Thong Bao Khuon Mat La

Muc dich: Canh bao nguoi dung khi camera phat hien nguoi khong co trong danh sach.

Co che:
- Python phat hien khuon mat la -> publish len home/face recognition/alert
- MQTTService nhan -> push len faceRecognitionStream
- Dashboard lang nghe stream -> goi NotificationService.show()
- Chi goi NotificationService o dashboard (da xoa khoi front door cam screen tranh thong bao trung lap)

---

## IV. Python AI Server

Ngon ngu: Python 3  
File chinh: ESP32CAM/face recognition advanced.py  

---

### 1. Single Loop Capturer

Muc dich: Don gian hoa pipeline, tranh xung dot giua nhieu worker, de debug.

Da thu va bo:
- 3 worker song song: AI chi mat 23ms/frame, 1fps -> 3 worker khong bao gio duoc dung het -> phuc tap vo ich -> xoa

Thiet ke hien tai:
- 1 vong lap duy nhat: capture -> detect -> match -> publish -> cooldown
- Toc do: 1 frame/giay (CAPTURE INTERVAL = 1.0)
- Cooldown 6 giay sau khi nhan dien thanh cong: tranh publish cung 1 khuon mat nhieu lan

---

### 2. Capture Frame Tu ESP32-CAM

Muc dich: Lay frame JPEG tu ESP32-CAM qua HTTP.

Ky thuat:
- requests.get(url, timeout=5): 1 lan duy nhat, khong retry
- proxies= NO PROXY: tranh proxy he thong can thiep vao request noi mang
- Parse JPEG bang numpy + cv2.imdecode

Ly do chi thu 1 lan:
- Neu retry: 2-3 request cung luc -> ESP32 qua tai -> tat ca deu timeout
- 1 request that bai -> bo qua frame do -> thu lai sau 1 giay

---

### 3. Drain Capture Trong Cooldown

Muc dich: Trong 6 giay cooldown, van goi /capture moi 1 giay de ESP32 khong bi buffer lock.

Van de neu khong drain:
- ESP32 lien tuc cap nhat camera buffer
- Neu khong ai doc /capture trong 6 giay: buffer day -> cam hal: FB-OVF
- Lan capture tiep theo se timeout vi buffer dang bi lock

Giai phap:
- drain capture(duration=6.0): vong lap goi /capture moi 1 giay trong 6 giay cooldown
- Khong xu ly frame, chi goi de giai phong buffer
- timeout = 2 giay (ngan hon binh thuong vi chi can giai phong, khong can ket qua)

---

### 4. Nhan Dien Khuon Mat

Phat hien khuon mat:
- MediaPipe FaceDetection: nhanh, chinh xac, xu ly tren CPU
- Haar Cascade fallback: du phong khi MediaPipe khong tim thay
- CLAHE (Contrast Limited Adaptive Histogram Equalization): tang cuong anh toi truoc khi phat hien

So sanh khuon mat:
- Cat vung khuon mat, resize ve 64x64 grayscale
- Flatten thanh vector 1 chieu
- Cosine similarity giua vector query va toan bo database
- Nguong MATCH THRESHOLD = 0.78:
  - < 0.78: khong khop -> "Unknown"
  - >= 0.78: khop -> tra ve ten nguoi khop nhat
  - Truoc do de 0.55: qua thap -> moi khuon mat deu match vao "thinh" -> nang len 0.78

---

### 5. Flask API va MQTT

Flask API (chay tren thread rieng, stdout line buffering = True):
- /enroll POST: chup anh, trich xuat dac trung, luu vao database
- /delete POST: xoa thanh vien theo ten
- /members GET: tra ve danh sach thanh vien va anh dai dien
- /config POST: cap nhat nguong nhan dien va cooldown realtime
- /status GET: kiem tra trang thai server, so luong thanh vien, thong tin ket noi

MQTT Publish:
- home/face recognition/result: {"name": "thinh", "score": 0.92, "ts": ...}
- home/face recognition/alert: {"message": "Unknown face detected", "ts": ...}
- home/face recognition/bbox: {"x": 100, "y": 80, "w": 60, "h": 60, "ts": ...}
- home/server/ip: {"ip": "192.168.1.x", "port": 5000} voi retain = true

---

## V. Cac Loi Da Gap Va Cach Xu Ly

### 1. cam hal: FB-OVF (Frame Buffer Overflow)
- Nguyen nhan: fb count = 2 qua it, buffer day truoc khi kip doc
- Thu: them drainTask goi fb get/return lien tuc -> tieu thu het buffer -> /capture mat frame -> xoa drainTask
- Giai phap cuoi: fb count = 4 + CAMERA GRAB LATEST

### 2. Python /capture bi timeout
- Nguyen nhan tong hop: stream 8fps chiem het bang thong, retry nhieu lan lam ESP32 qua tai, buffer lock trong cooldown
- Giai phap: giam FPS xuong 5, chi thu 1 lan, drain trong cooldown

### 3. Flutter stream lag tang dan
- Nguyen nhan: BytesBuilder.toBytes() sao chep toan bo buffer moi chunk -> bo nho tang nhanh
- Giai phap: dung List int + removeRange() chi xoa phan da dung

### 4. Moi khuon mat deu match "thinh"
- Nguyen nhan: MATCH THRESHOLD = 0.55 qua thap
- Giai phap: nang len 0.78

### 5. max open sockets = 2 tren port 81
- Thu: cho phep 2 ket noi dong thoi
- Ket qua: moi frame gui 2 lan, Flutter nhan frame trung, stream lag gap doi
- Giai phap: giu max open sockets = 1

### 6. jpeg quality bat dong bo
- Nguyen nhan: cfg.jpeg quality = 12 nhung s->set quality(s, 8) override lai
- Giai phap: dong bo ca 2 ve 12

### 7. Thong bao trung lap
- Nguyen nhan: ca dashboard lan front door cam screen deu goi NotificationService
- Giai phap: chi goi o dashboard, xoa khoi front door cam

---

## VI. Tong Quan He Thong

```
Flutter App
  |-- BLE Provisioning --> ESP32-CAM / ESP32-S3 (lan dau)
  |-- MJPEG Stream (port 81) --> ESP32-CAM --> hien thi video
  |-- MQTT --> broker.emqx.io:1883
       |-- Nhan: face result, bbox, alert, device state, power, logs, server ip
       |-- Gui: relay command (ON/OFF)

Python AI Server
  |-- HTTP /capture (port 80) --> ESP32-CAM --> lay frame
  |-- MediaPipe + Cosine Similarity --> nhan dien khuon mat
  |-- MQTT --> publish ket qua, IP server

ESP32-CAM (192.168.1.200)
  |-- port 81 /stream --> Flutter
  |-- port 80 /capture --> Python
  |-- BLE (lan dau) --> nhan WiFi tu Flutter

ESP32-S3
  |-- MQTT --> nhan lenh relay, publish state + power
  |-- GPIO 2 --> Relay --> den / thiet bi
  |-- GPIO 34 (ADC) --> ACS712 --> do dong dien
  |-- BLE (lan dau) --> nhan WiFi tu Flutter
```
