# ESP32-S3 Relay + ACS712 — Hướng dẫn

## Thư viện cần cài (Arduino IDE)
Vào Tools → Manage Libraries, tìm và cài:
- **PubSubClient** by Nick O'Leary (v2.8+)
- **ArduinoJson** by Benoit Blanchon (v6+)

## Wiring

| ESP32-S3 | Module | Ghi chú |
|----------|--------|---------|
| GPIO 2 | Relay IN | Điều khiển relay |
| GPIO 34 | ACS712 OUT | Đọc dòng điện (ADC) |
| 3.3V | ACS712 VCC | |
| 5V | Relay VCC | Relay cần 5V |
| GND | Relay GND + ACS712 GND | Chung GND |

## Relay → Bóng đèn

```
220V Line ──→ Relay COM
              Relay NO ──→ Bóng đèn ──→ 220V Neutral
```

## Chỉnh ACS712 Sensitivity

Mở file .ino, tìm dòng:
```cpp
#define ACS712_SENSITIVITY  185.0   // mV/A
```
- ACS712-5A  → 185.0
- ACS712-20A → 100.0
- ACS712-30A → 66.0

## Chỉnh WiFi

```cpp
#define WIFI_SSID  "tên_wifi_của_bạn"
#define WIFI_PASS  "mật_khẩu"
```

## Nạp code

1. Cắm USB ESP32-S3 vào máy
2. Arduino IDE → Board: "ESP32S3 Dev Module"
3. Upload → Done
4. Sau đó chỉ cần cấp nguồn 5V là tự chạy

## Flow tự động

```
Cấp nguồn
  → Kết nối WiFi (tự động, không cần thao tác)
  → Kết nối MQTT broker.emqx.io
  → Subscribe home/devices/light/living_room/command
  → Publish state hiện tại (retain) → Flutter tự sync
  → Đọc ACS712 mỗi 2s → Publish power → Flutter hiển thị Watt
```

## Test nhanh không cần Flutter

Dùng MQTT Explorer hoặc mosquitto_pub:
```
mosquitto_pub -h broker.emqx.io -t "home/devices/light/living_room/command" -m '{"state":"ON"}'
mosquitto_pub -h broker.emqx.io -t "home/devices/light/living_room/command" -m '{"state":"OFF"}'
```
