"""
Benchmark từng bước AI pipeline — chạy: python benchmark_ai.py
Kết quả cho biết chính xác thời gian xử lý 1 frame trên máy này.
"""
import sys, io
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace', line_buffering=True)

import cv2, numpy as np, time, requests, mediapipe as mp
from PIL import Image, ImageEnhance

ESP32_IP           = "192.168.1.200"
ESP32_CAPTURE_PORT = 80
BENCH_FRAMES       = 5   # số frame đo để lấy trung bình
_NO_PROXY          = {"http": "", "https": ""}

# ── Helpers ──────────────────────────────────────────────────────────────────
def ts(): return time.perf_counter()

def fmt(ms): return f"{ms:6.1f}ms"

def capture_frame():
    url = f"http://{ESP32_IP}:{ESP32_CAPTURE_PORT}/capture"
    r = requests.get(url, timeout=5, proxies=_NO_PROXY)
    arr = np.frombuffer(r.content, np.uint8)
    return cv2.imdecode(arr, cv2.IMREAD_COLOR)

def enhance(image):
    lab = cv2.cvtColor(image, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    mean_l = float(np.mean(l))
    clip = 4.0 if mean_l < 80 else 2.5
    l = cv2.createCLAHE(clipLimit=clip, tileGridSize=(4, 4)).apply(l)
    bgr = cv2.cvtColor(cv2.merge([l, a, b]), cv2.COLOR_LAB2BGR)
    if mean_l < 80:
        pil = Image.fromarray(cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB))
        pil = ImageEnhance.Brightness(pil).enhance(1.5)
        pil = ImageEnhance.Contrast(pil).enhance(1.4)
        bgr = cv2.cvtColor(np.array(pil), cv2.COLOR_RGB2BGR)
    return bgr

def extract_template(frame, bbox):
    x, y, w, h = bbox
    crop = frame[y:y+h, x:x+w]
    if crop.size == 0: return None
    resized = cv2.resize(crop, (64, 64))
    enh = enhance(resized)
    gray = cv2.equalizeHist(cv2.cvtColor(enh, cv2.COLOR_BGR2GRAY))
    vec = gray.flatten().astype(np.float32)
    norm = np.linalg.norm(vec)
    return vec / norm if norm > 0 else vec

# ── Benchmark ─────────────────────────────────────────────────────────────────
print("=" * 55)
print("  AI PIPELINE BENCHMARK")
print("=" * 55)

# 1. Capture
print(f"\n[1] Capture frame từ ESP32 ({BENCH_FRAMES} lần)...")
capture_times = []
frame = None
for i in range(BENCH_FRAMES):
    try:
        t0 = ts()
        frame = capture_frame()
        capture_times.append((ts() - t0) * 1000)
        print(f"    #{i+1}: {fmt(capture_times[-1])}  size={frame.shape}")
    except Exception as e:
        print(f"    #{i+1}: FAILED — {e}")

if not capture_times:
    print("\n❌ Không lấy được frame — kiểm tra ESP32 IP")
    sys.exit(1)

avg_capture = sum(capture_times) / len(capture_times)

# 2. MediaPipe detect — khởi tạo MỖI LẦN (cách cũ)
print(f"\n[2] MediaPipe detect — init mỗi lần (cách CŨ)...")
detect_old_times = []
for i in range(BENCH_FRAMES):
    t0 = ts()
    with mp.solutions.face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5) as fd:
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        res = fd.process(rgb)
    detect_old_times.append((ts() - t0) * 1000)
    found = len(res.detections) if res.detections else 0
    print(f"    #{i+1}: {fmt(detect_old_times[-1])}  faces={found}")
avg_detect_old = sum(detect_old_times) / len(detect_old_times)

# 3. MediaPipe detect — instance cố định (cách MỚI)
print(f"\n[3] MediaPipe detect — instance cố định (cách MỚI)...")
detector = mp.solutions.face_detection.FaceDetection(model_selection=1, min_detection_confidence=0.5)
detect_new_times = []
bbox = None
for i in range(BENCH_FRAMES):
    t0 = ts()
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    res = detector.process(rgb)
    detect_new_times.append((ts() - t0) * 1000)
    found = 0
    if res.detections:
        found = len(res.detections)
        det = res.detections[0]
        b = det.location_data.relative_bounding_box
        h, w = frame.shape[:2]
        x, y = int(b.xmin * w), int(b.ymin * h)
        fw, fh = int(b.width * w), int(b.height * h)
        bbox = (max(0,x), max(0,y), min(w-x,fw), min(h-y,fh))
    print(f"    #{i+1}: {fmt(detect_new_times[-1])}  faces={found}")
avg_detect_new = sum(detect_new_times) / len(detect_new_times)
detector.close()

# 4. enhance + extract_template
print(f"\n[4] enhance + extract_template...")
extract_times = []
templ = None
if bbox:
    for i in range(BENCH_FRAMES):
        t0 = ts()
        templ = extract_template(frame, bbox)
        extract_times.append((ts() - t0) * 1000)
        print(f"    #{i+1}: {fmt(extract_times[-1])}")
    avg_extract = sum(extract_times) / len(extract_times)
else:
    print("    ⚠️  Không có mặt trong frame — bỏ qua bước này")
    avg_extract = 0

# 5. cosine similarity (giả lập 3 template trong DB)
print(f"\n[5] Cosine similarity (3 templates trong DB)...")
dummy_templates = [np.random.rand(64*64).astype(np.float32) for _ in range(3)]
for t in dummy_templates:
    t /= np.linalg.norm(t)

match_times = []
if templ is not None:
    for i in range(BENCH_FRAMES):
        t0 = ts()
        for kt in dummy_templates:
            float(np.dot(templ, kt))
        match_times.append((ts() - t0) * 1000)
        print(f"    #{i+1}: {fmt(match_times[-1])}")
    avg_match = sum(match_times) / len(match_times)
else:
    avg_match = 0

# ── Summary ───────────────────────────────────────────────────────────────────
print("\n" + "=" * 55)
print("  KẾT QUẢ BENCHMARK (trung bình)")
print("=" * 55)
print(f"  Capture frame từ ESP32   : {fmt(avg_capture)}")
print(f"  MediaPipe detect (cũ)    : {fmt(avg_detect_old)}  ← init mỗi lần")
print(f"  MediaPipe detect (mới)   : {fmt(avg_detect_new)}  ← instance cố định")
print(f"  enhance + extract_templ  : {fmt(avg_extract)}")
print(f"  cosine match (3 template): {fmt(avg_match)}")
print("-" * 55)

total_old = avg_capture + avg_detect_old + avg_extract + avg_match
total_new = avg_capture + avg_detect_new + avg_extract + avg_match
print(f"  TỔNG (cách cũ)           : {fmt(total_old)}")
print(f"  TỔNG (cách mới/worker)   : {fmt(total_new)}")
print(f"\n  → Với 3 worker song song, throughput thực tế:")
print(f"    1 frame xử lý {fmt(total_new)} → 3 worker xử lý được")
print(f"    ~{1000/total_new*3:.1f} frame/s  (bottleneck: capture {fmt(avg_capture)}/frame)")
print("=" * 55)
