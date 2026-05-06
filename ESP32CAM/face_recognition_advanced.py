
import sys
import io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')
sys.stderr = io.TextIOWrapper(sys.stderr.buffer, encoding='utf-8', errors='replace')

import cv2
import numpy as np
import os
import sqlite3
import threading
import queue as _queue_module
import requests
from flask import Flask, jsonify, request
from datetime import datetime
import base64
from PIL import Image, ImageEnhance
import mediapipe as mp
import time
import json
import paho.mqtt.client as mqtt

try:
    from skimage.metrics import structural_similarity as ssim
    HAS_SSIM = True
except ImportError:
    HAS_SSIM = False

app = Flask(__name__)

# ============================================================
# CONFIG
# ============================================================
IMG_DIR  = "img"
TEMP_DIR = "temp"
DB_FILE  = "members.db"

ESP32_IP   = "192.168.1.27"   # default — bị ghi đè bởi esp32_config.json nếu có
ESP32_PORT = 81
CONFIG_FILE = "esp32_config.json"

def _load_esp32_config():
    global ESP32_IP, ESP32_PORT
    try:
        with open(CONFIG_FILE, 'r') as f:
            data = json.load(f)
            ESP32_IP   = data.get('ip', ESP32_IP)
            ESP32_PORT = data.get('port', ESP32_PORT)
            print(f"📂 Loaded ESP32 config: {ESP32_IP}:{ESP32_PORT}")
    except FileNotFoundError:
        pass

def _save_esp32_config():
    with open(CONFIG_FILE, 'w') as f:
        json.dump({'ip': ESP32_IP, 'port': ESP32_PORT}, f)

_load_esp32_config()  # đọc config ngay khi import

MQTT_BROKER = "broker.hivemq.com"
MQTT_PORT   = 1883

# Recognition tuning
RECOGNITION_INTERVAL = 3.0    # giây giữa mỗi lần check
STABLE_SECONDS       = 2.0    # giây mặt phải giữ yên trước khi nhận diện
MATCH_THRESHOLD      = 0.50   # độ tương đồng tối thiểu để coi là khớp
COOLDOWN_SECONDS     = 10.0   # không nhận diện lại trong n giây sau khi đã nhận

# MQTT topics — phải khớp với AppConfig trong Flutter
TOPIC_FACE_RESULT = "home/face_recognition/result"
TOPIC_FACE_ALERT  = "home/face_recognition/alert"
TOPIC_SYSTEM_LOG  = "home/system/log"

# ============================================================
# MJPEG RELAY — kéo 1 luồng từ ESP32, broadcast ra nhiều client
# ESP32 chỉ chịu 1 kết nối stream → relay giải quyết vấn đề này
# ============================================================
relay_frame     = None   # JPEG bytes mới nhất từ ESP32
relay_lock      = threading.Lock()
relay_subscribers = set()
relay_sub_lock  = threading.Lock()
relay_restart_event = threading.Event()
relay_connected = False

def relay_worker():
    """Kéo MJPEG stream từ ESP32, lưu frame mới nhất, notify subscribers."""
    global relay_frame, relay_connected
    print("📹 MJPEG relay worker started")
    retry_delay = 1
    while True:
        url = f"http://{ESP32_IP}:{ESP32_PORT}/stream"
        print(f"📹 Relay connecting: {url}")
        relay_restart_event.clear()
        try:
            r = requests.get(url, stream=True, timeout=5)
            relay_connected = True
            retry_delay = 1
            print(f"✅ Relay connected to ESP32")
            buf = b''
            for chunk in r.iter_content(chunk_size=65536):
                if relay_restart_event.is_set():
                    print("🔄 Relay restarting with new ESP32 IP...")
                    r.close()
                    break
                buf += chunk
                # Chỉ giữ frame mới nhất nếu buffer quá lớn
                if len(buf) > 524288:
                    start = buf.rfind(b'\xff\xd8')
                    buf = buf[start:] if start != -1 else b''
                while True:
                    start = buf.find(b'\xff\xd8')
                    end   = buf.find(b'\xff\xd9')
                    if start == -1 or end == -1 or end < start:
                        break
                    jpg = buf[start:end + 2]
                    buf = buf[end + 2:]
                    with relay_lock:
                        relay_frame = jpg
                    with relay_sub_lock:
                        for ev in relay_subscribers:
                            ev.set()
        except Exception as e:
            relay_connected = False
            print(f"⚠️ Relay error: {e} — retry in {retry_delay}s")
            time.sleep(retry_delay)
            retry_delay = min(retry_delay * 2, 8)
            continue
        time.sleep(0.5)

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
def on_connect(client, userdata, flags, rc, props=None):
    global mqtt_connected
    if rc == 0:
        mqtt_connected = True
        print("✅ MQTT connected")
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
# CAMERA — pull single JPEG from ESP32
# ============================================================
def capture_frame():
    """Lấy frame mới nhất từ relay buffer (không tạo thêm kết nối tới ESP32)."""
    with relay_lock:
        jpg = relay_frame
    if jpg is None:
        return None
    arr = np.frombuffer(jpg, np.uint8)
    return cv2.imdecode(arr, cv2.IMREAD_COLOR)

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
    pil = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    pil = ImageEnhance.Brightness(pil).enhance(1.3)
    pil = ImageEnhance.Contrast(pil).enhance(1.2)
    pil = ImageEnhance.Sharpness(pil).enhance(1.2)
    bgr = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
    lab = cv2.cvtColor(bgr, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    l = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8, 8)).apply(l)
    return cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)

def extract_template(frame, bbox):
    x, y, w, h = bbox
    crop = frame[y:y+h, x:x+w]
    if crop.size == 0:
        return None
    enh = enhance(cv2.resize(crop, (160, 160)))
    gray = cv2.GaussianBlur(cv2.cvtColor(enh, cv2.COLOR_BGR2GRAY), (3, 3), 0)
    return cv2.equalizeHist(gray)

def compare_templates(t1, t2):
    if t1 is None or t2 is None:
        return 0.0
    _, s1, _, _ = cv2.minMaxLoc(cv2.matchTemplate(t1, t2, cv2.TM_CCOEFF_NORMED))
    s2 = ssim(t1, t2) if HAS_SSIM else s1
    h1 = cv2.calcHist([t1], [0], None, [256], [0, 256])
    h2 = cv2.calcHist([t2], [0], None, [256], [0, 256])
    s3 = cv2.compareHist(h1, h2, cv2.HISTCMP_CORREL)
    return max(0.0, min(1.0, s1 * 0.4 + s2 * 0.4 + s3 * 0.2))

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
# Đây là trái tim của Cách B:
# Python server tự pull frame, tự nhận diện, tự publish MQTT
# Flutter không cần làm gì ngoài subscribe MQTT
# ============================================================
def recognition_worker():
    global rec_state
    print("🤖 Recognition worker started")
    publish(TOPIC_SYSTEM_LOG, {'event': 'ai_server_start', 'ts': int(time.time() * 1000)})

    while True:
        time.sleep(RECOGNITION_INTERVAL)

        # Bỏ qua nếu đang trong cooldown
        if rec_state['phase'] == 'cooldown':
            elapsed = time.time() - rec_state['last_result_time']
            if elapsed < COOLDOWN_SECONDS:
                continue
            rec_state['phase'] = 'idle'
            print("🔄 Cooldown over — resuming recognition")

        # Lấy frame từ ESP32
        frame = capture_frame()
        if frame is None:
            rec_state['phase'] = 'idle'
            continue

        # Kiểm tra có chuyển động không
        if not detect_motion(frame):
            if rec_state['phase'] != 'idle':
                print("😴 No motion — idle")
                rec_state['phase'] = 'idle'
                rec_state['stable_start'] = None
            continue

        # Kiểm tra có khuôn mặt không
        faces = detect_faces(frame)
        if not faces:
            rec_state['phase'] = 'idle'
            rec_state['stable_start'] = None
            continue

        now = time.time()

        # Bắt đầu đếm stable
        if rec_state['phase'] == 'idle':
            rec_state['phase'] = 'stabilizing'
            rec_state['stable_start'] = now
            print(f"👤 Face detected — stabilizing for {STABLE_SECONDS}s...")
            continue

        if rec_state['phase'] == 'stabilizing':
            elapsed = now - rec_state['stable_start']
            if elapsed < STABLE_SECONDS:
                print(f"⏳ Stabilizing {elapsed:.1f}/{STABLE_SECONDS}s")
                continue
            rec_state['phase'] = 'recognizing'

        if rec_state['phase'] != 'recognizing':
            continue

        # ── Chụp 3 frame cách nhau 0.5s, vote majority ─────
        print("🔍 Capturing 3 frames for recognition...")
        votes = []
        for shot in range(3):
            f = capture_frame()
            if f is not None:
                r = match_frame(f)
                if r is not None:
                    votes.append(r)
                    print(f"  Shot {shot+1}: {'✅ ' + r['name'] if r['matched'] else '⚠️ Stranger'} ({r['confidence']*100:.0f}%)")
            if shot < 2:
                time.sleep(0.5)

        if not votes:
            rec_state['phase'] = 'idle'
            continue

        # Vote majority: đếm xem tên nào xuất hiện nhiều nhất
        from collections import Counter
        matched_votes = [v for v in votes if v['matched']]
        if len(matched_votes) >= 2:
            name_counts = Counter(v['name'] for v in matched_votes)
            best_name = name_counts.most_common(1)[0][0]
            best_vote = max((v for v in matched_votes if v['name'] == best_name),
                            key=lambda v: v['confidence'])
            result = best_vote
        else:
            # Người lạ: lấy vote có confidence cao nhất
            result = max(votes, key=lambda v: v['confidence'])
            result['matched'] = False
            result['name'] = 'Người lạ'

        rec_state['phase'] = 'cooldown'
        rec_state['last_result_time'] = now

        if result['matched']:
            print(f"✅ Recognized: {result['name']} ({result['confidence']*100:.0f}%)")
            publish(TOPIC_FACE_RESULT, {
                'matched': True,
                'name': result['name'],
                'id': result.get('id', ''),
                'role': result.get('role', ''),
                'confidence': result['confidence'],
                'ts': result.get('ts', int(now * 1000)),
            })
        else:
            print(f"⚠️ Stranger detected (conf={result['confidence']*100:.0f}%)")
            publish(TOPIC_FACE_ALERT, {
                'matched': False,
                'name': 'Người lạ',
                'confidence': result['confidence'],
                'ts': int(now * 1000),
            })

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
    global ESP32_IP, ESP32_PORT
    # Hỗ trợ cả JSON body (POST) và query params (GET) để dễ test trên browser
    if request.method == 'POST' and request.is_json:
        data = request.json
    else:
        data = request.args

    changed = False
    if 'ip' in data and data['ip']:
        ESP32_IP = data['ip']
        changed = True
    if 'port' in data:
        ESP32_PORT = int(data['port'])
        changed = True

    if changed:
        print(f"📡 ESP32 config updated: {ESP32_IP}:{ESP32_PORT} — restarting relay...")
        _save_esp32_config()       # lưu để lần sau không cần nhập lại
        relay_restart_event.set()  # báo relay worker reconnect với IP mới

    return jsonify({'ip': ESP32_IP, 'port': ESP32_PORT}), 200

@app.route('/status', methods=['GET'])
def status():
    with lock:
        count = len(known_templates)
    return jsonify({
        'status': 'running',
        'esp32': f"{ESP32_IP}:{ESP32_PORT}",
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
# ESP32 chỉ có đúng 1 kết nối stream (từ relay_worker)
# ============================================================
RELAY_BOUNDARY = b'--frame'

STREAM_FPS      = 15              # FPS gửi về Flutter
STREAM_INTERVAL = 1.0 / STREAM_FPS

@app.route('/stream')
def stream_relay():
    def generate():
        ev = threading.Event()
        with relay_sub_lock:
            relay_subscribers.add(ev)
        last_sent = 0.0
        try:
            while True:
                ev.wait(timeout=5)
                ev.clear()
                now = time.time()
                if now - last_sent < STREAM_INTERVAL:
                    continue
                last_sent = now
                with relay_lock:
                    jpg = relay_frame
                if jpg is None:
                    continue
                yield (
                    RELAY_BOUNDARY +
                    b'\r\nContent-Type: image/jpeg\r\nContent-Length: ' +
                    str(len(jpg)).encode() +
                    b'\r\n\r\n' + jpg + b'\r\n'
                )
        except GeneratorExit:
            pass
        finally:
            with relay_sub_lock:
                relay_subscribers.discard(ev)

    return app.response_class(
        generate(),
        mimetype='multipart/x-mixed-replace; boundary=frame',
    )

# ============================================================
# mDNS BROADCAST — Flutter tự tìm server, không cần nhập IP
# ============================================================
def start_mdns(port=5000):
    """Broadcast service _smarthome._tcp trên LAN để Flutter tự discover."""
    try:
        from zeroconf import Zeroconf, ServiceInfo
        import socket
        zc = Zeroconf()
        local_ip = socket.gethostbyname(socket.gethostname())
        info = ServiceInfo(
            "_smarthome._tcp.local.",
            "SmartHome AI Server._smarthome._tcp.local.",
            addresses=[socket.inet_aton(local_ip)],
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

    # Relay: kéo 1 kết nối từ ESP32, broadcast ra nhiều client Flutter
    threading.Thread(target=relay_worker, daemon=True).start()

    # Recognition: dùng relay_frame thay vì gọi thêm kết nối tới ESP32
    threading.Thread(target=recognition_worker, daemon=True).start()

    # mDNS: Flutter tự tìm thấy server trên LAN, không cần nhập IP
    zc, mdns_info = start_mdns(port=5000)

    print(f"🚀 AI Server: http://0.0.0.0:5000")
    print(f"📹 MJPEG relay: http://<PC_IP>:5000/stream")
    print(f"🔗 ESP32 source: http://{ESP32_IP}:{ESP32_PORT}/stream")
    print(f"📡 MQTT: {MQTT_BROKER}:{MQTT_PORT}")

    try:
        app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)
    finally:
        if zc and mdns_info:
            zc.unregister_service(mdns_info)
            zc.close()
