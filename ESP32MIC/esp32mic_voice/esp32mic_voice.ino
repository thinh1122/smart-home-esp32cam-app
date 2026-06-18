/*
 * ESP32-S3 #2 — Voice Control (INMP441 + Edge Impulse + MQTT)
 *
 * Chức năng:
 *   - Lắng nghe mic INMP441 liên tục
 *   - Nhận diện "on" / "off" bằng Edge Impulse model
 *   - Tự detect room từ retained state của ESP32-S3 #1
 *   - Publish MQTT đúng topic → relay bật/tắt + Flutter đồng bộ
 *
 * INMP441: SCK=5, WS=6, SD=4
 */

#include <phungthinh2611-project-1_inferencing.h>
#include <driver/i2s.h>
#include <esp_mac.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <PubSubClient.h>
#include <WiFiManager.h>

// ============================================================
// CONFIG
// ============================================================
#define AP_NAME      "SmartHome-Voice"  // Tên AP khi chưa có WiFi
#define BOOT_PIN     0                  // Nút BOOT = GPIO0
#define RESET_HOLD   3000               // Giữ 3 giây để reset WiFi

#define MQTT_BROKER "93a7685af2254d02a616baa58c6ae86e.s1.eu.hivemq.cloud"
#define MQTT_PORT   8883
#define MQTT_USER   "smarthome"
#define MQTT_PASS   "SmartHome@2026"

#define VOICE_THRESHOLD_ON   0.5f
#define VOICE_THRESHOLD_OFF  0.7f

#define I2S_SCK  5
#define I2S_WS   6
#define I2S_SD   4

#define AUDIO_BUF_SIZE  EI_CLASSIFIER_RAW_SAMPLE_COUNT

// Topic wildcard để detect room
#define TOPIC_STATE_WILDCARD  "home/devices/light/+/state"

// ============================================================
// GLOBALS
// ============================================================
WiFiClientSecure wifiClient;
PubSubClient     mqtt(wifiClient);

static int16_t *audioBuf = nullptr;

String currentRoom = "";   // room tự detect từ retained state
String topicCmd    = "";   // topic publish lệnh

unsigned long lastReconnect = 0;

// ============================================================
// MQTT CALLBACK — nhận retained state để detect room
// ============================================================
void onMqttMessage(char* topic, byte* payload, unsigned int len) {
  String t = String(topic);
  // topic dạng: home/devices/light/{room}/state
  // extract room từ topic
  int idx = t.indexOf("light/");
  int p1  = (idx >= 0) ? idx + 6 : -1;
  int p2  = t.indexOf("/state");
  if (p1 >= 0 && p2 > p1) {
    String room = t.substring(p1, p2);
    if (room != currentRoom) {
      currentRoom = room;
      topicCmd    = "home/devices/light/" + room + "/command";
      Serial.println("Room detected: " + room);
      Serial.println("Topic cmd: " + topicCmd);
    }
  }
}

// ============================================================
// WIFI — WiFiManager tự động lưu/load credentials
// ============================================================
void connectWiFi() {
  WiFiManager wm;
  wm.setConnectTimeout(30);
  wm.setConfigPortalTimeout(120);

  Serial.println("WiFiManager starting...");
  Serial.println("Giu nut BOOT 3s ngay luc nay de vao AP mode doi WiFi");
  if (!wm.autoConnect(AP_NAME)) {
    Serial.println("WiFi failed — restarting...");
    delay(3000);
    ESP.restart();
  }
  WiFi.setSleep(false);
  Serial.printf("WiFi OK — IP: %s\n", WiFi.localIP().toString().c_str());
}

// ============================================================
// RESET WIFI — giữ nút BOOT 3 giây
// ============================================================
void checkResetButton() {
  if (digitalRead(BOOT_PIN) == LOW) {
    unsigned long pressTime = millis();
    Serial.println("BOOT pressed — hold 3s to reset WiFi...");
    while (digitalRead(BOOT_PIN) == LOW) {
      if (millis() - pressTime >= RESET_HOLD) {
        Serial.println("Resetting WiFi...");
        WiFiManager wm;
        wm.resetSettings();
        delay(1000);
        ESP.restart();
      }
    }
  }
}

// ============================================================
// MQTT
// ============================================================
bool connectMQTT() {
  if (mqtt.connected()) return true;
  Serial.printf("MQTT connecting %s:%d...", MQTT_BROKER, MQTT_PORT);
  String clientId = "esp32mic_";
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  char buf[5];
  snprintf(buf, sizeof(buf), "%02x%02x", mac[4], mac[5]);
  clientId += buf;
  bool ok = mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS);
  if (ok) {
    Serial.println(" OK");
    // Subscribe wildcard để nhận retained state từ ESP32-S3 #1
    mqtt.subscribe(TOPIC_STATE_WILDCARD);
    Serial.println("Subscribed: " + String(TOPIC_STATE_WILDCARD));
  } else {
    Serial.printf(" FAIL rc=%d\n", mqtt.state());
  }
  return ok;
}

// ============================================================
// I2S MIC
// ============================================================
void initI2S() {
  i2s_config_t cfg = {
    .mode                 = (i2s_mode_t)(I2S_MODE_MASTER | I2S_MODE_RX),
    .sample_rate          = EI_CLASSIFIER_FREQUENCY,
    .bits_per_sample      = I2S_BITS_PER_SAMPLE_32BIT,
    .channel_format       = I2S_CHANNEL_FMT_ONLY_LEFT,
    .communication_format = I2S_COMM_FORMAT_STAND_I2S,
    .intr_alloc_flags     = ESP_INTR_FLAG_LEVEL1,
    .dma_buf_count        = 4,
    .dma_buf_len          = 512,
    .use_apll             = false,
  };
  i2s_pin_config_t pins = {
    .bck_io_num   = I2S_SCK,
    .ws_io_num    = I2S_WS,
    .data_out_num = I2S_PIN_NO_CHANGE,
    .data_in_num  = I2S_SD,
  };
  i2s_driver_install(I2S_NUM_0, &cfg, 0, NULL);
  i2s_set_pin(I2S_NUM_0, &pins);
  Serial.println("I2S mic OK");
}

// ============================================================
// EDGE IMPULSE CALLBACK
// ============================================================
static int audioCb(size_t offset, size_t length, float *out) {
  numpy::int16_to_float(audioBuf + offset, out, length);
  return 0;
}

// ============================================================
// VOICE HANDLE
// ============================================================
void handleVoice() {
  // Thu đủ AUDIO_BUF_SIZE samples
  size_t samplesRead = 0;
  while (samplesRead < AUDIO_BUF_SIZE) {
    int32_t raw[64];
    size_t got = 0;
    i2s_read(I2S_NUM_0, raw, sizeof(raw), &got, portMAX_DELAY);
    size_t n = got / sizeof(int32_t);
    for (size_t i = 0; i < n && samplesRead < AUDIO_BUF_SIZE; i++) {
      audioBuf[samplesRead++] = (int16_t)(raw[i] >> 14);
    }
  }

  // Inference
  signal_t sig;
  sig.total_length = AUDIO_BUF_SIZE;
  sig.get_data     = &audioCb;

  ei_impulse_result_t result;
  EI_IMPULSE_ERROR err = run_classifier(&sig, &result, false);
  if (err != EI_IMPULSE_OK) {
    Serial.printf("Classifier error: %d\n", err);
    return;
  }

  float confOn  = result.classification[1].value;  // "On"
  float confOff = result.classification[0].value;  // "Off"

  Serial.printf("On=%.2f Off=%.2f\n", confOn, confOff);

  // Chỉ publish khi đã biết room
  if (topicCmd.length() == 0) {
    Serial.println("Waiting for room detection...");
    return;
  }

  if (!mqtt.connected()) return;

  if (confOn > VOICE_THRESHOLD_ON && confOn > confOff) {
    Serial.println(">>> Voice ON → " + topicCmd);
    mqtt.publish(topicCmd.c_str(), "{\"state\":\"ON\",\"src\":\"voice\"}");
  } else if (confOff > VOICE_THRESHOLD_OFF && confOff > confOn) {
    Serial.println(">>> Voice OFF → " + topicCmd);
    mqtt.publish(topicCmd.c_str(), "{\"state\":\"OFF\",\"src\":\"voice\"}");
  }
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  pinMode(BOOT_PIN, INPUT_PULLUP);
  Serial.println("\n=== ESP32-S3 Voice Control ===");
  Serial.printf("PSRAM: %s (%d KB)\n", psramFound() ? "found" : "not found", ESP.getFreePsram() / 1024);

  audioBuf = (int16_t*)ps_malloc(AUDIO_BUF_SIZE * sizeof(int16_t));
  if (!audioBuf) {
    Serial.println("ERR: ps_malloc audioBuf failed!");
    ESP.restart();
  }
  Serial.printf("audioBuf: %d samples in PSRAM\n", AUDIO_BUF_SIZE);

  connectWiFi();

  wifiClient.setInsecure();
  mqtt.setServer(MQTT_BROKER, MQTT_PORT);
  mqtt.setBufferSize(512);
  mqtt.setCallback(onMqttMessage);
  connectMQTT();

  initI2S();

  Serial.println("=== Ready — listening... ===\n");
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  if (WiFi.status() != WL_CONNECTED) {
    Serial.println("WiFi lost — restarting...");
    delay(3000);
    ESP.restart();
  }

  if (!mqtt.connected()) {
    unsigned long now = millis();
    if (now - lastReconnect >= 3000) {
      lastReconnect = now;
      connectMQTT();
    }
  }
  mqtt.loop();
  checkResetButton();
  handleVoice();
}
