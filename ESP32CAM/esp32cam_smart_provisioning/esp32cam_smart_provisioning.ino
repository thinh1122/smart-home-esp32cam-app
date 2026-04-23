#include "esp_camera.h"
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// CAMERA PINS - AI THINKER ESP32-CAM
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
// SMART PROVISIONING CONFIG
// ============================================================
#define RESET_BUTTON_PIN  12  // GPIO12 - nút reset WiFi (tùy chọn)
#define LED_PIN           33  // GPIO33 - LED status (tùy chọn)

// BLE UUIDs
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define WIFI_PASS_UUID      "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STATUS_UUID         "d8de624e-140f-4a22-8594-e2216b84a5f2"
#define RESET_UUID          "f47ac10b-58cc-4372-a567-0e02b2c3d479"

// Timing constants
#define WIFI_CONNECT_TIMEOUT    20000  // 20 giây timeout kết nối WiFi
#define BLE_TIMEOUT            300000  // 5 phút timeout BLE (sau đó restart)
#define RESET_BUTTON_HOLD      5000   // Giữ nút reset 5 giây để xóa WiFi

// ============================================================
// GLOBAL VARIABLES
// ============================================================
Preferences preferences;
BLEServer* pServer = NULL;
BLECharacteristic* pStatusCharacteristic = NULL;
bool deviceConnected = false;
bool wifiConfigReceived = false;
String receivedSSID = "";
String receivedPassword = "";

WiFiServer server(81);

// State management
enum SystemState {
  STATE_INIT,
  STATE_WIFI_CONNECTING,
  STATE_WIFI_CONNECTED,
  STATE_BLE_PROVISIONING,
  STATE_ERROR
};

SystemState currentState = STATE_INIT;
unsigned long stateStartTime = 0;
unsigned long lastHeartbeat = 0;

// ============================================================
// UTILITY FUNCTIONS
// ============================================================
void setLED(bool on) {
  #ifdef LED_PIN
  digitalWrite(LED_PIN, on ? HIGH : LOW);
  #endif
}

void blinkLED(int times, int delayMs = 200) {
  for (int i = 0; i < times; i++) {
    setLED(true);
    delay(delayMs);
    setLED(false);
    delay(delayMs);
  }
}

void changeState(SystemState newState) {
  Serial.printf("🔄 State: %d → %d\n", currentState, newState);
  currentState = newState;
  stateStartTime = millis();
}

bool isResetButtonPressed() {
  #ifdef RESET_BUTTON_PIN
  return digitalRead(RESET_BUTTON_PIN) == LOW;
  #else
  return false;
  #endif
}

void checkResetButton() {
  static unsigned long resetPressStart = 0;
  static bool resetPressed = false;
  
  if (isResetButtonPressed()) {
    if (!resetPressed) {
      resetPressed = true;
      resetPressStart = millis();
      Serial.println("🔘 Reset button pressed...");
    } else if (millis() - resetPressStart > RESET_BUTTON_HOLD) {
      Serial.println("🗑️ Xóa WiFi config và restart...");
      clearWiFiConfig();
      blinkLED(5, 100);
      ESP.restart();
    }
  } else {
    resetPressed = false;
  }
}

// ============================================================
// WIFI MANAGEMENT
// ============================================================
void clearWiFiConfig() {
  preferences.begin("wifi", false);
  preferences.clear();
  preferences.end();
  Serial.println("🗑️ Đã xóa WiFi config");
}

bool loadWiFiConfig() {
  preferences.begin("wifi", false);
  String ssid = preferences.getString("ssid", "");
  String password = preferences.getString("password", "");
  preferences.end();
  
  if (ssid.length() > 0) {
    Serial.println("📂 WiFi đã lưu: " + ssid);
    receivedSSID = ssid;
    receivedPassword = password;
    return true;
  }
  return false;
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
  changeState(STATE_WIFI_CONNECTING);
  
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), password.c_str());
  
  unsigned long startTime = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - startTime < WIFI_CONNECT_TIMEOUT) {
    delay(500);
    Serial.print(".");
    blinkLED(1, 100);
    
    // Check reset button during connection
    checkResetButton();
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ WiFi kết nối thành công!");
    Serial.printf("   📍 IP: %s\n", WiFi.localIP().toString().c_str());
    Serial.printf("   📶 RSSI: %d dBm\n", WiFi.RSSI());
    
    changeState(STATE_WIFI_CONNECTED);
    setLED(true);  // LED sáng liên tục khi có WiFi
    
    // Notify BLE client if connected
    if (deviceConnected && pStatusCharacteristic) {
      String status = "connected|" + WiFi.localIP().toString();
      pStatusCharacteristic->setValue(status.c_str());
      pStatusCharacteristic->notify();
    }
    
    return true;
  } else {
    Serial.println("\n❌ WiFi kết nối thất bại!");
    changeState(STATE_ERROR);
    
    if (deviceConnected && pStatusCharacteristic) {
      pStatusCharacteristic->setValue("wifi_failed");
      pStatusCharacteristic->notify();
    }
    
    return false;
  }
}

// ============================================================
// CAMERA FUNCTIONS
// ============================================================
bool initCamera() {
  Serial.println("📷 Khởi tạo camera...");
  
  camera_config_t config;
  config.ledc_channel = LEDC_CHANNEL_0;
  config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = Y2_GPIO_NUM;
  config.pin_d1 = Y3_GPIO_NUM;
  config.pin_d2 = Y4_GPIO_NUM;
  config.pin_d3 = Y5_GPIO_NUM;
  config.pin_d4 = Y6_GPIO_NUM;
  config.pin_d5 = Y7_GPIO_NUM;
  config.pin_d6 = Y8_GPIO_NUM;
  config.pin_d7 = Y9_GPIO_NUM;
  config.pin_xclk = XCLK_GPIO_NUM;
  config.pin_pclk = PCLK_GPIO_NUM;
  config.pin_vsync = VSYNC_GPIO_NUM;
  config.pin_href = HREF_GPIO_NUM;
  config.pin_sscb_sda = SIOD_GPIO_NUM;
  config.pin_sscb_scl = SIOC_GPIO_NUM;
  config.pin_pwdn = PWDN_GPIO_NUM;
  config.pin_reset = RESET_GPIO_NUM;
  config.xclk_freq_hz = 10000000;
  config.pixel_format = PIXFORMAT_JPEG;
  
  // Smart memory allocation
  if(psramFound()){
    config.frame_size = FRAMESIZE_QVGA;  // 320x240
    config.jpeg_quality = 12;
    config.fb_count = 1;  // Giảm để tiết kiệm RAM cho BLE
    config.fb_location = CAMERA_FB_IN_PSRAM;
    Serial.println("   ✅ PSRAM detected - High quality mode");
  } else {
    config.frame_size = FRAMESIZE_QQVGA;  // 160x120
    config.jpeg_quality = 15;
    config.fb_count = 1;
    Serial.println("   ⚠️ No PSRAM - Low quality mode");
  }
  
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("❌ Camera init failed: 0x%x\n", err);
    return false;
  }
  
  // Camera sensor tuning
  sensor_t * s = esp_camera_sensor_get();
  if (s != NULL) {
    s->set_brightness(s, 0);
    s->set_contrast(s, 1);
    s->set_saturation(s, 0);
    s->set_whitebal(s, 1);
    s->set_awb_gain(s, 1);
    s->set_wb_mode(s, 0);
    s->set_exposure_ctrl(s, 1);
    s->set_aec2(s, 1);
    s->set_gain_ctrl(s, 1);
    s->set_lenc(s, 1);
    s->set_hmirror(s, 0);
    s->set_vflip(s, 0);
    s->set_dcw(s, 1);
  }
  
  Serial.println("✅ Camera khởi tạo thành công");
  return true;
}

// ============================================================
// BLE CALLBACKS
// ============================================================
class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 Flutter app kết nối BLE");
    blinkLED(2, 100);
  }
  
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("📱 Flutter app ngắt kết nối BLE");
    BLEDevice::startAdvertising();
  }
};

class WiFiSSIDCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() > 0) {
      receivedSSID = String(value.c_str());
      Serial.println("📥 Nhận SSID: " + receivedSSID);
    }
  }
};

class WiFiPasswordCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value.length() > 0) {
      receivedPassword = String(value.c_str());
      Serial.println("📥 Nhận Password: " + receivedPassword);
      wifiConfigReceived = true;
    }
  }
};

class ResetCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic *pCharacteristic) {
    std::string value = pCharacteristic->getValue();
    if (value == "reset_wifi") {
      Serial.println("🔄 Reset WiFi qua BLE");
      clearWiFiConfig();
      ESP.restart();
    }
  }
};

// ============================================================
// BLE FUNCTIONS
// ============================================================
void initBLE() {
  // Generate unique BLE name
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  String bleName = "ESP32CAM-" + String(mac[4], HEX) + String(mac[5], HEX);
  bleName.toUpperCase();
  
  Serial.println("🔵 Khởi động BLE: " + bleName);
  changeState(STATE_BLE_PROVISIONING);
  
  BLEDevice::init(bleName.c_str());
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  // Create service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // SSID characteristic
  BLECharacteristic *pSSIDChar = pService->createCharacteristic(
    WIFI_SSID_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSSIDChar->setCallbacks(new WiFiSSIDCallbacks());
  
  // Password characteristic
  BLECharacteristic *pPasswordChar = pService->createCharacteristic(
    WIFI_PASS_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pPasswordChar->setCallbacks(new WiFiPasswordCallbacks());
  
  // Status characteristic (notify)
  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusCharacteristic->addDescriptor(new BLE2902());
  pStatusCharacteristic->setValue("ready");
  
  // Reset characteristic
  BLECharacteristic *pResetChar = pService->createCharacteristic(
    RESET_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pResetChar->setCallbacks(new ResetCallbacks());
  
  pService->start();
  
  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("✅ BLE sẵn sàng - Mở Flutter app để kết nối");
  Serial.println("   📱 Tên thiết bị: " + bleName);
}

void deinitBLE() {
  if (pServer) {
    Serial.println("🔵 Tắt BLE để tiết kiệm RAM...");
    BLEDevice::deinit(true);
    pServer = NULL;
    pStatusCharacteristic = NULL;
    deviceConnected = false;
  }
}

// ============================================================
// HTTP SERVER
// ============================================================
void handleHTTPRequest() {
  WiFiClient client = server.available();
  if (!client) return;
  
  String request = client.readStringUntil('\r');
  client.flush();
  
  // /capture endpoint
  if (request.indexOf("GET /capture") >= 0) {
    camera_fb_t * fb = esp_camera_fb_get();
    if (fb) {
      client.println("HTTP/1.1 200 OK");
      client.println("Content-Type: image/jpeg");
      client.println("Access-Control-Allow-Origin: *");
      client.printf("Content-Length: %u\r\n", fb->len);
      client.println("Connection: close");
      client.println();
      client.write(fb->buf, fb->len);
      esp_camera_fb_return(fb);
      Serial.println("📸 Captured frame");
    } else {
      client.println("HTTP/1.1 500 Internal Server Error");
    }
  }
  
  // /status endpoint
  else if (request.indexOf("GET /status") >= 0) {
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: application/json");
    client.println("Access-Control-Allow-Origin: *");
    client.println("Connection: close");
    client.println();
    client.printf("{\"status\":\"connected\",\"ip:\"%s\",\"rssi\":%d,\"uptime\":%lu}\n", 
                  WiFi.localIP().toString().c_str(), WiFi.RSSI(), millis());
  }
  
  // /stream endpoint
  else if (request.indexOf("GET /stream") >= 0) {
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: multipart/x-mixed-replace; boundary=frame");
    client.println("Access-Control-Allow-Origin: *");
    client.println("Connection: close");
    client.println();
    
    while (client.connected()) {
      camera_fb_t * fb = esp_camera_fb_get();
      if (!fb) break;
      
      client.println("--frame");
      client.println("Content-Type: image/jpeg");
      client.printf("Content-Length: %u\r\n\r\n", fb->len);
      client.write(fb->buf, fb->len);
      client.println();
      
      esp_camera_fb_return(fb);
      delay(100);  // 10 FPS
    }
  }
  
  // /reset_wifi endpoint
  else if (request.indexOf("GET /reset_wifi") >= 0) {
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: text/plain");
    client.println("Connection: close");
    client.println();
    client.println("WiFi config cleared. Restarting...");
    client.stop();
    
    clearWiFiConfig();
    delay(1000);
    ESP.restart();
  }
  
  // Default page
  else {
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: text/html");
    client.println("Connection: close");
    client.println();
    client.println("<!DOCTYPE HTML><html><body>");
    client.println("<h1>ESP32-CAM Smart Provisioning</h1>");
    client.printf("<p>Status: %s</p>", currentState == STATE_WIFI_CONNECTED ? "Connected" : "Disconnected");
    client.printf("<p>IP: %s</p>", WiFi.localIP().toString().c_str());
    client.printf("<p>RSSI: %d dBm</p>", WiFi.RSSI());
    client.printf("<p>Uptime: %lu ms</p>", millis());
    client.println("<h2>Endpoints:</h2>");
    client.println("<ul>");
    client.println("<li><a href='/stream'>/stream</a> - MJPEG Stream</li>");
    client.println("<li><a href='/capture'>/capture</a> - Single frame</li>");
    client.println("<li><a href='/status'>/status</a> - JSON status</li>");
    client.println("<li><a href='/reset_wifi'>/reset_wifi</a> - Clear WiFi & restart</li>");
    client.println("</ul>");
    client.println("</body></html>");
  }
  
  client.stop();
}

// ============================================================
// MAIN SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n" + String("=") * 70);
  Serial.println("🚀 ESP32-CAM SMART PROVISIONING v2.0");
  Serial.println("🧠 Auto WiFi → BLE → Plug & Play");
  Serial.println(String("=") * 70);
  
  // Init pins
  #ifdef LED_PIN
  pinMode(LED_PIN, OUTPUT);
  setLED(false);
  #endif
  
  #ifdef RESET_BUTTON_PIN
  pinMode(RESET_BUTTON_PIN, INPUT_PULLUP);
  #endif
  
  // Init camera
  if (!initCamera()) {
    Serial.println("❌ Camera failed - System halted");
    changeState(STATE_ERROR);
    while(1) {
      blinkLED(3, 500);
      delay(2000);
    }
  }
  
  // Smart provisioning logic
  Serial.println("\n🧠 SMART PROVISIONING LOGIC:");
  
  // Step 1: Try saved WiFi
  if (loadWiFiConfig()) {
    Serial.println("1️⃣ Thử kết nối WiFi đã lưu...");
    if (connectToWiFi(receivedSSID, receivedPassword)) {
      // Success - start web server
      server.begin();
      Serial.println("✅ Web server khởi động port 81");
      Serial.println("🎯 Hệ thống sẵn sàng hoạt động!");
    } else {
      // Failed - clear bad config and start BLE
      Serial.println("⚠️ WiFi đã lưu không hoạt động → Xóa và chuyển BLE");
      clearWiFiConfig();
      initBLE();
    }
  } else {
    // No saved WiFi - start BLE
    Serial.println("1️⃣ Chưa có WiFi → Khởi động BLE provisioning");
    initBLE();
  }
  
  Serial.println(String("=") * 70 + "\n");
}

// ============================================================
// MAIN LOOP
// ============================================================
void loop() {
  unsigned long now = millis();
  
  // Check reset button
  checkResetButton();
  
  // State machine
  switch (currentState) {
    case STATE_WIFI_CONNECTED:
      // Handle HTTP requests
      handleHTTPRequest();
      
      // Check WiFi connection
      if (WiFi.status() != WL_CONNECTED) {
        Serial.println("⚠️ WiFi mất kết nối → Thử kết nối lại");
        changeState(STATE_WIFI_CONNECTING);
        if (!connectToWiFi(receivedSSID, receivedPassword)) {
          Serial.println("❌ Không thể kết nối lại → Chuyển BLE");
          initBLE();
        }
      }
      
      // Heartbeat
      if (now - lastHeartbeat > 30000) {  // 30 giây
        Serial.printf("💓 Heartbeat - IP: %s, RSSI: %d dBm, Uptime: %lu ms\n", 
                      WiFi.localIP().toString().c_str(), WiFi.RSSI(), now);
        lastHeartbeat = now;
      }
      break;
      
    case STATE_BLE_PROVISIONING:
      // Handle WiFi config received via BLE
      if (wifiConfigReceived) {
        wifiConfigReceived = false;
        
        Serial.println("\n🔄 Xử lý WiFi config từ BLE...");
        
        // Notify connecting
        if (pStatusCharacteristic) {
          pStatusCharacteristic->setValue("connecting");
          pStatusCharacteristic->notify();
        }
        
        delay(1000);
        
        // Disable BLE to free RAM
        deinitBLE();
        
        // Try to connect
        if (connectToWiFi(receivedSSID, receivedPassword)) {
          saveWiFiConfig(receivedSSID, receivedPassword);
          server.begin();
          Serial.println("✅ Web server khởi động port 81");
          Serial.println("🎯 Provisioning hoàn tất!");
        } else {
          Serial.println("❌ Kết nối thất bại → Restart để thử lại");
          delay(3000);
          ESP.restart();
        }
      }
      
      // BLE timeout
      if (now - stateStartTime > BLE_TIMEOUT) {
        Serial.println("⏰ BLE timeout → Restart");
        ESP.restart();
      }
      
      // BLE status blink
      if (now % 2000 < 100) {
        blinkLED(1, 50);
      }
      break;
      
    case STATE_ERROR:
      // Error state - blink rapidly
      blinkLED(5, 100);
      delay(2000);
      break;
      
    default:
      delay(100);
      break;
  }
  
  delay(10);
}