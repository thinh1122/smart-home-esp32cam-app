// ESP32-CAM SIMPLE TEST - Upload này trước để kiểm tra hardware
// Không cần camera library để test upload

void setup() {
  Serial.begin(115200);
  delay(1000);
  
  Serial.println("\n==================================================");
  Serial.println("🚀 ESP32-CAM SIMPLE TEST");
  Serial.println("📡 Kiểm tra upload và Serial Monitor");
  Serial.println("==================================================");
  
  // Test GPIO
  pinMode(2, OUTPUT);  // Built-in LED (nếu có)
  
  Serial.println("✅ ESP32-CAM khởi động thành công!");
  Serial.println("✅ Upload code hoạt động!");
  Serial.println("✅ Serial Monitor kết nối OK!");
  Serial.println("\n💡 Nếu thấy tin nhắn này = Hardware OK");
}

void loop() {
  static int count = 0;
  count++;
  
  // Blink LED
  digitalWrite(2, HIGH);
  delay(500);
  digitalWrite(2, LOW);
  delay(500);
  
  // Print heartbeat
  Serial.printf("💓 Heartbeat #%d - ESP32-CAM OK - Uptime: %lu ms\n", 
                count, millis());
  
  // Memory info
  if (count % 10 == 0) {
    Serial.printf("📊 Free heap: %d bytes\n", ESP.getFreeHeap());
    Serial.printf("📊 PSRAM: %s\n", psramFound() ? "Available" : "Not found");
  }
}