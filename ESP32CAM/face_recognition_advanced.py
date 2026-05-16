
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace', line_buffering=True)
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace', line_buffering=True)

import cv2
import numpy as np
import os
import sqlite3
import threading
import requests
from flask import Flask, jsonify, request
from datetime import datetime
import base64
from PIL import Image, ImageEnhance
import mediapipe as mp
import time
import json
import paho.mqtt.client as mqtt


app = Flask(__name__)

# ============================================================
# CONFIG
# ============================================================
IMG_DIR  = "img"
TEMP_DIR = "temp"
DB_FILE  = "members.db"

ESP32_IP          = "192.168.1.200"  # default — bị ghi đè bởi esp32_config.json nếu có
ESP32_CAPTURE_PORT = 80              # port riêng cho /capture — không tranh với stream port 81
CONFIG_FILE = "esp32_config.json"

def _load_esp32_config():
    global ESP32_IP, ESP32_CAPTURE_PORT
    try:
        with open(CONFIG_FILE, 'r') as f:
            data = json.load(f)
            ESP32_IP           = data.get('ip', ESP32_IP)
            ESP32_CAPTURE_PORT = data.get('capture_port', ESP32_CAPTURE_PORT)
            print(f"📂 Loaded ESP32 config: {ESP32_IP} capture={ESP32_CAPTURE_PORT}")
    except FileNotFoundError:
        pass

def _save_esp32_config():
    with open(CONFIG_FILE, 'w') as f:
        json.dump({'ip': ESP32_IP, 'capture_port': ESP32_CAPTURE_PORT}, f)

_load_esp32_config()  # đọc config ngay khi import

MQTT_BROKER = "broker.emqx.io"
MQTT_PORT   = 1883

# Bypass proxy hệ thống — requests tới ESP32 trên LAN không qua proxy
_NO_PROXY = {"http": "", "https": ""}

# Recognition tuning
CAPTURE_INTERVAL  = 1.0    # giây giữa mỗi lần lấy frame
NUM_WORKERS       = 1      # 1 worker đủ — AI xử lý ~23ms, capture 1 frame/s
MATCH_THRESHOLD   = 0.78   # cosine similarity tối thiểu
COOLDOWN_SECONDS  = 6.0    # sau nhận diện thành công, dừng capture 6s

# MQTT topics — phải khớp với AppConfig trong Flutter
TOPIC_FACE_RESULT = "home/face_recognition/result"
TOPIC_FACE_ALERT  = "home/face_recognition/alert"
TOPIC_FACE_BOX    = "home/face_recognition/bbox"   # tọa độ box để Flutter vẽ overlay
TOPIC_SYSTEM_LOG  = "home/system/log"

# ============================================================
# ============================================================
# SHARED STATE
# ============================================================
lock             = threading.Lock()
known_templates  = []
known_names      = []
known_info       = {}
mqtt_client      = None
mqtt_connected   = False

# ============================================================
# MQTT
# ============================================================
def _get_lan_ip() -> str:
    """Trả về IP của PC trên cùng subnet với ESP32 (192.168.x.x / 10.x.x.x).
    Ưu tiên IP cùng dải với ESP32_IP, fallback về IP đầu tiên tìm được."""
    import socket, ipaddress
    esp_net = ipaddress.ip_network(ESP32_IP + '/24', strict=False)
    candidates = []
    try:
        # Lấy tất cả IP của máy bằng cách connect UDP (không gửi gói thật)
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            try:
                addr = ipaddress.ip_address(ip)
                if addr.is_loopback or addr.is_link_local:
                    continue
                candidates.append(ip)
                if addr in esp_net:
                    return ip  # cùng subnet → dùng ngay
            except ValueError:
                pass
    except Exception:
        pass
    # Fallback: connect tới MQTT broker để OS chọn đúng interface
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(('8.8.8.8', 80))
            return s.getsockname()[0]
    except Exception:
        pass
    return candidates[0] if candidates else '127.0.0.1'


def on_connect(client, userdata, flags, rc, props=None):
    global mqtt_connected
    if rc == 0:
        mqtt_connected = True
        print("✅ MQTT connected")
        try:
            my_ip = _get_lan_ip()
            client.publish('home/server/ip', json.dumps({'ip': my_ip, 'port': 5000}), qos=1, retain=True)
            print(f"📡 Published server IP: {my_ip}:5000 → Flutter tự cấu hình")
        except Exception as e:
            print(f"⚠️ Cannot get local IP: {e}")
    else:
        mqtt_connected = False
        print(f"❌ MQTT connect failed: {rc}")

def on_disconnect(client, userdata, flags, rc, props=None):
    global mqtt_connected
    mqtt_connected = False
    print(f"⚠️ MQTT disconnected: {rc}")

def init_mqtt():
    global mqtt_client
    try:
        mqtt_client = mqtt.Client(
            client_id=f"ai_server_{int(time.time())}",
            callback_api_version=mqtt.CallbackAPIVersion.VERSION2
        )
        mqtt_client.on_connect    = on_connect
        mqtt_client.on_disconnect = on_disconnect
        mqtt_client.reconnect_delay_set(min_delay=2, max_delay=60)
        mqtt_client.connect(MQTT_BROKER, MQTT_PORT, keepalive=60)
        mqtt_client.loop_start()
        time.sleep(1)
    except Exception as e:
        print(f"❌ MQTT init error: {e}")
        mqtt_client = None

def publish(topic, payload):
    if mqtt_client and mqtt_connected:
        try:
            mqtt_client.publish(topic, json.dumps(payload), qos=1)
            print(f"📤 MQTT [{topic}]: {payload}")
            return True
        except Exception as e:
            print(f"❌ MQTT publish error: {e}")
    return False

# ============================================================
# CAMERA — gọi /capture trên ESP32 (JPEG tĩnh, độc lập với /stream Flutter)
# ESP32 xử lý /stream và /capture trên 2 handler riêng không block nhau
# ============================================================
def capture_frame():
    """Lấy JPEG từ /capture ESP32 port 80. Chỉ thử 1 lần — không retry flood ESP32."""
    url = f"http://{ESP32_IP}:{ESP32_CAPTURE_PORT}/capture"
    try:
        r = requests.get(url, timeout=5, proxies=_NO_PROXY)
        if r.status_code == 200 and r.content:
            arr = np.frombuffer(r.content, np.uint8)
            frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
            if frame is not None:
                return frame
    except Exception as e:
        print(f"⚠️ capture timeout — skip frame")
    return None

# ============================================================
# IMAGE PROCESSING
# ============================================================
mp_face = mp.solutions.face_detection

def detect_faces(frame):
    faces = []
    with mp_face.FaceDetection(model_selection=1, min_detection_confidence=0.5) as fd:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        res = fd.process(rgb)
        if res.detections:
            h, w = frame.shape[:2]
            for det in res.detections:
                b = det.location_data.relative_bounding_box
                x, y = int(b.xmin * w), int(b.ymin * h)
                fw, fh = int(b.width * w), int(b.height * h)
                mx, my = int(fw * 0.2), int(fh * 0.2)
                x, y = max(0, x - mx), max(0, y - my)
                fw, fh = min(w - x, fw + 2*mx), min(h - y, fh + 2*my)
                if fw >= 40 and fh >= 40:
                    faces.append({'bbox': (x, y, fw, fh), 'score': float(det.score[0])})
    if not faces:
        cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        gray = cv2.equalizeHist(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
        for (x, y, w, h) in cascade.detectMultiScale(gray, 1.05, 3, minSize=(30, 30)):
            faces.append({'bbox': (x, y, w, h), 'score': 0.7})
    return faces

def enhance(image):
    # CLAHE trên LAB để tăng sáng thích nghi — hiệu quả với ảnh tối từ ESP32
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    # Kiểm tra độ sáng trung bình — nếu tối thì tăng mạnh hơn
    mean_l = float(np.mean(l))
    clip = 4.0 if mean_l < 80 else 2.5
    l = cv2.createCLAHE(clipLimit=clip, tileGridSize=(4, 4)).apply(l)
    bgr = cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)
    # Nếu quá tối thì boost thêm brightness/contrast qua PIL
    if mean_l < 80:
        pil = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        pil = ImageEnhance.Brightness(pil).enhance(1.5)
        pil = ImageEnhance.Contrast(pil).enhance(1.4)
        bgr = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
    return bgr

def extract_template(frame, bbox):
    x, y, w, h = bbox
    crop = frame[y:y+h, x:x+w]
    if crop.size == 0:
        return None
    # Resize cố định 64x64, enhance, flatten thành vector
    resized = cv2.resize(crop, (64, 64))
    enh = enhance(resized)
    gray = cv2.equalizeHist(cv2.cvtColor(enh, cv2.COLOR_BGR2GRAY))
    vec = gray.flatten().astype(np.float32)
    norm = np.linalg.norm(vec)
    return vec / norm if norm > 0 else vec

def compare_templates(t1, t2):
    if t1 is None or t2 is None:
        return 0.0
    # Cosine similarity — cùng shape vì cùng flatten từ 64x64
    score = float(np.dot(t1, t2))
    return max(0.0, min(1.0, score))

# ============================================================
# RECOGNITION PIPELINE
# ============================================================

detector = mp.solutions.face_detection.FaceDetection(
    model_selection=1, min_detection_confidence=0.5
)

def _drain_capture(duration: float):
    """Trong thời gian cooldown vẫn gọi /capture mỗi 1s để ESP32 không tắc buffer."""
    end = time.time() + duration
    while time.time() < end:
        try:
            requests.get(
                f"http://{ESP32_IP}:{ESP32_CAPTURE_PORT}/capture",
                timeout=2, proxies=_NO_PROXY
            )
        except Exception:
            pass
        time.sleep(CAPTURE_INTERVAL)

def _capturer():
    """Single-loop pipeline:
    - Lấy 1 frame mỗi CAPTURE_INTERVAL giây
    - Detect + match ngay trong loop
    - Sau khi nhận diện thành công (matched hoặc stranger) → sleep COOLDOWN_SECONDS
      tránh nhận diện lại cùng 1 khuôn mặt nhiều lần liên tiếp
    """
    print(f"📸 Capturer started — interval={CAPTURE_INTERVAL}s, cooldown={COOLDOWN_SECONDS}s")

    while True:
        t0 = time.time()
        frame = capture_frame()
        if frame is None:
            # ESP32 bận — thử lại sau 0.5s, không sleep 1s full
            time.sleep(0.5)
            continue

        ts = int(time.time() * 1000)

        # ── Detect ──────────────────────────────────────────
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        res = detector.process(rgb)
        fh, fw = frame.shape[:2]
        faces = []
        if res.detections:
            for det in res.detections:
                b = det.location_data.relative_bounding_box
                x, y = int(b.xmin * fw), int(b.ymin * fh)
                w, h = int(b.width * fw), int(b.height * fh)
                mx, my = int(w * 0.2), int(h * 0.2)
                x, y = max(0, x - mx), max(0, y - my)
                w, h = min(fw - x, w + 2*mx), min(fh - y, h + 2*my)
                if w >= 40 and h >= 40:
                    faces.append({'bbox': (x, y, w, h), 'score': float(det.score[0])})
        if not faces:
            cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
            gray = cv2.equalizeHist(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY))
            for (x, y, w, h) in cascade.detectMultiScale(gray, 1.05, 3, minSize=(30, 30)):
                faces.append({'bbox': (x, y, int(w), int(h)), 'score': 0.7})

        if not faces:
            publish(TOPIC_FACE_BOX, {'clear': True, 'ts': ts})
            print("🚫 No face")
            elapsed = time.time() - t0
            time.sleep(max(0.0, CAPTURE_INTERVAL - elapsed))
            continue

        best = max(faces, key=lambda f: f['score'])
        x, y, w, h = best['bbox']
        print(f"👤 face score={best['score']:.2f}")

        publish(TOPIC_FACE_BOX, {
            'x': round(x / fw, 4), 'y': round(y / fh, 4),
            'w': round(w / fw, 4), 'h': round(h / fh, 4),
            'ts': ts,
        })

        # ── Match ────────────────────────────────────────────
        templ = extract_template(frame, best['bbox'])
        if templ is None:
            elapsed = time.time() - t0
            time.sleep(max(0.0, CAPTURE_INTERVAL - elapsed))
            continue

        with lock:
            lt, ln, li = list(known_templates), list(known_names), dict(known_info)

        if not lt:
            elapsed = time.time() - t0
            time.sleep(max(0.0, CAPTURE_INTERVAL - elapsed))
            continue

        best_score, best_name = 0.0, None
        scores_debug = []
        for i, kt in enumerate(lt):
            score = compare_templates(templ, kt)
            scores_debug.append(f"{ln[i]}={score:.3f}")
            if score > MATCH_THRESHOLD and score > best_score:
                best_score, best_name = score, ln[i]
        print(f"🔍 scores: {', '.join(scores_debug)} | threshold={MATCH_THRESHOLD}")

        now = time.time()
        ts2 = int(now * 1000)
        if best_name:
            info = li.get(best_name, {})
            print(f"✅ {best_name} ({best_score*100:.0f}%) — cooldown {COOLDOWN_SECONDS}s")
            publish(TOPIC_FACE_RESULT, {
                'matched': True, 'name': best_name,
                'id': info.get('id', ''), 'role': info.get('role', ''),
                'confidence': round(best_score, 3), 'ts': ts2,
            })
            # Cooldown — vẫn capture để drain ESP32 buffer, không xử lý AI
            _drain_capture(COOLDOWN_SECONDS)
        else:
            print(f"⚠️ Stranger ({best_score*100:.0f}%) — cooldown {COOLDOWN_SECONDS}s")
            publish(TOPIC_FACE_ALERT, {
                'matched': False, 'name': 'Người lạ',
                'confidence': round(best_score, 3), 'ts': ts2,
            })
            _drain_capture(COOLDOWN_SECONDS)
            continue

        # Sau cooldown không cần sleep thêm — tiếp tục loop ngay


def _start_recognition_worker():
    """Khởi động capturer trong daemon thread, watchdog tự restart nếu crash."""
    def _watchdog():
        while True:
            try:
                _capturer()
            except Exception as e:
                print(f"💀 Capturer crashed: {e} — restarting in 3s")
                time.sleep(3)
    threading.Thread(target=_watchdog, daemon=True).start()

# ============================================================
# DATABASE
# ============================================================
def get_db():
    conn = sqlite3.connect(DB_FILE)
    conn.row_factory = sqlite3.Row
    return conn

def init_db():
    conn = get_db()
    conn.execute('''
        CREATE TABLE IF NOT EXISTS members (
            id TEXT PRIMARY KEY, name TEXT NOT NULL,
            role TEXT DEFAULT "Thành viên",
            avatar TEXT, pose1 TEXT, pose2 TEXT, pose3 TEXT,
            enrolled_at TEXT
        )
    ''')
    conn.commit(); conn.close()

def load_known_faces():
    global known_templates, known_names, known_info
    nt, nn, ni = [], [], {}
    conn = get_db()
    for row in conn.execute("SELECT * FROM members").fetchall():
        for p in ['pose1', 'pose2', 'pose3']:
            path = row[p]
            if path and os.path.exists(path):
                bgr = cv2.imread(path)
                if bgr is not None:
                    faces = detect_faces(bgr)
                    if faces:
                        best = max(faces, key=lambda f: f['score'])
                        t = extract_template(bgr, best['bbox'])
                        if t is not None:
                            nt.append(t); nn.append(row['name'])
                            ni[row['name']] = {'id': row['id'], 'role': row['role']}
    conn.close()
    with lock:
        known_templates, known_names, known_info = nt, nn, ni
    print(f"📚 Loaded {len(nt)} face templates from {len(set(nn))} members")

# ============================================================
# REST API — chỉ dành cho Flutter enroll/delete/sync
# Recognition KHÔNG còn qua API nữa
# ============================================================
@app.route('/members', methods=['GET'])
def get_members():
    conn = get_db()
    rows = conn.execute("SELECT id, name, role, avatar, enrolled_at FROM members").fetchall()
    conn.close()
    return jsonify({'members': [dict(r) for r in rows]}), 200

@app.route('/enroll', methods=['POST'])
def enroll():
    data = request.json
    name    = data['name'].strip()
    m_id    = str(data.get('id', ''))
    role    = data.get('role', 'Thành viên')
    avatar  = data.get('avatar', '')
    pose    = int(data.get('pose', 1))
    img_data = base64.b64decode(data['image_base64'])
    bgr = cv2.imdecode(np.frombuffer(img_data, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None or not detect_faces(bgr):
        return jsonify({'error': 'No face found in image'}), 400
    os.makedirs(IMG_DIR, exist_ok=True)
    path = os.path.join(IMG_DIR, f"{m_id}_pose{pose}.jpg")
    cv2.imwrite(path, bgr)
    conn = get_db()
    if conn.execute("SELECT id FROM members WHERE id=?", (m_id,)).fetchone():
        conn.execute(f"UPDATE members SET name=?,role=?,avatar=?,pose{pose}=? WHERE id=?",
                     (name, role, avatar, path, m_id))
    else:
        conn.execute(f"INSERT INTO members (id,name,role,avatar,pose{pose},enrolled_at) VALUES (?,?,?,?,?,?)",
                     (m_id, name, role, avatar, path, datetime.now().isoformat()))
    conn.commit(); conn.close()
    load_known_faces()
    return jsonify({'message': 'Enrolled', 'pose': pose}), 200

@app.route('/delete', methods=['POST'])
def delete_member():
    data = request.json
    u_id = data.get('id', '').strip()
    conn = get_db()
    row = conn.execute("SELECT * FROM members WHERE id=?", (u_id,)).fetchone()
    if not row:
        conn.close(); return jsonify({'error': 'Not found'}), 404
    for p in ['pose1', 'pose2', 'pose3']:
        if row[p] and os.path.exists(row[p]): os.remove(row[p])
    conn.execute("DELETE FROM members WHERE id=?", (u_id,))
    conn.commit(); conn.close()
    load_known_faces()
    return jsonify({'message': 'Deleted'}), 200

@app.route('/config', methods=['POST', 'GET'])
def set_config():
    """Flutter gọi sau BLE provisioning để cập nhật IP ESP32"""
    global ESP32_IP, ESP32_CAPTURE_PORT
    if request.method == 'POST' and request.is_json:
        data = request.json
    else:
        data = request.args

    changed = False
    if 'ip' in data and data['ip']:
        ESP32_IP = data['ip']
        changed = True
    if 'capture_port' in data:
        ESP32_CAPTURE_PORT = int(data['capture_port'])
        changed = True

    if changed:
        print(f"📡 ESP32 config updated: {ESP32_IP} capture={ESP32_CAPTURE_PORT}")
        _save_esp32_config()

    return jsonify({'ip': ESP32_IP, 'capture_port': ESP32_CAPTURE_PORT}), 200

@app.route('/status', methods=['GET'])
def status():
    with lock:
        count = len(known_templates)
    return jsonify({
        'status': 'running',
        'esp32': f"{ESP32_IP}:{ESP32_CAPTURE_PORT}",
        'templates': count,
        'mqtt': mqtt_connected,
        'workers': 1,
    }), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200

# ============================================================
# mDNS BROADCAST — Flutter tự tìm server, không cần nhập IP
# ============================================================
def start_mdns(port=5000):
    """Broadcast service _smarthome._tcp trên LAN để Flutter tự discover."""
    try:
        import socket as _sock
        from zeroconf import Zeroconf, ServiceInfo
        zc = Zeroconf()
        local_ip = _get_lan_ip()
        info = ServiceInfo(
            "_smarthome._tcp.local.",
            "SmartHome AI Server._smarthome._tcp.local.",
            addresses=[_sock.inet_aton(local_ip)],
            port=port,
            properties={'version': '1.0', 'esp32': ESP32_IP},
        )
        zc.register_service(info)
        print(f"📡 mDNS broadcast: smarthome.local → {local_ip}:{port}")
        print(f"   Flutter sẽ tự tìm thấy server — không cần nhập IP thủ công")
        return zc, info
    except ImportError:
        print("⚠️ zeroconf chưa cài — chạy: pip install zeroconf")
        print("   Flutter cần nhập IP thủ công trong Devices → Cấu hình AI Server")
        return None, None
    except Exception as e:
        print(f"⚠️ mDNS error: {e}")
        return None, None

# ============================================================
# MAIN
# ============================================================
if __name__ == '__main__':
    os.makedirs(IMG_DIR, exist_ok=True)
    os.makedirs(TEMP_DIR, exist_ok=True)
    init_db()
    load_known_faces()
    init_mqtt()

    # Recognition pipeline
    _start_recognition_worker()

    # mDNS: Flutter tự tìm thấy server trên LAN, không cần nhập IP
    zc, mdns_info = start_mdns(port=5000)

    print(f"🚀 AI Server: http://0.0.0.0:5000")
    print(f"📹 ESP32 stream (Flutter): http://{ESP32_IP}:81/stream")
    print(f"📸 ESP32 capture (AI):     http://{ESP32_IP}:{ESP32_CAPTURE_PORT}/capture")
    print(f"📡 MQTT: {MQTT_BROKER}:{MQTT_PORT}")

    # Chạy Flask trên thread riêng — không block stdout
    def _run_server():
        try:
            from waitress import serve
            serve(app, host='0.0.0.0', port=5000, threads=8)
        except ImportError:
            app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)

    threading.Thread(target=_run_server, daemon=True).start()
    print("🚀 Running with waitress on :5000")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("⛔ Shutting down...")
    finally:
        if zc and mdns_info:
            zc.unregister_service(mdns_info)
            zc.close()
