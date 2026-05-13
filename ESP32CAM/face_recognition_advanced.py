
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
RECOGNITION_INTERVAL = 1.0    # giây giữa mỗi lần lấy frame
MATCH_THRESHOLD      = 0.55   # cosine similarity tối thiểu — đủ cao để tránh nhầm
COOLDOWN_SECONDS     = 8.0    # không nhận diện lại trong n giây sau khi đã nhận

# MQTT topics — phải khớp với AppConfig trong Flutter
TOPIC_FACE_RESULT = "home/face_recognition/result"
TOPIC_FACE_ALERT  = "home/face_recognition/alert"
TOPIC_FACE_BOX    = "home/face_recognition/bbox"   # tọa độ box để Flutter vẽ overlay
TOPIC_SYSTEM_LOG  = "home/system/log"

# ============================================================
# ============================================================
# SHARED STATE
# ============================================================
lock              = threading.Lock()
known_templates   = []
known_names       = []
known_info        = {}
previous_frame    = None
mqtt_client       = None
mqtt_connected    = False

# recognition state machine
rec_state = {
    'phase': 'idle',          # idle | face_detected | stabilizing | recognizing | cooldown
    'stable_start': None,
    'last_result_time': None,
}

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
    """Lấy JPEG từ /capture ESP32 port 80 (server riêng, không tranh với stream port 81)."""
    url = f"http://{ESP32_IP}:{ESP32_CAPTURE_PORT}/capture"
    for attempt in range(3):
        try:
            r = requests.get(url, timeout=4, proxies=_NO_PROXY)
            if r.status_code == 200 and r.content:
                arr = np.frombuffer(r.content, np.uint8)
                frame = cv2.imdecode(arr, cv2.IMREAD_COLOR)
                if frame is not None:
                    return frame
        except Exception as e:
            print(f"⚠️ capture_frame attempt {attempt+1}/3: {e}")
            time.sleep(0.5)
    return None

# ============================================================
# IMAGE PROCESSING
# ============================================================
mp_face = mp.solutions.face_detection

def detect_motion(frame):
    global previous_frame
    gray = cv2.GaussianBlur(cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY), (5, 5), 0)
    gray = cv2.resize(gray, (160, 120))
    if previous_frame is None:
        previous_frame = gray
        return False
    diff = cv2.absdiff(previous_frame, gray)
    _, thresh = cv2.threshold(diff, 25, 255, cv2.THRESH_BINARY)
    previous_frame = gray
    return cv2.countNonZero(thresh) > 500

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

def match_frame(frame):
    """So khớp 1 frame với database. Trả về dict kết quả."""
    faces = detect_faces(frame)
    if not faces:
        return None

    best_face = max(faces, key=lambda f: f['score'])
    templ = extract_template(frame, best_face['bbox'])
    if templ is None:
        return None

    with lock:
        lt, ln, li = list(known_templates), list(known_names), dict(known_info)

    if not lt:
        return {'matched': False, 'name': 'Người lạ', 'confidence': 0.0}

    best_score, best_name = 0.0, None
    for i, kt in enumerate(lt):
        score = compare_templates(templ, kt)
        if score > MATCH_THRESHOLD and score > best_score:
            best_score, best_name = score, ln[i]

    if best_name:
        info = li.get(best_name, {})
        return {
            'matched': True,
            'name': best_name,
            'id': info.get('id', ''),
            'role': info.get('role', ''),
            'confidence': round(best_score, 3),
            'ts': int(time.time() * 1000),
        }
    return {'matched': False, 'name': 'Người lạ', 'confidence': round(best_score, 3), 'ts': int(time.time() * 1000)}

# ============================================================
# BACKGROUND RECOGNITION WORKER
# - Lấy frame mỗi RECOGNITION_INTERVAL giây
# - Detect + match chạy trên thread pool — không block vòng lặp chính
# - Drop frame nếu thread pool đang bận (tránh queue chất đống)
# - Watchdog tự restart nếu worker chết
# ============================================================
_processing = threading.Event()   # True = đang xử lý frame, drop frame mới

def _process_frame(frame, last_result_time_ref):
    """Chạy trong ThreadPoolExecutor — detect + match + publish."""
    try:
        faces = detect_faces(frame)
        ts = int(time.time() * 1000)

        if not faces:
            print("🚫 No face")
            publish(TOPIC_FACE_BOX, {'clear': True, 'ts': ts})
            return

        best = max(faces, key=lambda f: f['score'])
        x, y, w, h = best['bbox']
        fh, fw = frame.shape[:2]
        publish(TOPIC_FACE_BOX, {
            'x': round(x / fw, 4), 'y': round(y / fh, 4),
            'w': round(w / fw, 4), 'h': round(h / fh, 4),
            'ts': ts,
        })
        print(f"👤 Face score={best['score']:.2f}")

        # Cooldown check — bên trong thread để không waste detect
        if time.time() - last_result_time_ref[0] < COOLDOWN_SECONDS:
            return

        result = match_frame(frame)
        if result is None:
            return

        print(f"  → {'✅ '+result['name'] if result['matched'] else '⚠️ Lạ'} ({result['confidence']*100:.0f}%)")
        last_result_time_ref[0] = time.time()
        ts2 = int(time.time() * 1000)

        if result['matched']:
            publish(TOPIC_FACE_RESULT, {
                'matched': True, 'name': result['name'],
                'id': result.get('id', ''), 'role': result.get('role', ''),
                'confidence': result['confidence'], 'ts': ts2,
            })
        else:
            publish(TOPIC_FACE_ALERT, {
                'matched': False, 'name': 'Người lạ',
                'confidence': result['confidence'], 'ts': ts2,
            })
    finally:
        _processing.clear()

def recognition_worker():
    from concurrent.futures import ThreadPoolExecutor
    print("🤖 Recognition worker started")
    publish(TOPIC_SYSTEM_LOG, {'event': 'ai_server_start', 'ts': int(time.time() * 1000)})

    last_result_time_ref = [0.0]  # list để truyền by-reference vào thread

    with ThreadPoolExecutor(max_workers=1) as pool:
        while True:
            time.sleep(RECOGNITION_INTERVAL)

            # Drop frame nếu thread pool đang bận — tránh queue chồng chất
            if _processing.is_set():
                print("⏭ Drop frame — still processing previous")
                continue

            frame = capture_frame()
            if frame is None:
                print(f"❌ Capture failed — {ESP32_IP}:{ESP32_CAPTURE_PORT}")
                continue

            print(f"📷 Frame {frame.shape}")
            _processing.set()
            pool.submit(_process_frame, frame, last_result_time_ref)

def _start_recognition_worker():
    """Khởi động worker trong daemon thread, tự restart nếu crash."""
    def _watchdog():
        while True:
            try:
                recognition_worker()
            except Exception as e:
                print(f"💀 Recognition worker crashed: {e} — restarting in 3s")
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
        'recognition_phase': rec_state['phase'],
    }), 200

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'ok'}), 200

# ============================================================
# MJPEG RELAY ENDPOINT
# Flutter kết nối vào đây — relay phân phối lại cho nhiều client
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

    # Recognition: gọi /capture để nhận diện, độc lập với stream
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
