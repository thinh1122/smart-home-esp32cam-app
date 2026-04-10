#include "esp_camera.h"
#include <WiFi.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ============================================================
// CAMERA PINS
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
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define WIFI_SSID_UUID      "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define WIFI_PASS_UUID      "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STATUS_UUID         "d8de624e-140f-4a22-8594-e2216b84a5f2"

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

// ============================================================
// BLE CALLBACKS
// ============================================================
class ServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("📱 Flutter app đã kết nối BLE");
  }
  
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("📱 Flutter app ngắt kết nối BLE");
    // Restart advertising
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


// ============================================================
// WIFI FUNCTIONS
// ============================================================
void loadWiFiConfig() {
  preferences.begin("wifi", false);
  String ssid = preferences.getString("ssid", "");
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
    delay(500);
    Serial.print(".");
    attempts++;
  }
  
  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ Kết nối thành công!");
    Serial.print("   📍 IP: ");
    Serial.println(WiFi.localIP());
    
    // Gửi IP qua BLE nếu đang kết nối
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
  
  if(psramFound()){
    config.frame_size = FRAMESIZE_QVGA;
    config.jpeg_quality = 12;
    config.fb_count = 1;  // Giảm xuống 1 để tiết kiệm RAM cho BLE
    config.fb_location = CAMERA_FB_IN_PSRAM;
  } else {
    config.frame_size = FRAMESIZE_QQVGA;
    config.jpeg_quality = 15;
    config.fb_count = 1;
  }
  
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("❌ Camera init failed: 0x%x\n", err);
    return false;
  }
  
  Serial.println("✅ Camera OK");
  return true;
}


// ============================================================
// BLE INIT
// ============================================================
void initBLE() {
  // Tạo tên BLE với MAC address
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  String bleName = "ESP32CAM-" + String(mac[4], HEX) + String(mac[5], HEX);
  bleName.toUpperCase();
  
  Serial.println("🔵 Khởi động BLE: " + bleName);
  
  BLEDevice::init(bleName.c_str());
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new ServerCallbacks());
  
  // Tạo service
  BLEService *pService = pServer->createService(SERVICE_UUID);
  
  // Characteristic cho SSID
  BLECharacteristic *pSSIDChar = pService->createCharacteristic(
    WIFI_SSID_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pSSIDChar->setCallbacks(new WiFiSSIDCallbacks());
  
  // Characteristic cho Password
  BLECharacteristic *pPasswordChar = pService->createCharacteristic(
    WIFI_PASS_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );
  pPasswordChar->setCallbacks(new WiFiPasswordCallbacks());
  
  // Characteristic cho Status (notify)
  pStatusCharacteristic = pService->createCharacteristic(
    STATUS_UUID,
    BLECharacteristic::PROPERTY_READ | BLECharacteristic::PROPERTY_NOTIFY
  );
  pStatusCharacteristic->addDescriptor(new BLE2902());
  pStatusCharacteristic->setValue("ready");
  
  pService->start();
  
  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("✅ BLE đã sẵn sàng");
  Serial.println("   📱 Mở Flutter app để kết nối");
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n" + String("=") * 60);
  Serial.println("🚀 ESP32-CAM BLE Provisioning");
  Serial.println(String("=") * 60);
  
  // Init camera
  if (!initCamera()) {
    Serial.println("❌ Camera failed!");
    return;
  }
  
  // Load WiFi config
  loadWiFiConfig();
  
  // Nếu chưa kết nối WiFi → Khởi động BLE
  if (WiFi.status() != WL_CONNECTED) {
    initBLE();
  } else {
    // Đã có WiFi → Start web server
    server.begin();
    Serial.println("✅ Web server port 81");
  }
  
  Serial.println(String("=") * 60 + "\n");
}


// ============================================================
// LOOP
// ============================================================
void loop() {
  // Nếu nhận được WiFi config qua BLE
  if (wifiConfigReceived) {
    wifiConfigReceived = false;
    
    Serial.println("\n🔄 Đang xử lý WiFi config...");
    
    // Gửi status "connecting"
    if (pStatusCharacteristic) {
      pStatusCharacteristic->setValue("connecting");
      pStatusCharacteristic->notify();
    }
    
    delay(1000);
    
    // Tắt BLE để tiết kiệm RAM
    Serial.println("🔵 Tắt BLE...");
    BLEDevice::deinit(true);
    
    delay(500);
    
    // Kết nối WiFi
    if (connectToWiFi(receivedSSID, receivedPassword)) {
      // Lưu config
      saveWiFiConfig(receivedSSID, receivedPassword);
      
      // Start web server
      server.begin();
      Serial.println("✅ Web server port 81");
      Serial.println("📡 Sẵn sàng hoạt động!");
    } else {
      // Kết nối thất bại → Restart để vào BLE lại
      Serial.println("⚠️ Kết nối thất bại → Restart...");
      delay(3000);
      ESP.restart();
    }
  }
  
  // Xử lý HTTP requests nếu đã có WiFi
  if (WiFi.status() == WL_CONNECTED) {
    WiFiClient client = server.available();
    if (client) {
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
        }
      }
      
      // /status endpoint
      else if (request.indexOf("GET /status") >= 0) {
        client.println("HTTP/1.1 200 OK");
        client.println("Content-Type: application/json");
        client.println("Access-Control-Allow-Origin: *");
        client.println("Connection: close");
        client.println();
        client.print("{\"status\":\"connected\",\"ip\":\"");
        client.print(WiFi.localIP().toString());
        client.println("\"}");
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
          delay(100);
        }
      }
      
      client.stop();
    }
  }
  
  delay(10);
}
