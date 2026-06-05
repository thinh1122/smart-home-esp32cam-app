/*
 * ESP32-S3: BLE WiFi Provisioning + Relay + ACS712 + MQTT + Voice Control (INMP441)
 * Arduino Framework — nap bang Arduino IDE hoac PlatformIO
 *
 * Flow:
 *   Boot → doc WiFi tu NVS (Preferences)
 *     Co WiFi → ket noi → MQTT → relay + ACS712 + voice
 *     Khong co → BLE mode → Flutter gui SSID+PASS → luu → restart
 *
 * MQTT Topics:
 *   Sub: home/devices/light/{room}/command  {"state":"ON"/"OFF"}
 *   Pub: home/devices/light/{room}/state    {"state":"ON"/"OFF","ts":...}  retain
 *   Pub: home/devices/light/{room}/power    {"watt":...,"current":...,"state":...,"ts":...}
 */

#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <Preferences.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <PubSubClient.h>
#include <ArduinoJson.h>

// ============================================================
// CONFIG
// ============================================================
#define MQTT_BROKER     "93a7685af2254d02a616baa58c6ae86e.s1.eu.hivemq.cloud"
#define MQTT_PORT       8883
#define MQTT_USER       "smarthome"
#define MQTT_PASS       "SmartHome@2026"
#define MQTT_CLIENT_ID  "esp32s3_relay_01"

#define RELAY_PIN       2    // GPIO2 → Relay IN
#define ACS712_PIN      7    // GPIO7 → ACS712 OUT (ADC)

#define TOPIC_LOG       "home/logs/activity"

#define ACS712_SENSITIVITY  185.0f
#define VOLTAGE_AC          220.0f
#define POWER_INTERVAL_MS   5000

#define BOOT_PIN            0
#define RESET_HOLD_MS       2000

#define VOICE_THRESHOLD     0.7f

// BLE UUIDs
#define SERVICE_UUID    "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define SSID_UUID       "beb5483e-36e1-4688-b7f5-ea07361b26a8"
#define PASS_UUID       "1c95d5e3-d8f7-413a-bf3d-7a2e5d7be87e"
#define STATUS_UUID     "d8de624e-140f-4a22-8594-e2216b84a5f2"
#define WIFILIST_UUID   "2b8c9e50-7182-4f32-8414-b49911e0eb7e"
#define ROOM_UUID       "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

// ============================================================
// GLOBALS
// ============================================================
Preferences       prefs;
WiFiClientSecure  wifiClient;
PubSubClient      mqtt(wifiClient);

BLECharacteristic *pStatus   = nullptr;
BLECharacteristic *pWifiList = nullptr;
bool bleConnected   = false;
bool wifiReceived   = false;
String rxSSID       = "";
String rxPass       = "";

String g_room      = "living_room";
String g_topicCmd;
String g_topicState;
String g_topicPower;

bool          relayState     = false;
unsigned long lastPower      = 0;
unsigned long lastReconnect  = 0;
unsigned long bootPressStart = 0;
bool          bootPressed    = false;

// ============================================================
// RELAY
// ============================================================
void relaySet(bool on) {
  relayState = on;
  digitalWrite(RELAY_PIN, on ? HIGH : LOW);
  Serial.printf("Relay %s\n", on ? "ON" : "OFF");
}

// ============================================================
// PUBLISH
// ============================================================
void publishState() {
  StaticJsonDocument<128> doc;
  doc["state"] = relayState ? "ON" : "OFF";
  doc["ts"]    = millis();
  char buf[128];
  serializeJson(doc, buf);
  mqtt.publish(g_topicState.c_str(), buf, true);
  Serial.printf("State: %s\n", buf);
}

void publishPower() {
  long sum = 0;
  for (int i = 0; i < 50; i++) {
    sum += analogRead(ACS712_PIN);
    delayMicroseconds(200);
  }
  float avg     = sum / 50.0f;
  float volt_mv = (avg / 4095.0f) * 3300.0f;
  float current = (volt_mv - 1650.0f) / ACS712_SENSITIVITY;
  if (current < 0)     current = -current;
  if (current < 0.05f) current = 0.0f;
  float watt = current * VOLTAGE_AC;

  StaticJsonDocument<128> doc;
  doc["current"] = round(current * 100) / 100.0f;
  doc["watt"]    = round(watt);
  doc["state"]   = relayState ? "ON" : "OFF";
  doc["ts"]      = millis();
  char buf[128];
  serializeJson(doc, buf);
  mqtt.publish(g_topicPower.c_str(), buf);
  Serial.printf("Power: %.2fA  %.0fW\n", current, watt);
}

// ============================================================
// MQTT CALLBACK
// ============================================================
void onMqttMessage(char* topic, byte* payload, unsigned int len) {
  String msg;
  for (unsigned int i = 0; i < len; i++) msg += (char)payload[i];
  Serial.printf("MQTT [%s]: %s\n", topic, msg.c_str());

  StaticJsonDocument<128> doc;
  if (deserializeJson(doc, msg) != DeserializationError::Ok) return;

  if (doc.containsKey("room")) {
    String newRoom = doc["room"] | "";
    if (newRoom.length() > 0 && newRoom != g_room) {
      mqtt.unsubscribe(g_topicCmd.c_str());
      g_room       = newRoom;
      g_topicCmd   = "home/devices/light/" + g_room + "/command";
      g_topicState = "home/devices/light/" + g_room + "/state";
      g_topicPower = "home/devices/light/" + g_room + "/power";
      prefs.begin("cfg", false);
      prefs.putString("room", g_room);
      prefs.end();
      mqtt.subscribe(g_topicCmd.c_str());
      Serial.println("Room updated: " + g_room);
    }
    return;
  }

  String state = doc["state"] | "";
  state.toUpperCase();
  if (state == "ON")       { relaySet(true);  publishState(); }
  else if (state == "OFF") { relaySet(false); publishState(); }
}

// ============================================================
// MQTT CONNECT
// ============================================================
bool connectMQTT() {
  if (mqtt.connected()) return true;
  Serial.printf("MQTT connecting %s:%d...", MQTT_BROKER, MQTT_PORT);

  // Client ID unique theo MAC
  String clientId = "esp32s3_";
  clientId += WiFi.macAddress();
  clientId.replace(":", "");

  String will = "{\"state\":\"OFFLINE\"}";
  bool ok = mqtt.connect(clientId.c_str(), MQTT_USER, MQTT_PASS,
                         g_topicState.c_str(), 0, true, will.c_str());
  if (ok) {
    Serial.println(" OK");
    mqtt.subscribe(g_topicCmd.c_str());
    String mac = WiFi.macAddress();
    mac.replace(":", "");
    mac.toLowerCase();
    mqtt.subscribe(("home/devices/config/" + mac).c_str());
    publishState();

    StaticJsonDocument<128> log;
    log["message"] = "ESP32-S3 " + g_room + " online";
    log["type"]    = "info";
    log["ts"]      = millis();
    char logBuf[128];
    serializeJson(log, logBuf);
    mqtt.publish(TOPIC_LOG, logBuf);
  } else {
    Serial.printf(" FAIL rc=%d\n", mqtt.state());
  }
  return ok;
}

// ============================================================
// BLE CALLBACKS
// ============================================================
class BLEConn : public BLEServerCallbacks {
  void onConnect(BLEServer*)    { bleConnected = true;  Serial.println("BLE connected"); }
  void onDisconnect(BLEServer*) { bleConnected = false; BLEDevice::startAdvertising(); }
};

class SSIDcb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    rxSSID = c->getValue().c_str();
    Serial.println("BLE SSID: " + rxSSID);
  }
};

class PASScb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    rxPass = c->getValue().c_str();
    wifiReceived = true;
    Serial.println("BLE PASS received");
  }
};

class ROOMcb : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* c) {
    String room = c->getValue().c_str();
    if (room.length() > 0) {
      g_room       = room;
      g_topicCmd   = "home/devices/light/" + g_room + "/command";
      g_topicState = "home/devices/light/" + g_room + "/state";
      g_topicPower = "home/devices/light/" + g_room + "/power";
      prefs.begin("cfg", false);
      prefs.putString("room", g_room);
      prefs.end();
      Serial.println("BLE ROOM: " + g_room);
    }
  }
};

// ============================================================
// BLE INIT
// ============================================================
void initBLE() {
  uint8_t mac[6];
  WiFi.macAddress(mac);
  String name = "ESP32S3_Relay-";
  char buf[5];
  snprintf(buf, sizeof(buf), "%02X%02X", mac[4], mac[5]);
  name += buf;

  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  int n = WiFi.scanNetworks();
  String list = "";
  for (int i = 0; i < min(n, 10); i++) {
    if (WiFi.SSID(i).length() > 0) {
      list += WiFi.SSID(i) + ";";
      if (list.length() > 200) break;
    }
  }
  WiFi.scanDelete();
  WiFi.mode(WIFI_OFF);
  delay(300);

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

  auto* roomChar = svc->createCharacteristic(ROOM_UUID, BLECharacteristic::PROPERTY_WRITE);
  roomChar->setCallbacks(new ROOMcb());

  svc->start();
  BLEAdvertising* adv = BLEDevice::getAdvertising();
  adv->addServiceUUID(SERVICE_UUID);
  adv->setScanResponse(true);
  BLEDevice::startAdvertising();

  Serial.println("BLE: " + name + " — waiting for Flutter");
}

// ============================================================
// WIFI
// ============================================================
void loadAndConnect() {
  prefs.begin("wifi", true);
  String ssid = prefs.getString("ssid", "");
  String pass = prefs.getString("pass", "");
  prefs.end();

  if (ssid.isEmpty()) { Serial.println("No WiFi saved → BLE mode"); return; }

  Serial.println("Saved WiFi: " + ssid);
  WiFi.mode(WIFI_STA);
  WiFi.begin(ssid.c_str(), pass.c_str());
  WiFi.setSleep(false);

  Serial.print("Connecting");
  for (int i = 0; i < 20 && WiFi.status() != WL_CONNECTED; i++) {
    delay(500); Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.printf("\nWiFi OK — IP: %s\n", WiFi.localIP().toString().c_str());
  } else {
    Serial.println("\nWiFi failed → BLE mode");
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
    Serial.printf("\nWiFi OK — IP: %s\n", WiFi.localIP().toString().c_str());
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
// RESET BUTTON
// ============================================================
void blinkReset() {
  for (int i = 0; i < 3; i++) {
    digitalWrite(RELAY_PIN, HIGH); delay(150);
    digitalWrite(RELAY_PIN, LOW);  delay(150);
  }
}

void checkResetButton() {
  if (millis() < 10000) return;  // bỏ qua 10s đầu boot

  if (digitalRead(BOOT_PIN) == LOW) {
    if (!bootPressed) {
      bootPressed    = true;
      bootPressStart = millis();
      Serial.println("BOOT held — giu tiep 5s de reset WiFi...");
    } else if (millis() - bootPressStart >= RESET_HOLD_MS) {
      Serial.println(">>> Reset WiFi → BLE mode...");
      blinkReset();
      prefs.begin("wifi", false);
      prefs.clear();
      prefs.end();
      delay(300);
      ESP.restart();
    }
  } else {
    bootPressed = false;
  }
}

// ============================================================
// SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("\n=== ESP32-S3 Relay + ACS712 + MQTT + Voice ===");

  pinMode(RELAY_PIN, OUTPUT);
  digitalWrite(RELAY_PIN, LOW);
  pinMode(BOOT_PIN, INPUT_PULLUP);

  analogReadResolution(12);
  analogSetAttenuation(ADC_11db);

  prefs.begin("cfg", true);
  g_room = prefs.getString("room", "living_room");
  prefs.end();
  g_topicCmd   = "home/devices/light/" + g_room + "/command";
  g_topicState = "home/devices/light/" + g_room + "/state";
  g_topicPower = "home/devices/light/" + g_room + "/power";
  Serial.println("Room: " + g_room);

  loadAndConnect();

  if (WiFi.status() == WL_CONNECTED) {
    wifiClient.setInsecure();  // dùng TLS không xác minh CA cert
    mqtt.setServer(MQTT_BROKER, MQTT_PORT);
    mqtt.setCallback(onMqttMessage);
    mqtt.setKeepAlive(60);
    mqtt.setBufferSize(512);
    connectMQTT();
  } else {
    initBLE();
  }

  Serial.println("=================================================\n");
}

// ============================================================
// LOOP
// ============================================================
void loop() {
  checkResetButton();

  if (wifiReceived) {
    wifiReceived = false;
    if (pStatus) { pStatus->setValue("connecting"); pStatus->notify(); }
    delay(300);

    if (connectWiFi(rxSSID, rxPass)) {
      prefs.begin("wifi", false);
      prefs.putString("ssid", rxSSID);
      prefs.putString("pass", rxPass);
      prefs.end();
      if (pStatus) {
        String s = "connected|" + WiFi.localIP().toString();
        pStatus->setValue(s.c_str());
        pStatus->notify();
        delay(2000);
      }
      Serial.println("Restarting...");
      ESP.restart();
    }
  }

  if (WiFi.status() != WL_CONNECTED) return;

  if (!mqtt.connected()) {
    unsigned long now = millis();
    if (now - lastReconnect >= 3000) {
      lastReconnect = now;
      connectMQTT();
    }
  }
  mqtt.loop();

  unsigned long now = millis();
  if (now - lastPower >= POWER_INTERVAL_MS) {
    lastPower = now;
    publishPower();
  }

  // handleVoice() đã xóa
}
