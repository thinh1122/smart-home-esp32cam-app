/*
 * ESP32-CAM: BLE WiFi Provisioning + MJPEG Stream only
 * ESP32 job: connect WiFi via BLE, then stream MJPEG at low FPS
 * Face recognition / AI / MQTT → handled by Python server, NOT here
 */

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
// Stream config — low FPS to keep ESP32 free
// ============================================================
#define STREAM_FPS        10          // target FPS
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
    if (!fb) { vTaskDelay(pdMS_TO_TICKS(100)); continue; }

    esp_err_t res = httpd_resp_send_chunk(req, BOUNDARY, strlen(BOUNDARY));
    if (res == ESP_OK) {
      size_t hlen = snprintf(hdr, sizeof(hdr), FRAME_HDR, fb->len);
      res = httpd_resp_send_chunk(req, hdr, hlen);
    }
    if (res == ESP_OK) res = httpd_resp_send_chunk(req, (const char*)fb->buf, fb->len);
    esp_camera_fb_return(fb);

    if (res != ESP_OK) break;  // client disconnected

    // Throttle: wait remainder of frame interval
    vTaskDelayUntil(&lastFrame, pdMS_TO_TICKS(FRAME_DELAY_MS));
  }
  return ESP_OK;
}

// /capture → single JPEG snapshot (used by Python AI server)
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
// CAMERA SERVER
// ============================================================
void startCameraServer() {
  httpd_config_t cfg = HTTPD_DEFAULT_CONFIG();
  cfg.server_port      = 81;
  cfg.ctrl_port        = 32768;
  cfg.max_uri_handlers = 8;
  cfg.stack_size       = 8192;
  cfg.max_open_sockets = 4;
  cfg.lru_purge_enable = true;
  cfg.recv_wait_timeout  = 10;
  cfg.send_wait_timeout  = 10;

  httpd_uri_t uris[] = {
    { .uri = "/stream",  .method = HTTP_GET, .handler = stream_handler,  .user_ctx = nullptr },
    { .uri = "/capture", .method = HTTP_GET, .handler = capture_handler, .user_ctx = nullptr },
    { .uri = "/status",  .method = HTTP_GET, .handler = status_handler,  .user_ctx = nullptr },
  };

  if (httpd_start(&httpd, &cfg) == ESP_OK) {
    for (auto& u : uris) httpd_register_uri_handler(httpd, &u);
    Serial.printf("✅ Stream: http://%s:81/stream\n", WiFi.localIP().toString().c_str());
    Serial.printf("✅ Capture: http://%s:81/capture\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("❌ HTTP server failed");
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

  cfg.xclk_freq_hz = 10000000;   // 10MHz XCLK — stable, lower power than 20MHz
  cfg.pixel_format = PIXFORMAT_JPEG;
  cfg.frame_size   = FRAMESIZE_QVGA;   // 320x240 — good balance
  cfg.jpeg_quality = 15;               // 10=best, 63=worst; 15 ≈ 15-20KB/frame
  cfg.fb_count     = 1;               // 1 buffer — less RAM, lower latency
  cfg.fb_location  = psramFound() ? CAMERA_FB_IN_PSRAM : CAMERA_FB_IN_DRAM;
  cfg.grab_mode    = CAMERA_GRAB_LATEST; // always get latest frame, discard stale

  if (esp_camera_init(&cfg) != ESP_OK) {
    Serial.println("❌ Camera init failed");
    return false;
  }

  sensor_t* s = esp_camera_sensor_get();
  if (s) {
    s->set_framesize(s, FRAMESIZE_QVGA);
    s->set_quality(s, 15);
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
void loadAndConnect() {
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  if (ssid.isEmpty()) { Serial.println("ℹ️ No WiFi saved → BLE mode"); return; }

  Serial.println("📂 Saved WiFi: " + ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());
  WiFi.setSleep(false);  // disable WiFi power save → stable stream

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
// FACTORY RESET (hold IO0 ≥ 3s)
// ============================================================
void checkFactoryReset() {
  if (digitalRead(BOOT_PIN) != LOW) return;
  unsigned long t = millis();
  while (digitalRead(BOOT_PIN) == LOW) {
    digitalWrite(LED_PIN, (millis() - t) / 500 % 2);
    if (millis() - t >= 3000) {
      Serial.println("🗑️ Factory reset!");
      prefs.begin("wifi", false); prefs.clear(); prefs.end();
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
      digitalWrite(LED_PIN, HIGH);  // LED on = streaming ready
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
