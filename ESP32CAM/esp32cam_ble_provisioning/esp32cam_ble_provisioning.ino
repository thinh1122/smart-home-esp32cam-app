#include "esp_camera.h"
#include "esp_http_server.h"
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// CAMERA PINS (AI Thinker ESP32-CAM)
// ============================================================
#define PWDN_GPIO_NUM     32
#define RESET_GPIO_NUM    -1
#define XCLK_GPIO_NUM      0
#define SIOD_GPIO_NUM     26
#define SIOC_GPIO_NUM     27
#define Y9_GPIO_NUM       35
#define Y8_GPIO_NUM       34
#define Y7_GPIO_NUM       39
#define Y6_GPIO_NUM       36
#define Y5_GPIO_NUM       21
#define Y4_GPIO_NUM       19
#define Y3_GPIO_NUM       18
#define Y2_GPIO_NUM        5
#define VSYNC_GPIO_NUM    25
#define HREF_GPIO_NUM     23
#define PCLK_GPIO_NUM     22

// ============================================================
// BLE UUIDs
// ============================================================
#define SERVICE_UUID      "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_SSID_UUID    "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define WIFI_PASS_UUID    "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STATUS_UUID       "d8de624e-140f-4a22-8594-e2216b84a5f2"
#define WIFI_LIST_UUID    "2b8c9e50-7182-4f32-8414-b49911e0eb7e"

// ============================================================
// GLOBAL VARIABLES
// ============================================================
Preferences preferences;
BLECharacteristic* pStatusCharacteristic = NULL;
BLECharacteristic* pWiFiListCharacteristic = NULL;
bool deviceConnected   = false;
bool wifiConfigReceived = false;
String receivedSSID    = "";
String receivedPassword = "";

httpd_handle_t stream_httpd = NULL;

// ============================================================
// BLE CALLBACKS
// ============================================================
class ServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer*)    { deviceConnected = true;  Serial.println("📱 Flutter app đã kết nối BLE"); }
  void onDisconnect(BLEServer*) { deviceConnected = false; Serial.println("📱 Flutter app ngắt kết nối BLE"); BLEDevice::startAdvertising(); }
};

class WiFiSSIDCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    String v = c->getValue().c_str();
    if (v.length() > 0) { receivedSSID = v; Serial.println("📥 Nhận SSID: " + receivedSSID); }
  }
};

class WiFiPasswordCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    String v = c->getValue().c_str();
    if (v.length() > 0) { receivedPassword = v; Serial.println("📥 Nhận Password: " + receivedPassword); wifiConfigReceived = true; }
  }
};

// ============================================================
// HTTP STREAM HANDLER (esp_http_server — MJPEG chuẩn)
// ============================================================
// Target ~8 FPS to balance quality vs ESP32 load
#define STREAM_FRAME_DELAY_MS 120

#define PART_BOUNDARY "123456789000000000000987654321"
static const char* STREAM_CONTENT_TYPE = "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char* STREAM_BOUNDARY     = "\r\n--" PART_BOUNDARY "\r\n";
static const char* STREAM_PART        = "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

static esp_err_t stream_handler(httpd_req_t* req) {
  camera_fb_t* fb = NULL;
  esp_err_t res = ESP_OK;
  char part_buf[64];

  res = httpd_resp_set_type(req, STREAM_CONTENT_TYPE);
  if (res != ESP_OK) return res;

  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-cache, no-store, must-revalidate");
  httpd_resp_set_hdr(req, "Pragma", "no-cache");

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) { res = ESP_FAIL; break; }

    if (res == ESP_OK) res = httpd_resp_send_chunk(req, STREAM_BOUNDARY, strlen(STREAM_BOUNDARY));
    if (res == ESP_OK) {
      size_t hlen = snprintf(part_buf, sizeof(part_buf), STREAM_PART, fb->len);
      res = httpd_resp_send_chunk(req, part_buf, hlen);
    }
    if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);

    esp_camera_fb_return(fb);
    if (res != ESP_OK) break;

    // Throttle to ~8 FPS — prevents ESP32 from running at 100% and allows
    // the HTTP server to process other requests (/capture, /status)
    vTaskDelay(pdMS_TO_TICKS(STREAM_FRAME_DELAY_MS));
  }
  return res;
}

// /capture → single JPEG
static esp_err_t capture_handler(httpd_req_t* req) {
  camera_fb_t* fb = esp_camera_fb_get();
  if (!fb) { httpd_resp_send_500(req); return ESP_FAIL; }

  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-cache");
  esp_err_t res = httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

// /status → JSON
static esp_err_t status_handler(httpd_req_t* req) {
  char json[128];
  snprintf(json, sizeof(json), "{\"status\":\"connected\",\"ip\":\"%s\"}", WiFi.localIP().toString().c_str());
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json, strlen(json));
}

void startCameraServer() {
  httpd_config_t config = HTTPD_DEFAULT_CONFIG();
  config.server_port      = 81;
  config.ctrl_port        = 32768;
  config.max_uri_handlers = 8;
  config.stack_size       = 8192;
  config.max_open_sockets = 3;   // 1 stream + 1 capture + 1 status
  config.lru_purge_enable = true; // auto-close idle sockets

  httpd_uri_t stream_uri  = { .uri = "/stream",  .method = HTTP_GET, .handler = stream_handler,  .user_ctx = NULL };
  httpd_uri_t capture_uri = { .uri = "/capture", .method = HTTP_GET, .handler = capture_handler, .user_ctx = NULL };
  httpd_uri_t status_uri  = { .uri = "/status",  .method = HTTP_GET, .handler = status_handler,  .user_ctx = NULL };

  if (httpd_start(&stream_httpd, &config) == ESP_OK) {
    httpd_register_uri_handler(stream_httpd, &stream_uri);
    httpd_register_uri_handler(stream_httpd, &capture_uri);
    httpd_register_uri_handler(stream_httpd, &status_uri);
    Serial.printf("✅ Camera server: http://%s:81/stream\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("❌ Camera server start failed");
  }
}

// ============================================================
// WIFI FUNCTIONS
// ============================================================
void loadWiFiConfig() {
  preferences.begin("wifi", false);
  String ssid     = preferences.getString("ssid", "");
  String password = preferences.getString("password", "");
  preferences.end();

  if (ssid.length() > 0) {
    Serial.println("📂 WiFi đã lưu: " + ssid);
    connectToWiFi(ssid, password);
  } else {
    Serial.println("ℹ️ Chưa có WiFi → Khởi động BLE");
  }
}

void saveWiFiConfig(String ssid, String password) {
  preferences.begin("wifi", false);
  preferences.putString("ssid", ssid);
  preferences.putString("password", password);
  preferences.end();
  Serial.println("💾 Đã lưu WiFi: " + ssid);
}

bool connectToWiFi(String ssid, String password) {
  Serial.println("🔌 Đang kết nối WiFi: " + ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());

  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 20) {
    delay(500); Serial.print("."); attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ Kết nối thành công!\n   📍 IP: %s\n", WiFi.localIP().toString().c_str());
    if (deviceConnected && pStatusCharacteristic) {
      String status = "connected|" + WiFi.localIP().toString();
      pStatusCharacteristic->setValue(status.c_str());
      pStatusCharacteristic->notify();
    }
    return true;
  } else {
    Serial.println("\n❌ Kết nối thất bại!");
    if (deviceConnected && pStatusCharacteristic) {
      pStatusCharacteristic->setValue("failed");
      pStatusCharacteristic->notify();
    }
    return false;
  }
}

// ============================================================
// CAMERA INIT
// ============================================================
bool initCamera() {
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer   = LEDC_TIMER_0;
  config.pin_d0  = Y2_GPIO_NUM; config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2  = Y4_GPIO_NUM; config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4  = Y6_GPIO_NUM; config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6  = Y8_GPIO_NUM; config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk  = XCLK_GPIO_NUM; config.pin_pclk  = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM; config.pin_href  = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM; config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn  = PWDN_GPIO_NUM; config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 10000000;
  config.pixel_format = PIXFORMAT_JPEG;

  if (psramFound()) {
    // QVGA 320x240 @ quality 15 → ~15KB/frame, comfortable for ESP32 WiFi
    config.frame_size   = FRAMESIZE_QVGA;
    config.jpeg_quality = 15;
    config.fb_count     = 1;  // 1 buffer → lower latency, less PSRAM
    config.fb_location  = CAMERA_FB_IN_PSRAM;
  } else {
    config.frame_size   = FRAMESIZE_QQVGA;
    config.jpeg_quality = 20;
    config.fb_count     = 1;
    config.fb_location  = CAMERA_FB_IN_DRAM;
  }

  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("❌ Camera init failed: 0x%x\n", err);
    return false;
  }

  // Fine-tune sensor after init to reduce JPEG size and CPU load
  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_framesize(s, FRAMESIZE_QVGA);
    s->set_quality(s, 15);
    s->set_brightness(s, 1);   // slightly brighter for indoor
    s->set_saturation(s, -1);  // reduce saturation → smaller JPEG
    s->set_whitebal(s, 1);     // auto white balance
    s->set_gain_ctrl(s, 1);    // auto gain
    s->set_exposure_ctrl(s, 1); // auto exposure
  }

  Serial.println("✅ Camera OK");
  return true;
}

// ============================================================
// BLE INIT
// ============================================================
void initBLE() {
  // Lấy MAC trước khi scan
  WiFi.mode(WIFI_STA);
  delay(100);
  uint8_t mac[6];
  WiFi.macAddress(mac);
  String bleName = "ESP32CAM-" + String(mac[4], HEX) + String(mac[5], HEX);
  bleName.toUpperCase();

  // Quét WiFi
  Serial.println("🔍 [1/3] Đang quét WiFi xung quanh (trước khi bật BLE)...");
  WiFi.disconnect();
  delay(200);

  int n = WiFi.scanNetworks();
  String wifiListString = "";
  if (n <= 0) {
    Serial.println("   Không tìm thấy mạng WiFi nào.");
  } else {
    for (int i = 0; i < n; ++i) {
      String ssid = WiFi.SSID(i);
      if (ssid.length() > 0) wifiListString += ssid + ";";
      if (wifiListString.length() > 200 || i >= 10) break;
    }
    Serial.println("   Đã tìm thấy: " + wifiListString);
  }
  WiFi.scanDelete();

  // Tắt hoàn toàn WiFi để giải phóng RAM cho BLE
  WiFi.mode(WIFI_OFF);
  delay(500);

  Serial.printf("   Free heap before BLE init: %d bytes\n", ESP.getFreeHeap());
  Serial.println("🔵 [2/3] Khởi động BLE: " + bleName);

  BLEDevice::init(bleName.c_str());
  BLEServer* pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());

  BLEService* pService = pServer->createService(SERVICE_UUID);

  BLECharacteristic* pSSIDChar = pService->createCharacteristic(WIFI_SSID_UUID, BLECharacteristic::PROPERTY_WRITE);
  pSSIDChar->setCallbacks(new WiFiSSIDCallbacks());

  BLECharacteristic* pPasswordChar = pService->createCharacteristic(WIFI_PASS_UUID, BLECharacteristic::PROPERTY_WRITE);
  pPasswordChar->setCallbacks(new WiFiPasswordCallbacks());

  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_UUID, BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatusCharacteristic->addDescriptor(new BLE2902());
  pStatusCharacteristic->setValue("ready");

  pWiFiListCharacteristic = pService->createCharacteristic(WIFI_LIST_UUID, BLECharacteristic::PROPERTY_READ);
  pWiFiListCharacteristic->setValue(wifiListString.c_str());

  pService->start();

  BLEAdvertising* pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();

  Serial.println("✅ [3/3] BLE sẵn sàng! Mở Flutter App để kết nối.");
  Serial.println("   📱 App sẽ thấy danh sách WiFi ngay khi kết nối vào.");
}

// ============================================================
// FACTORY RESET (giữ nút IO0 ≥ 3 giây)
// ============================================================
void checkFactoryReset() {
  if (digitalRead(0) != LOW) return;

  unsigned long pressStart = millis();
  while (digitalRead(0) == LOW) {
    unsigned long held = millis() - pressStart;
    digitalWrite(4, (held / 500) % 2);
    if (held >= 3000) {
      digitalWrite(4, HIGH);
      Serial.println("\n🗑️  Factory Reset! Xóa WiFi...");
      preferences.begin("wifi", false);
      preferences.clear();
      preferences.end();
      delay(1000);
      digitalWrite(4, LOW);
      Serial.println("✅ Đã xóa. Khởi động lại vào chế độ BLE...");
      delay(500);
      ESP.restart();
    }
  }
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n============================================================");
  Serial.println("🚀 ESP32-CAM BLE Provisioning");
  Serial.println("============================================================");

  pinMode(0, INPUT_PULLUP);
  pinMode(4, OUTPUT);
  digitalWrite(4, LOW);

  loadWiFiConfig();

  if (WiFi.status() == WL_CONNECTED) {
    if (initCamera()) {
      startCameraServer();
    }
  } else {
    initBLE();
  }

  Serial.println("============================================================\n");
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  checkFactoryReset();

  if (wifiConfigReceived) {
    wifiConfigReceived = false;
    Serial.println("\n🔄 Đang xử lý WiFi config...");

    if (pStatusCharacteristic) {
      pStatusCharacteristic->setValue("connecting");
      pStatusCharacteristic->notify();
    }
    delay(1000);

    if (connectToWiFi(receivedSSID, receivedPassword)) {
      saveWiFiConfig(receivedSSID, receivedPassword);
      delay(2000);
      Serial.println("🔄 Restart để khởi động Camera với RAM sạch...");
      delay(500);
      ESP.restart();
    } else {
      Serial.println("⚠️ Kết nối thất bại → Restart...");
      delay(3000);
      ESP.restart();
    }
  }

  delay(10);
}
