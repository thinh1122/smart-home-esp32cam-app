/*
 * ESP32-CAM: BLE WiFi Provisioning + MJPEG Stream only
 * ESP32 job: connect WiFi via BLE, then stream MJPEG at low FPS
 * Face recognition / AI / MQTT → handled by Python server, NOT here
 */

#include "esp_camera.h"
#include "esp_http_server.h"
#include <WiFi.h>
#include <Preferences.h>
#include <ESPmDNS.h>
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

#define LED_PIN 4
#define BOOT_PIN 0

// ============================================================
// BLE UUIDs
// ============================================================
#define SERVICE_UUID   "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define PASS_UUID      "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STATUS_UUID    "d8de624e-140f-4a22-8594-e2216b84a5f2"
#define WIFILIST_UUID  "2b8c9e50-7182-4f32-8414-b49911e0eb7e"

// ============================================================
// Stream config
// ============================================================
#define STREAM_FPS        5           // 5fps — giảm bandwidth, nhường chỗ cho /capture
#define FRAME_DELAY_MS    (1000 / STREAM_FPS)

#define PART_BOUNDARY "123456789000000000000987654321"
static const char* CONTENT_TYPE = "multipart/x-mixed-replace;boundary=" PART_BOUNDARY;
static const char* BOUNDARY     = "\r\n--" PART_BOUNDARY "\r\n";
static const char* FRAME_HDR    = "Content-Type: image/jpeg\r\nContent-Length: %u\r\n\r\n";

// ============================================================
// GLOBALS
// ============================================================
Preferences prefs;
BLECharacteristic* pStatus   = nullptr;
BLECharacteristic* pWifiList = nullptr;
bool bleConnected     = false;
bool wifiReceived     = false;
String rxSSID         = "";
String rxPass         = "";
httpd_handle_t httpd  = nullptr;

// ============================================================
// BLE CALLBACKS
// ============================================================
class BLEConn : public BLEServerCallbacks {
  void onConnect(BLEServer*)    { bleConnected = true;  Serial.println("📱 BLE connected"); }
  void onDisconnect(BLEServer*) { bleConnected = false; BLEDevice::startAdvertising(); }
};
class SSIDcb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    rxSSID = c->getValue().c_str();
    Serial.println("📥 SSID: " + rxSSID);
  }
};
class PASScb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    rxPass = c->getValue().c_str();
    wifiReceived = true;
    Serial.println("📥 Password received");
  }
};

// ============================================================
// HTTP HANDLERS
// ============================================================
static esp_err_t stream_handler(httpd_req_t* req) {
  camera_fb_t* fb = nullptr;
  char hdr[64];

  httpd_resp_set_type(req, CONTENT_TYPE);
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-cache, no-store, must-revalidate");
  httpd_resp_set_hdr(req, "Pragma", "no-cache");

  TickType_t lastFrame = xTaskGetTickCount();

  while (true) {
    fb = esp_camera_fb_get();
    if (!fb) { vTaskDelay(pdMS_TO_TICKS(50)); continue; }

    esp_err_t res = httpd_resp_send_chunk(req, BOUNDARY, strlen(BOUNDARY));
    if (res == ESP_OK) {
      size_t hlen = snprintf(hdr, sizeof(hdr), FRAME_HDR, fb->len);
      res = httpd_resp_send_chunk(req, hdr, hlen);
    }
    if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    esp_camera_fb_return(fb);

    if (res != ESP_OK) break;  // client disconnect

    vTaskDelayUntil(&lastFrame, pdMS_TO_TICKS(FRAME_DELAY_MS));
  }

  return ESP_OK;
}

// /capture → single JPEG snapshot (used by Python AI server)
static esp_err_t capture_handler(httpd_req_t* req) {
  // Thử tối đa 20 lần × 50ms = 1000ms để lấy frame
  camera_fb_t* fb = nullptr;
  for (int i = 0; i < 20 && !fb; i++) {
    fb = esp_camera_fb_get();
    if (!fb) vTaskDelay(pdMS_TO_TICKS(50));
  }
  if (!fb) { httpd_resp_send_500(req); return ESP_FAIL; }
  httpd_resp_set_type(req, "image/jpeg");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  httpd_resp_set_hdr(req, "Cache-Control", "no-cache");
  esp_err_t res = httpd_resp_send(req, (const char*)fb->buf, fb->len);
  esp_camera_fb_return(fb);
  return res;
}

// /status → JSON with IP
static esp_err_t status_handler(httpd_req_t* req) {
  char json[128];
  snprintf(json, sizeof(json),
    "{\"status\":\"ok\",\"ip\":\"%s\",\"fps\":%d}",
    WiFi.localIP().toString().c_str(), STREAM_FPS);
  httpd_resp_set_type(req, "application/json");
  httpd_resp_set_hdr(req, "Access-Control-Allow-Origin", "*");
  return httpd_resp_send(req, json, strlen(json));
}

// ============================================================
// CAMERA SERVER — 2 server riêng: port 81 stream, port 80 capture/status
// ============================================================
static httpd_handle_t httpd2 = nullptr;  // server port 80

void startCameraServer() {
  // Server 1: port 81 — chỉ /stream, max 1 socket (dành trọn cho Flutter)
  httpd_config_t cfg1 = HTTPD_DEFAULT_CONFIG();
  cfg1.server_port      = 81;
  cfg1.ctrl_port        = 32768;
  cfg1.max_uri_handlers = 2;
  cfg1.stack_size       = 8192;
  cfg1.max_open_sockets = 1;  // chỉ Flutter dùng port 81
  cfg1.lru_purge_enable = true;
  cfg1.recv_wait_timeout  = 10;
  cfg1.send_wait_timeout  = 10;

  httpd_uri_t streamUri = { .uri = "/stream", .method = HTTP_GET, .handler = stream_handler, .user_ctx = nullptr };

  if (httpd_start(&httpd, &cfg1) == ESP_OK) {
    httpd_register_uri_handler(httpd, &streamUri);
    Serial.printf("✅ Stream: http://%s:81/stream\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("❌ Stream server failed");
  }

  // Server 2: port 80 — /capture và /status cho Python AI
  httpd_config_t cfg2 = HTTPD_DEFAULT_CONFIG();
  cfg2.server_port      = 80;
  cfg2.ctrl_port        = 32769;
  cfg2.max_uri_handlers = 4;
  cfg2.stack_size       = 4096;
  cfg2.max_open_sockets = 2;
  cfg2.lru_purge_enable = true;
  cfg2.recv_wait_timeout  = 5;
  cfg2.send_wait_timeout  = 5;

  httpd_uri_t captureUri = { .uri = "/capture", .method = HTTP_GET, .handler = capture_handler, .user_ctx = nullptr };
  httpd_uri_t statusUri  = { .uri = "/status",  .method = HTTP_GET, .handler = status_handler,  .user_ctx = nullptr };

  if (httpd_start(&httpd2, &cfg2) == ESP_OK) {
    httpd_register_uri_handler(httpd2, &captureUri);
    httpd_register_uri_handler(httpd2, &statusUri);
    Serial.printf("✅ Capture: http://%s:80/capture\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("❌ Capture server failed");
  }
}

// ============================================================
// CAMERA INIT
// ============================================================
bool initCamera() {
  camera_config_t cfg = {};
  cfg.ledc_channel = LEDC_CHANNEL_0;
  cfg.ledc_timer   = LEDC_TIMER_0;
  cfg.pin_d0  = Y2_GPIO_NUM; cfg.pin_d1 = Y3_GPIO_NUM;
  cfg.pin_d2  = Y4_GPIO_NUM; cfg.pin_d3 = Y5_GPIO_NUM;
  cfg.pin_d4  = Y6_GPIO_NUM; cfg.pin_d5 = Y7_GPIO_NUM;
  cfg.pin_d6  = Y8_GPIO_NUM; cfg.pin_d7 = Y9_GPIO_NUM;
  cfg.pin_xclk     = XCLK_GPIO_NUM;
  cfg.pin_pclk     = PCLK_GPIO_NUM;
  cfg.pin_vsync    = VSYNC_GPIO_NUM;
  cfg.pin_href     = HREF_GPIO_NUM;
  cfg.pin_sscb_sda = SIOD_GPIO_NUM;
  cfg.pin_sscb_scl = SIOC_GPIO_NUM;
  cfg.pin_pwdn     = PWDN_GPIO_NUM;
  cfg.pin_reset    = RESET_GPIO_NUM;

  cfg.xclk_freq_hz = 20000000;   // 20MHz
  cfg.pixel_format = PIXFORMAT_JPEG;
  cfg.frame_size   = FRAMESIZE_QVGA;   // 320x240
  cfg.jpeg_quality = 12;              // 12=cân bằng chất lượng/size (~20KB/frame)
  cfg.fb_count     = 4;               // 4 buffer: stream + capture cùng lúc không block nhau
  cfg.fb_location  = CAMERA_FB_IN_PSRAM;
  cfg.grab_mode    = CAMERA_GRAB_LATEST; // luôn lấy frame mới nhất từ sensor

  if (esp_camera_init(&cfg) != ESP_OK) {
    Serial.println("❌ Camera init failed");
    return false;
  }

  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_framesize(s, FRAMESIZE_QVGA);
    s->set_quality(s, 12);  // khớp với cfg.jpeg_quality — không để override
    s->set_brightness(s, 1);
    s->set_saturation(s, -1);   // lower saturation → smaller JPEG
    s->set_whitebal(s, 1);
    s->set_gain_ctrl(s, 1);
    s->set_exposure_ctrl(s, 1);
    s->set_aec2(s, 1);          // advanced auto exposure
  }

  Serial.println("✅ Camera OK");
  return true;
}

// ============================================================
// WIFI
// ============================================================
// Static IP — ESP32 luôn dùng IP này, không bị DHCP đổi khi restart
static const IPAddress STATIC_IP(192, 168,   1, 200);
static const IPAddress GATEWAY  (192, 168,   1,   1);
static const IPAddress SUBNET   (255, 255, 255,   0);
static const IPAddress DNS1     (  8,   8,   8,   8);

void loadAndConnect() {
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  if (ssid.isEmpty()) { Serial.println("ℹ️ No WiFi saved → BLE mode"); return; }

  Serial.println("📂 Saved WiFi: " + ssid);
  WiFi.mode(WIFI_STA);
  WiFi.config(STATIC_IP, GATEWAY, SUBNET, DNS1);
  WiFi.begin(ssid.c_str(), pass.c_str());
  WiFi.setSleep(false);

  Serial.print("🔌 Connecting");
  for (int i = 0; i < 20 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500); Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ Connected! IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\n❌ WiFi failed → BLE mode");
    WiFi.disconnect(true);
  }
}

bool connectWiFi(const String& ssid, const String& pass) {
  WiFi.mode(WIFI_STA);
  WiFi.config(STATIC_IP, GATEWAY, SUBNET, DNS1);
  WiFi.begin(ssid.c_str(), pass.c_str());
  WiFi.setSleep(false);

  for (int i = 0; i < 20 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500); Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\n✅ IP: %s\n", WiFi.localIP().toString().c_str());
    if (pStatus) {
      String s = "connected|" + WiFi.localIP().toString();
      pStatus->setValue(s.c_str());
      pStatus->notify();
    }
    return true;
  }

  if (pStatus) { pStatus->setValue("failed"); pStatus->notify(); }
  return false;
}

// ============================================================
// BLE INIT
// ============================================================
void initBLE() {
  // Get MAC before WiFi scan
  WiFi.mode(WIFI_STA);
  delay(100);
  uint8_t mac[6]; WiFi.macAddress(mac);
  String name = "ESP32CAM-" + String(mac[4], HEX) + String(mac[5], HEX);
  name.toUpperCase();

  // Scan WiFi networks
  WiFi.disconnect();
  int n = WiFi.scanNetworks();
  String list = "";
  for (int i = 0; i < min(n, 10); i++) {
    if (WiFi.SSID(i).length() > 0) list += WiFi.SSID(i) + ";";
    if (list.length() > 200) break;
  }
  WiFi.scanDelete();

  // Free RAM: shut down WiFi before BLE
  WiFi.mode(WIFI_OFF);
  delay(500);

  Serial.printf("Free heap: %d bytes\n", ESP.getFreeHeap());
  Serial.println("🔵 BLE: " + name);

  BLEDevice::init(name.c_str());
  BLEServer* srv = BLEDevice::createServer();
  srv->setCallbacks(new BLEConn());

  BLEService* svc = srv->createService(SERVICE_UUID);

  auto* ssidChar = svc->createCharacteristic(SSID_UUID, BLECharacteristic::PROPERTY_WRITE);
  ssidChar->setCallbacks(new SSIDcb());

  auto* passChar = svc->createCharacteristic(PASS_UUID, BLECharacteristic::PROPERTY_WRITE);
  passChar->setCallbacks(new PASScb());

  pStatus = svc->createCharacteristic(STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY);
  pStatus->addDescriptor(new BLE2902());
  pStatus->setValue("ready");

  pWifiList = svc->createCharacteristic(WIFILIST_UUID, BLECharacteristic::PROPERTY_READ);
  pWifiList->setValue(list.c_str());

  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("✅ BLE ready — waiting for Flutter app");
}

// ============================================================
// FACTORY RESET (hold IO0 ≥ 1s)
// ============================================================
void checkFactoryReset() {
  // Bỏ qua 5 giây đầu sau boot để tránh trigger khi upload firmware
  if (millis() < 5000) return;
  if (digitalRead(BOOT_PIN) != LOW) return;
  unsigned long t = millis();
  // Chờ đủ 1 giây
  while (digitalRead(BOOT_PIN) == LOW) {
    if (millis() - t >= 1000) {
      Serial.println("🗑️ Factory reset!");
      // Nháy 3 lần báo hiệu
      for (int i = 0; i < 6; i++) { digitalWrite(LED_PIN, i % 2); delay(150); }
      prefs.begin("wifi", false); prefs.clear(); prefs.end();
      delay(300);
      ESP.restart();
    }
  }
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);

  Serial.println("\n============================================================");
  Serial.println("🚀 ESP32-CAM BLE Provisioning");
  Serial.println("============================================================");

  pinMode(BOOT_PIN, INPUT_PULLUP);
  pinMode(LED_PIN, OUTPUT);
  digitalWrite(LED_PIN, LOW);

  loadAndConnect();

  if (WiFi.status() == WL_CONNECTED) {
    if (initCamera()) {
      startCameraServer();
      digitalWrite(LED_PIN, LOW);

      // mDNS — Flutter tự tìm ESP32 trên LAN, không cần nhập IP thủ công
      if (MDNS.begin("esp32cam")) {
        MDNS.addService("_esp32cam", "_tcp", 81);
        MDNS.addServiceTxt("_esp32cam", "_tcp", "stream", "/stream");
        MDNS.addServiceTxt("_esp32cam", "_tcp", "capture", "/capture");
        Serial.printf("📡 mDNS: esp32cam.local → %s:81\n", WiFi.localIP().toString().c_str());
      }
    }
  } else {
    initBLE();
  }

  Serial.println("============================================================\n");
}

// ============================================================
// LOOP — minimal: just factory reset check + WiFi watchdog
// ============================================================
void loop() {
  checkFactoryReset();

  // BLE provisioning flow
  if (wifiReceived) {
    wifiReceived = false;
    Serial.println("🔄 WiFi config received...");
    if (pStatus) { pStatus->setValue("connecting"); pStatus->notify(); }
    delay(500);

    if (connectWiFi(rxSSID, rxPass)) {
      prefs.begin("wifi", false);
      prefs.putString("ssid", rxSSID);
      prefs.putString("pass", rxPass);
      prefs.end();
      delay(1500);
      Serial.println("🔄 Restarting into camera mode...");
      delay(300);
      ESP.restart();
    } else {
      delay(2000);
      ESP.restart();
    }
  }

  // WiFi watchdog: auto-reconnect if dropped
  if (WiFi.status() != WL_CONNECTED && httpd != nullptr) {
    Serial.println("⚠️ WiFi lost — reconnecting...");
    prefs.begin("wifi", true);
    String ssid = prefs.getString("ssid", "");
    String pass = prefs.getString("pass", "");
    prefs.end();
    if (!ssid.isEmpty()) connectWiFi(ssid, pass);
  }

  delay(5000);  // check every 5s — loop does almost nothing
}
