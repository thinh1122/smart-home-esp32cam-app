import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

import cv2
import numpy as np
import os
import sqlite3
import threading
import traceback
import requests
from flask import Flask, request, jsonify
from datetime import datetime
import base64
from PIL import Image, ImageEnhance
import mediapipe as mp
import time
# ⭐ THÊM MỚI - Import MQTT
import paho.mqtt.client as mqtt
import json

# Import SSIM nếu có (optional)
try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    HAS_SSIM = False
    print("⚠️ scikit-image không có - SSIM sẽ bị bỏ qua")

app = Flask(__name__)

# ============================================================
# CẤU HÌNH HỆ THỐNG NÂNG CAO
# ============================================================
IMG_DIR = "img"
TEMP_DIR = "temp"
DB_FILE = "members.db"

# ⭐ MQTTX Configuration (HiveMQ Public Broker)
MQTT_BROKER = "broker.hivemq.com"  # HiveMQ public broker ít rớt mạng hơn Mosquitto
MQTT_PORT = 1883
MQTT_USERNAME = ""  
MQTT_PASSWORD = ""  
MQTT_USE_TLS = False

# ⭐ THÊM MỚI - Kết nối MQTT
mqtt_client = None
mqtt_connected = False

# ⭐ THÊM MỚI - MJPEG Relay cho nhiều người xem
ESP32_STREAM_URL = "http://192.168.110.230:81/stream" # Thay đổi theo IP ESP32 của bạn
current_frame_bytes = None
frame_lock = threading.Lock()

def fetch_esp32_frames():
    """Luồng liên tục lấy ảnh từ ESP32 để relay cho nhiều app cùng coi"""
    global current_frame_bytes
    print(f"📹 Bắt đầu kết nối luồng gốc từ ESP32: {ESP32_STREAM_URL}")
    while True:
        try:
            r = requests.get(ESP32_STREAM_URL, stream=True, timeout=10)
            if r.status_code != 200:
                time.sleep(2)
                continue
                
            combined_bytes = b''
            for chunk in r.iter_content(chunk_size=1024):
                combined_bytes += chunk
                a = combined_bytes.find(b'\xff\xd8') # Start of JPEG
                b = combined_bytes.find(b'\xff\xd9') # End of JPEG
                if a != -1 and b != -1:
                    jpg = combined_bytes[a:b+2]
                    combined_bytes = combined_bytes[b+2:]
                    with frame_lock:
                        current_frame_bytes = jpg
        except Exception as e:
            print(f"⚠️ Lỗi kết nối ESP32 Stream: {e}")
            time.sleep(2)

# Start fetcher thread
threading.Thread(target=fetch_esp32_frames, daemon=True).start()

def on_mqtt_connect(client, userdata, flags, reason_code, properties):
    global mqtt_connected
    if reason_code == 0:
        print("✅ MQTTX (Mosquitto) connected successfully", flush=True)
        mqtt_connected = True
        client.subscribe("home/test/+", qos=1)
        client.subscribe("home/flutter/+", qos=1)
    else:
        print(f"❌ MQTTX connection failed: {reason_code}", flush=True)
        mqtt_connected = False

def on_mqtt_disconnect(client, userdata, disconnect_flags, reason_code, properties):
    global mqtt_connected
    print(f"⚠️ MQTTX disconnected: {reason_code}", flush=True)
    mqtt_connected = False
    def reconnect():
        time.sleep(3)
        try:
            print("🔄 Attempting MQTT reconnect...", flush=True)
            client.reconnect()
        except Exception as e:
            print(f"❌ Reconnect failed: {e}", flush=True)
    threading.Thread(target=reconnect, daemon=True).start()

try:
    mqtt_client = mqtt.Client(client_id=f"python_ai_server_{int(time.time())}", callback_api_version=mqtt.CallbackAPIVersion.VERSION2)
    if MQTT_USERNAME and MQTT_PASSWORD:
        mqtt_client.username_pw_set(MQTT_USERNAME, MQTT_PASSWORD)
    mqtt_client.on_connect = on_mqtt_connect
    mqtt_client.on_disconnect = on_mqtt_disconnect
    mqtt_client.keepalive = 60
    mqtt_client.reconnect_delay_set(min_delay=1, max_delay=120)
    mqtt_client.enable_logger()
    if MQTT_USE_TLS:
        import ssl
        mqtt_client.tls_set(cert_reqs=ssl.CERT_NONE, tls_version=ssl.PROTOCOL_TLS)
        mqtt_client.tls_insecure_set(True)
    print(f"🔌 Connecting to MQTTX (Mosquitto)...", flush=True)
    mqtt_client.connect(MQTT_BROKER, MQTT_PORT, 60)
    mqtt_client.loop_start()
    time.sleep(2)
except Exception as e:
    print(f"❌ MQTTX connection error: {e}", flush=True)
    mqtt_client = None

def publish_mqtt(topic, payload):
    global mqtt_client, mqtt_connected
    if mqtt_client and mqtt_connected:
        try:
            mqtt_client.publish(topic, json.dumps(payload), qos=1)
            print(f"📤 Published to MQTTX [{topic}]: {payload}")
            return True
        except Exception as e:
            print(f"❌ MQTTX publish error: {e}")
            return False
    return False

mp_face_detection = mp.solutions.face_detection
mp_drawing = mp.solutions.drawing_utils

if not os.path.exists(IMG_DIR): os.makedirs(IMG_DIR)
if not os.path.exists(TEMP_DIR): os.makedirs(TEMP_DIR)

known_face_templates = []
known_face_names = []
known_face_info = {}
lock = threading.Lock()
previous_frame = None
MOTION_THRESHOLD = 25
MIN_MOTION_PIXELS = 500

def detect_motion_frame_diff(current_frame):
    global previous_frame
    gray = cv2.cvtColor(current_frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, (160, 120))
    gray = cv2.GaussianBlur(gray, (5, 5), 0)
    if previous_frame is None:
        previous_frame = gray
        return False, 0
    frame_diff = cv2.absdiff(previous_frame, gray)
    _, thresh = cv2.threshold(frame_diff, MOTION_THRESHOLD, 255, cv2.THRESH_BINARY)
    motion_pixels = cv2.countNonZero(thresh)
    previous_frame = gray
    return motion_pixels > MIN_MOTION_PIXELS, motion_pixels

face_detection_state = {
    'face_detected': False,
    'stable_start_time': None,
    'last_detection_time': None,
    'capture_in_progress': False
}

def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute('''
        CREATE TABLE IF NOT EXISTS members (
            id          TEXT PRIMARY KEY,
            name        TEXT NOT NULL,
            role        TEXT DEFAULT 'Thành viên',
            avatar      TEXT,
            pose1       TEXT,
            pose2       TEXT,
            pose3       TEXT,
            enrolled_at TEXT
        )
    ''')
    conn.commit()
    conn.close()

def enhance_small_image_to_hd(image):
    height, width = image.shape[:2]
    if width < 400:
        scale_factor = 400.0 / width
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        image = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
    pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    pil_image = ImageEnhance.Brightness(pil_image).enhance(1.5)
    pil_image = ImageEnhance.Contrast(pil_image).enhance(1.4)
    pil_image = ImageEnhance.Sharpness(pil_image).enhance(1.3)
    enhanced = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
    lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(4,4)).apply(l)
    enhanced = cv2.merge([l, a, b])
    enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
    return cv2.bilateralFilter(enhanced, 5, 50, 50)

def detect_faces_advanced_glasses_mask(image):
    faces = []
    with mp_face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5) as face_detection:
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = face_detection.process(rgb_image)
        if results.detections:
            h, w, _ = image.shape
            for detection in results.detections:
                bbox = detection.location_data.relative_bounding_box
                x, y, width, height = int(bbox.xmin * w), int(bbox.ymin * h), int(bbox.width * w), int(bbox.height * h)
                margin = 0.25
                x_m, y_m = int(width * margin), int(height * margin)
                x, y = max(0, x - x_m), max(0, y - y_m)
                width, height = min(w - x, width + 2 * x_m), min(h - y, height + 2 * y_m)
                if width >= 50 and height >= 50:
                    faces.append({'bbox': (x, y, width, height), 'confidence': float(detection.score[0])})
    if not faces:
        face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        profile_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_profileface.xml')
        gray = cv2.equalizeHist(cv2.cvtColor(image, cv2.COLOR_BGR2GRAY))
        all_faces = list(face_cascade.detectMultiScale(gray, 1.03, 2, minSize=(20, 20))) + list(profile_cascade.detectMultiScale(gray, 1.03, 2, minSize=(20, 20)))
        for (x, y, w, h) in all_faces: faces.append({'bbox': (x, y, w, h), 'confidence': 0.8})
    return faces

def enhance_image_for_glasses_mask(image):
    pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    pil_image = ImageEnhance.Brightness(pil_image).enhance(1.3)
    pil_image = ImageEnhance.Contrast(pil_image).enhance(1.2)
    pil_image = ImageEnhance.Sharpness(pil_image).enhance(1.2)
    enhanced = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
    lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8,8)).apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)

def extract_face_template_advanced(image, bbox):
    x, y, w, h = bbox
    face_crop = image[y:y+h, x:x+w]
    if face_crop.size == 0: return None
    face_resized = cv2.resize(face_crop, (160, 160))
    face_enhanced = enhance_image_for_glasses_mask(face_resized)
    face_gray = cv2.cvtColor(face_enhanced, cv2.COLOR_BGR2GRAY)
    face_gray = cv2.GaussianBlur(face_gray, (3, 3), 0)
    return cv2.equalizeHist(face_gray)

def compare_faces_advanced_template(template1, template2):
    if template1 is None or template2 is None: return 0.0
    res1 = cv2.matchTemplate(template1, template2, cv2.TM_CCOEFF_NORMED)
    _, score1, _, _ = cv2.minMaxLoc(res1)
    score2 = ssim(template1, template2) if HAS_SSIM else score1
    hist1 = cv2.calcHist([template1], [0], None, [256], [0, 256])
    hist2 = cv2.calcHist([template2], [0], None, [256], [0, 256])
    score3 = cv2.compareHist(hist1, hist2, cv2.HISTCMP_CORREL)
    return max(0.0, min(1.0, (score1 * 0.4) + (score2 * 0.4) + (score3 * 0.2)))

def load_known_faces():
    global known_face_templates, known_face_names, known_face_info
    new_t, new_n, new_i = [], [], {}
    conn = get_db()
    rows = conn.execute("SELECT id, name, role, avatar, pose1, pose2, pose3 FROM members").fetchall()
    for row in rows:
        name = row['name']
        for p_num in [1, 2, 3]:
            p_path = row[f'pose{p_num}']
            if p_path and os.path.exists(p_path):
                bgr = cv2.imread(p_path)
                if bgr is not None:
                    faces = detect_faces_advanced_glasses_mask(bgr)
                    if faces:
                        best = max(faces, key=lambda f: f['confidence'])
                        templ = extract_face_template_advanced(bgr, best['bbox'])
                        if templ is not None:
                            new_t.append(templ)
                            new_n.append(name)
                            new_i[name] = {'id': row['id'], 'role': row['role'], 'avatar': row['avatar']}
    conn.close()
    with lock:
        known_face_templates, known_face_names, known_face_info = new_t, new_n, new_i

@app.route('/recognize', methods=['POST'])
def recognize():
    data = request.json
    if not data or 'image_base64' not in data: return jsonify({"error": "Missing data"}), 400
    img_data = base64.b64decode(data['image_base64'])
    bgr = cv2.imdecode(np.frombuffer(img_data, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None: return jsonify({"face_count": 0, "faces": [], "motion": False}), 200
    has_m, m_px = detect_motion_frame_diff(bgr)
    if not has_m: return jsonify({"face_count": 0, "faces": [], "motion": False, "motion_pixels": int(m_px)}), 200
    d_faces = detect_faces_advanced_glasses_mask(bgr)
    faces_res = [{'box': {'top': int(y), 'right': int(x+w), 'bottom': int(y+h), 'left': int(x)}, 'confidence': float(f['confidence'])} for f in d_faces for x, y, w, h in [f['bbox']]]
    return jsonify({"face_count": len(d_faces), "faces": faces_res, "motion": True, "motion_pixels": int(m_px)}), 200

@app.route('/smart_recognition', methods=['POST'])
def smart_recognition():
    global face_detection_state
    data = request.json
    if not data or 'image_base64' not in data: return jsonify({"error": "Missing data"}), 400
    img_data = base64.b64decode(data['image_base64'])
    bgr = cv2.imdecode(np.frombuffer(img_data, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None: return jsonify({"status": "no_image", "face_detected": False}), 200
    enhanced = enhance_small_image_to_hd(bgr)
    d_faces = detect_faces_advanced_glasses_mask(enhanced)
    curr = time.time()
    if not d_faces:
        face_detection_state = {'face_detected': False, 'stable_start_time': None, 'last_detection_time': None, 'capture_in_progress': False}
        return jsonify({"status": "no_face", "face_detected": False, "instruction": "reduce_frequency"}), 200
    face_detection_state['last_detection_time'] = curr
    if not face_detection_state['face_detected']:
        face_detection_state.update({'face_detected': True, 'stable_start_time': curr})
        return jsonify({"status": "face_detected", "face_detected": True, "countdown": 2.0, "instruction": "increase_frequency"}), 200
    stable = curr - face_detection_state['stable_start_time']
    if stable < 2.0: return jsonify({"status": "stabilizing", "face_detected": True, "countdown": 2.0 - stable, "instruction": "maintain_frequency"}), 200
    if not face_detection_state['capture_in_progress']:
        face_detection_state['capture_in_progress'] = True
        return jsonify({"status": "ready_to_capture", "face_detected": True, "instruction": "start_capture"}), 200
    return jsonify({"status": "capturing", "face_detected": True, "instruction": "wait"}), 200

def compare_with_database(captured_image_paths):
    captured_t = []
    for i, path in enumerate(captured_image_paths):
        bgr = cv2.imread(path)
        if bgr is not None:
            enhanced = enhance_image_for_glasses_mask(bgr)
            faces = detect_faces_advanced_glasses_mask(enhanced)
            if faces:
                best = max(faces, key=lambda f: f['confidence'])
                templ = extract_face_template_advanced(enhanced, best['bbox'])
                if templ is not None: captured_t.append(templ)
    if not captured_t: return {"status": "no_face_in_capture", "matched": False}
    with lock: l_t, l_n, l_i = list(known_face_templates), list(known_face_names), dict(known_face_info)
    if not l_t: return {"status": "no_registered_users", "matched": False}
    best_c, best_n = 0.0, None
    for templ in captured_t:
        for i, k_templ in enumerate(l_t):
            score = compare_faces_advanced_template(templ, k_templ)
            if score > 0.50 and score > best_c:
                best_c, best_n = score, l_n[i]
    if best_n:
        info = l_i.get(best_n, {})
        return {"status": "recognized", "matched": True, "name": best_n, "id": info.get('id', ''), "role": info.get('role', ''), "avatar": info.get('avatar', ''), "confidence": round(best_c, 3)}
    return {"status": "stranger", "matched": False, "name": "Người lạ", "confidence": round(best_c, 3)}

@app.route('/enroll', methods=['POST'])
def enroll():
    data = request.json
    name, m_id, role, avatar, pose = data['name'].strip(), str(data.get('id', '')), data.get('role', 'Thành viên'), data.get('avatar', ''), int(data.get('pose', 1))
    img_data = base64.b64decode(data['image_base64'])
    bgr = cv2.imdecode(np.frombuffer(img_data, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None or not detect_faces_advanced_glasses_mask(bgr): return jsonify({"error": "No face found"}), 400
    path = os.path.join(IMG_DIR, f"{name}_pose{pose}.jpg")
    cv2.imwrite(path, bgr)
    conn = get_db()
    if conn.execute("SELECT id FROM members WHERE id = ?", (m_id,)).fetchone():
        conn.execute(f"UPDATE members SET name=?, role=?, avatar=?, pose{pose}=? WHERE id=?", (name, role, avatar, path, m_id))
    else:
        conn.execute(f"INSERT INTO members (id, name, role, avatar, pose{pose}, enrolled_at) VALUES (?,?,?,?,?,?)", (m_id, name, role, avatar, path, datetime.now().isoformat()))
    conn.commit(); conn.close(); load_known_faces()
    return jsonify({"message": "Success", "pose_done": pose}), 200

@app.route('/members', methods=['GET'])
def get_members():
    conn = get_db()
    rows = conn.execute("SELECT * FROM members").fetchall()
    conn.close()
    return jsonify({"members": [dict(r) for r in rows]}), 200

@app.route('/delete', methods=['POST'])
def delete_face():
    data = request.json
    name, u_id = data.get('name', '').strip(), data.get('id', '').strip()
    conn = get_db()
    row = conn.execute("SELECT * FROM members WHERE id = ? OR name = ?", (u_id, name)).fetchone()
    if not row: conn.close(); return jsonify({"error": "Not found"}), 404
    for p in ['pose1', 'pose2', 'pose3']:
        if row[p] and os.path.exists(row[p]): os.remove(row[p])
    conn.execute("DELETE FROM members WHERE id = ?", (row['id'],))
    conn.commit(); conn.close(); load_known_faces()
    return jsonify({"message": "Deleted"}), 200

@app.route('/status', methods=['GET'])
def get_status():
    with lock: count = len(known_face_templates)
    return jsonify({"status": "running", "templates": count}), 200

@app.route('/stream')
def stream_relay():
    def generate():
        while True:
            with frame_lock:
                if current_frame_bytes:
                    yield (b'--frame\r\n' b'Content-Type: image/jpeg\r\n\r\n' + current_frame_bytes + b'\r\n')
            time.sleep(0.04)
    return app.response_class(generate(), mimetype='multipart/x-mixed-replace; boundary=frame')

@app.route('/auto_capture_compare', methods=['POST'])
def auto_capture_compare():
    data = request.json
    captured = []
    curr = int(time.time())
    for i, b64 in enumerate(data['images_base64']):
        path = os.path.join(TEMP_DIR, f"f_{curr}_{i}.jpg")
        with open(path, 'wb') as f: f.write(base64.b64decode(b64))
        captured.append(path)
    res = compare_with_database(captured)
    for p in captured: os.remove(p)
    if res.get('matched'):
        publish_mqtt("home/face_recognition/result", {"name": res['name'], "action": "recognized"})
    else:
        publish_mqtt("home/face_recognition/alert", {"action": "alert"})
    return jsonify(res), 200

if __name__ == '__main__':
    init_db(); load_known_faces()
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)