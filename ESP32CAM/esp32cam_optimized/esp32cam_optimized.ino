#include "esp_camera.h"
#include <WiFi.h>

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
// CẤU HÌNH WIFI - THAY ĐỔI THEO MẠNG CỦA BẠN
// ============================================================
const char* ssid = "PI Coffee 24h";        // ⚠️ THAY TÊN WIFI
const char* password = "77778888";       // ⚠️ THAY MẬT KHẨU

// ============================================================
// WEB SERVER - Port 81
// ============================================================
WiFiServer server(81);  // ⚠️ Phải là port 81

// Biến toàn cục để quản lý stream
bool streamActive = false;
unsigned long lastFrameTime = 0;
const int TARGET_FPS = 10; // Giảm xuống 10 FPS để giảm độ trễ

void setup() {
  Serial.begin(115200);
  Serial.setDebugOutput(true);
  Serial.println();

  // ── CẤU HÌNH CAMERA ──────────────────────────────────────
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
  config.xclk_freq_hz = 10000000; // 10MHz - Giảm xuống để ổn định hơn
  config.pixel_format = PIXFORMAT_JPEG;

  // ── TỐI ƯU HÓA CHO STREAM REALTIME (ĐỘ TRỄ < 2S) ──────────────
  if(psramFound()){
    // Có PSRAM: Cấu hình cho stream mượt
    config.frame_size = FRAMESIZE_QVGA;  // 320x240 - Cân bằng chất lượng/tốc độ
    config.jpeg_quality = 12;            // Chất lượng cao hơn (số càng nhỏ càng đẹp)
    config.fb_count = 2;                 // 2 buffer để stream mượt hơn
    config.fb_location = CAMERA_FB_IN_PSRAM;
  } else {
    // Không PSRAM: Cấu hình tối thiểu
    config.frame_size = FRAMESIZE_QQVGA; // 160x120 - Cực nhỏ
    config.jpeg_quality = 15;            
    config.fb_count = 1;
  }

  // Khởi tạo camera
  esp_err_t err = esp_camera_init(&config);
  if (err != ESP_OK) {
    Serial.printf("Camera init failed with error 0x%x", err);
    return;
  }

  // ── TINH CHỈNH SENSOR ĐỂ TĂNG CHẤT LƯỢNG ──────────────────
  sensor_t * s = esp_camera_sensor_get();
  if (s != NULL) {
    // Cấu hình cân bằng giữa chất lượng và tốc độ
    s->set_brightness(s, 0);     // Brightness mặc định
    s->set_contrast(s, 1);       // Tăng contrast một chút
    s->set_saturation(s, 0);     // Saturation mặc định
    s->set_sharpness(s, 1);      // Tăng sharpness để rõ hơn
    
    // Bật white balance để màu sắc tự nhiên
    s->set_whitebal(s, 1);       // Bật white balance
    s->set_awb_gain(s, 1);       // Bật AWB gain
    s->set_wb_mode(s, 0);        // Auto white balance
    
    // Exposure tự động để thích nghi ánh sáng
    s->set_exposure_ctrl(s, 1);  // Auto exposure
    s->set_aec2(s, 1);           // Bật AEC DSP
    s->set_ae_level(s, 0);       // Exposure level mặc định
    s->set_aec_value(s, 300);    // Exposure time vừa phải
    s->set_gain_ctrl(s, 1);      // Auto gain
    s->set_agc_gain(s, 0);       // Auto gain
    s->set_gainceiling(s, (gainceiling_t)2); // Gain ceiling vừa phải
    
    // Bật một số filter để ảnh đẹp hơn
    s->set_bpc(s, 0);            // Tắt black pixel correction (không cần)
    s->set_wpc(s, 1);            // Bật white pixel correction
    s->set_raw_gma(s, 1);        // Bật gamma correction
    s->set_lenc(s, 1);           // Bật lens correction
    
    // Cài đặt cơ bản
    s->set_hmirror(s, 0);        
    s->set_vflip(s, 0);          
    s->set_dcw(s, 1);            // Bật downsize
    s->set_colorbar(s, 0);
    
    Serial.println("✅ Đã cấu hình camera cho chất lượng tốt");
  }

  // ── KẾT NỐI WIFI ──────────────────────────────────────────
  Serial.println("\n--- BẮT ĐẦU QUÉT WIFI ĐỂ CHẨN ĐOÁN ---");
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  delay(100);

  int n = WiFi.scanNetworks();
  bool found = false;
  if (n == 0) {
    Serial.println("❌ Không tìm thấy mạng WiFi nào xung quanh!");
  } else {
    Serial.printf("🔍 Tìm thấy %d mạng. Đang tìm '%s'...\n", n, ssid);
    for (int i = 0; i < n; ++i) {
      if (WiFi.SSID(i) == ssid) {
        Serial.printf("✅ Đã thấy mạng của bạn! Cường độ sóng: %d dBm\n", WiFi.RSSI(i));
        found = true;
        break;
      }
    }
    if (!found) {
      Serial.println("❌ KHÔNG TÌM THẤY tên mạng của bạn trong danh sách trên.");
      Serial.println("👉 Hãy kiểm tra lại SSID (chú ý chữ hoa/thường) hoặc mang ESP32 lại gần router.");
    }
  }

  Serial.printf("\nĐang thử kết nối tới: %s\n", ssid);
  WiFi.begin(ssid, password);

  int retry_count = 0;
  while (WiFi.status() != WL_CONNECTED && retry_count < 40) {
    delay(500);
    Serial.print(".");
    retry_count++;
    
    // In trạng thái lỗi định kỳ
    if (retry_count % 10 == 0) {
      Serial.print("\nTrạng thái hiện tại: ");
      switch (WiFi.status()) {
        case WL_NO_SSID_AVAIL:    Serial.println("Không tìm thấy SSID"); break;
        case WL_CONNECT_FAILED:   Serial.println("Kết nối thất bại / Sai PASS"); break;
        case WL_DISCONNECTED:     Serial.println("Bị ngắt kết nối"); break;
        default:                  Serial.println("Đang chờ..."); break;
      }
    }
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\n✅ KẾT NỐI THÀNH CÔNG!");
    Serial.print("   📍 IP Local: ");
    Serial.println(WiFi.localIP());
    Serial.println("   📺 Stream: http://" + WiFi.localIP().toString() + ":81/stream");
  } else {
    Serial.println("\n❌ THẤT BẠI: Vẫn không thể kết nối. Hãy kiểm tra nguồn điện (cần 5V-2A)!");
    return;  // Dừng nếu không kết nối được
  }

  // Khởi động server
  Serial.println("\n🚀 Đang khởi động Web Server trên port 81...");
  server.begin();
  Serial.println("✅ Web Server đã sẵn sàng!");
  Serial.println("📡 Đang chờ requests...\n");
}

void loop() {
  WiFiClient client = server.accept();
  if (!client) return;

  Serial.println("📥 Nhận request từ client...");
  
  String request = client.readStringUntil('\r');
  Serial.print("   Request: ");
  Serial.println(request);
  
  client.flush();

  // ── ENDPOINT: /capture (Chụp 1 ảnh chất lượng cao) ────────
  if (request.indexOf("GET /capture") >= 0) {
    camera_fb_t * fb = esp_camera_fb_get();
    if (!fb) {
      Serial.println("Camera capture failed");
      client.println("HTTP/1.1 500 Internal Server Error");
      client.stop();
      return;
    }

    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: image/jpeg");
    client.println("Access-Control-Allow-Origin: *");
    client.printf("Content-Length: %u\r\n", fb->len);
    client.println("Connection: close");
    client.println();
    
    // Gửi ảnh
    client.write(fb->buf, fb->len);
    esp_camera_fb_return(fb);
    
    Serial.println("📸 Captured 1 frame");
  }
  
  // ── ENDPOINT: /stream (MJPEG Stream tối ưu) ───────────────
  else if (request.indexOf("GET /stream") >= 0) {
    streamActive = true;
    
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: multipart/x-mixed-replace; boundary=frame");
    client.println("Access-Control-Allow-Origin: *");
    client.println("Connection: close");
    client.println();

    while (client.connected() && streamActive) {
      // Giới hạn FPS
      unsigned long now = millis();
      if (now - lastFrameTime < (1000 / TARGET_FPS)) {
        delay(5);
        continue;
      }
      lastFrameTime = now;

      camera_fb_t * fb = esp_camera_fb_get();
      if (!fb) {
        Serial.println("Frame capture failed");
        break;
      }

      client.println("--frame");
      client.println("Content-Type: image/jpeg");
      client.printf("Content-Length: %u\r\n\r\n", fb->len);
      client.write(fb->buf, fb->len);
      client.println();
      
      esp_camera_fb_return(fb);
      
      // Kiểm tra client còn kết nối không
      if (!client.connected()) {
        streamActive = false;
        break;
      }
    }
    
    Serial.println("Stream ended");
  }
  
  // ── ENDPOINT: /status ──────────────────────────────────────
  else if (request.indexOf("GET /status") >= 0) {
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: application/json");
    client.println("Access-Control-Allow-Origin: *");
    client.println("Connection: close");
    client.println();
    client.println("{\"status\":\"online\",\"ip\":\"" + WiFi.localIP().toString() + "\"}");
  }
  
  // ── ENDPOINT: /config (Điều chỉnh camera runtime) ─────────
  else if (request.indexOf("GET /config?") >= 0) {
    // Parse query parameters
    int qualityIdx = request.indexOf("quality=");
    int brightnessIdx = request.indexOf("brightness=");
    
    sensor_t * s = esp_camera_sensor_get();
    
    if (qualityIdx >= 0 && s != NULL) {
      int quality = request.substring(qualityIdx + 8, qualityIdx + 10).toInt();
      s->set_quality(s, quality);
      Serial.printf("Quality set to: %d\n", quality);
    }
    
    if (brightnessIdx >= 0 && s != NULL) {
      int brightness = request.substring(brightnessIdx + 11, brightnessIdx + 13).toInt();
      s->set_brightness(s, brightness - 2); // Convert 0-4 to -2 to 2
      Serial.printf("Brightness set to: %d\n", brightness - 2);
    }
    
    client.println("HTTP/1.1 200 OK");
    client.println("Content-Type: application/json");
    client.println("Access-Control-Allow-Origin: *");
    client.println("Connection: close");
    client.println();
    client.println("{\"status\":\"config updated\"}");
  }
  
  else {
    client.println("HTTP/1.1 404 Not Found");
    client.println("Content-Type: text/html");
    client.println("Connection: close");
    client.println();
    client.println("<!DOCTYPE HTML><html><body>");
    client.println("<h1>ESP32-CAM Face Recognition Server</h1>");
    client.println("<p>Endpoints:</p>");
    client.println("<ul>");
    client.println("<li><a href='/stream'>/stream</a> - MJPEG Stream</li>");
    client.println("<li><a href='/capture'>/capture</a> - Capture single frame</li>");
    client.println("<li><a href='/status'>/status</a> - Server status</li>");
    client.println("<li>/config?quality=10&brightness=2 - Adjust settings</li>");
    client.println("</ul>");
    client.println("</body></html>");
  }

  client.stop();
}
