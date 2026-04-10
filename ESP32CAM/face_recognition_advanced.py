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

# MediaPipe Face Detection - Chuyên nghiệp cho đeo kính/khẩu trang
mp_face_detection = mp.solutions.face_detection
mp_drawing = mp.solutions.drawing_utils

if not os.path.exists(IMG_DIR):
    os.makedirs(IMG_DIR)
if not os.path.exists(TEMP_DIR):
    os.makedirs(TEMP_DIR)

# Lưu trữ templates và thông tin user
known_face_templates = []
known_face_names = []
known_face_info = {}  # Lưu avatar, role, etc.
lock = threading.Lock()

# Frame Diff - Motion Detection
previous_frame = None
MOTION_THRESHOLD = 25  # Ngưỡng phát hiện chuyển động (pixel diff)
MIN_MOTION_PIXELS = 500  # Số pixel tối thiểu để coi là có chuyển động

def detect_motion_frame_diff(current_frame):
    """Phát hiện chuyển động bằng Frame Diff - tiết kiệm CPU"""
    global previous_frame
    
    # Chuyển sang grayscale và resize nhỏ để tính nhanh
    gray = cv2.cvtColor(current_frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.resize(gray, (160, 120))  # Resize nhỏ để tính nhanh
    gray = cv2.GaussianBlur(gray, (5, 5), 0)  # Giảm noise
    
    # Lần đầu tiên - lưu frame và return False
    if previous_frame is None:
        previous_frame = gray
        return False, 0
    
    # Tính diff giữa 2 frame
    frame_diff = cv2.absdiff(previous_frame, gray)
    
    # Threshold để tìm vùng thay đổi
    _, thresh = cv2.threshold(frame_diff, MOTION_THRESHOLD, 255, cv2.THRESH_BINARY)
    
    # Đếm số pixel thay đổi
    motion_pixels = cv2.countNonZero(thresh)
    
    # Cập nhật previous frame
    previous_frame = gray
    
    # Có chuyển động nếu số pixel thay đổi > ngưỡng
    has_motion = motion_pixels > MIN_MOTION_PIXELS
    
    return has_motion, motion_pixels

# Biến theo dõi trạng thái phát hiện
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
    print("✅ Database sẵn sàng với bảng members nâng cao")

# ============================================================
# AI NÂNG CAO - XỬ LÝ ẢNH CHO ĐEO KÍNH/KHẨU TRANG
# ============================================================

def enhance_small_image_to_hd(image):
    """Nâng cấp ảnh nhỏ từ ESP32-CAM thành HD để nhận diện tốt"""
    height, width = image.shape[:2]
    
    # 1. Upscale ảnh lên 2-3 lần bằng INTER_CUBIC (chất lượng cao)
    if width < 400:  # Nếu ảnh nhỏ hơn 400px
        scale_factor = 400.0 / width
        new_width = int(width * scale_factor)
        new_height = int(height * scale_factor)
        image = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        print(f"   📈 Upscale ảnh từ {width}x{height} → {new_width}x{new_height}")
    
    # 2. Áp dụng enhancement mạnh cho ảnh nhỏ
    pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    
    # Tăng độ sáng mạnh hơn cho ảnh nhỏ
    enhancer = ImageEnhance.Brightness(pil_image)
    pil_image = enhancer.enhance(1.5)  # Tăng 50%
    
    # Tăng contrast mạnh hơn
    enhancer = ImageEnhance.Contrast(pil_image)
    pil_image = enhancer.enhance(1.4)  # Tăng 40%
    
    # Tăng sharpness để bù cho upscale
    enhancer = ImageEnhance.Sharpness(pil_image)
    pil_image = enhancer.enhance(1.3)  # Tăng 30%
    
    enhanced = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
    
    # 3. Áp dụng CLAHE mạnh hơn cho ảnh upscale
    lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=4.0, tileGridSize=(4,4))  # Mạnh hơn cho ảnh nhỏ
    l = clahe.apply(l)
    enhanced = cv2.merge([l, a, b])
    enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
    
    # 4. Noise reduction sau upscale
    enhanced = cv2.bilateralFilter(enhanced, 5, 50, 50)
    
    return enhanced

def detect_faces_advanced_glasses_mask(image):
    """Phát hiện khuôn mặt nâng cao - đặc biệt cho đeo kính/khẩu trang"""
    faces = []
    
    # 1. MediaPipe Face Detection với cấu hình tối ưu
    with mp_face_detection.FaceDetection(
        model_selection=1,  # Long range model - tốt hơn cho kính/khẩu trang
        min_detection_confidence=0.5  # Tăng threshold để tránh false positive
    ) as face_detection:
        
        rgb_image = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
        results = face_detection.process(rgb_image)
        
        if results.detections:
            h, w, _ = image.shape
            for detection in results.detections:
                bbox = detection.location_data.relative_bounding_box
                
                x = int(bbox.xmin * w)
                y = int(bbox.ymin * h)
                width = int(bbox.width * w)
                height = int(bbox.height * h)
                
                # Mở rộng bbox 25% để capture đầy đủ (quan trọng cho kính)
                margin = 0.25
                x_margin = int(width * margin)
                y_margin = int(height * margin)
                
                x = max(0, x - x_margin)
                y = max(0, y - y_margin)
                width = min(w - x, width + 2 * x_margin)
                height = min(h - y, height + 2 * y_margin)
                
                # Lọc bỏ face quá nhỏ (false positive)
                if width >= 50 and height >= 50:
                    faces.append({
                        'bbox': (x, y, width, height),
                        'confidence': float(detection.score[0]),
                        'keypoints': detection.location_data.relative_keypoints if hasattr(detection.location_data, 'relative_keypoints') else None
                    })
                else:
                    print(f"   ⚠️ Bỏ qua face quá nhỏ: {width}x{height}px")
    
    # 2. Fallback với OpenCV nếu MediaPipe không tìm thấy
    if len(faces) == 0:
        print("   🔄 MediaPipe không tìm thấy → Fallback OpenCV...")
        
        # Sử dụng multiple cascades cho độ chính xác cao
        face_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_frontalface_default.xml')
        profile_cascade = cv2.CascadeClassifier(cv2.data.haarcascades + 'haarcascade_profileface.xml')
        
        gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        gray = cv2.equalizeHist(gray)
        
        # Detect với tham số tối ưu cho kính/khẩu trang
        frontal_faces = face_cascade.detectMultiScale(
            gray, scaleFactor=1.03, minNeighbors=2, minSize=(20, 20), maxSize=(400, 400)
        )
        
        profile_faces = profile_cascade.detectMultiScale(
            gray, scaleFactor=1.03, minNeighbors=2, minSize=(20, 20), maxSize=(400, 400)
        )
        
        all_opencv_faces = list(frontal_faces) + list(profile_faces)
        
        for (x, y, w, h) in all_opencv_faces:
            faces.append({
                'bbox': (x, y, w, h),
                'confidence': 0.8,
                'keypoints': None
            })
    
    return faces
def enhance_image_for_glasses_mask(image):
    """Enhancement đặc biệt cho ảnh có kính/khẩu trang"""
    # Chuyển sang PIL để enhancement
    pil_image = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    
    # Tăng độ sáng
    enhancer = ImageEnhance.Brightness(pil_image)
    pil_image = enhancer.enhance(1.3)
    
    # Tăng contrast
    enhancer = ImageEnhance.Contrast(pil_image)
    pil_image = enhancer.enhance(1.2)
    
    # Tăng sharpness
    enhancer = ImageEnhance.Sharpness(pil_image)
    pil_image = enhancer.enhance(1.2)
    
    enhanced = cv2.cvtColor(np.array(pil_image), cv2.COLOR_RGB2BGR)
    
    # CLAHE cho vùng mắt
    lab = cv2.cvtColor(enhanced, cv2.COLOR_BGR2LAB)
    l, a, b = cv2.split(lab)
    clahe = cv2.createCLAHE(clipLimit=3.0, tileGridSize=(8,8))
    l = clahe.apply(l)
    enhanced = cv2.merge([l, a, b])
    enhanced = cv2.cvtColor(enhanced, cv2.COLOR_LAB2BGR)
    
    return enhanced

def extract_face_template_advanced(image, bbox):
    """Trích xuất template khuôn mặt nâng cao cho đeo kính/khẩu trang"""
    x, y, w, h = bbox
    face_crop = image[y:y+h, x:x+w]
    
    if face_crop.size == 0:
        return None
    
    # Resize về kích thước chuẩn lớn hơn để giữ chi tiết
    face_resized = cv2.resize(face_crop, (160, 160))
    
    # Áp dụng enhancement đặc biệt
    face_enhanced = enhance_image_for_glasses_mask(face_resized)
    
    # Chuyển sang grayscale với weighted average tối ưu
    # Trọng số cao hơn cho kênh xanh lá (tốt cho vùng mắt)
    face_gray = cv2.cvtColor(face_enhanced, cv2.COLOR_BGR2GRAY)
    
    # Áp dụng Gaussian blur nhẹ để giảm noise từ kính
    face_gray = cv2.GaussianBlur(face_gray, (3, 3), 0)
    
    # Chuẩn hóa histogram
    face_normalized = cv2.equalizeHist(face_gray)
    
    return face_normalized

def compare_faces_advanced_template(template1, template2):
    """So sánh template nâng cao với nhiều phương pháp"""
    if template1 is None or template2 is None:
        return 0.0
    
    # 1. Template matching cơ bản
    result1 = cv2.matchTemplate(template1, template2, cv2.TM_CCOEFF_NORMED)
    _, score1, _, _ = cv2.minMaxLoc(result1)
    
    # 2. Structural Similarity Index (SSIM) - tốt cho kính (nếu có)
    if HAS_SSIM:
        score2 = ssim(template1, template2)
    else:
        score2 = score1  # Fallback nếu không có SSIM
    
    # 3. Histogram comparison
    hist1 = cv2.calcHist([template1], [0], None, [256], [0, 256])
    hist2 = cv2.calcHist([template2], [0], None, [256], [0, 256])
    score3 = cv2.compareHist(hist1, hist2, cv2.HISTCMP_CORREL)
    
    # Kết hợp 3 điểm số với trọng số
    final_score = (score1 * 0.4) + (score2 * 0.4) + (score3 * 0.2)
    
    return max(0.0, min(1.0, final_score))

def load_known_faces():
    """Load templates và thông tin user từ database"""
    global known_face_templates, known_face_names, known_face_info
    new_templates = []
    new_names = []
    new_info = {}
    
    print("🔍 Đang load khuôn mặt từ database...")
    
    # Load từ database
    conn = get_db()
    rows = conn.execute("SELECT id, name, role, avatar, pose1, pose2, pose3 FROM members").fetchall()
    
    for row in rows:
        user_id = row['id']
        name = row['name']
        role = row['role'] or 'Thành viên'
        avatar = row['avatar']
        
        # Load từng pose
        for pose_num in [1, 2, 3]:
            pose_path = row[f'pose{pose_num}']
            if pose_path and os.path.exists(pose_path):
                try:
                    bgr = cv2.imread(pose_path)
                    if bgr is not None:
                        # Detect face trong ảnh đã lưu
                        faces = detect_faces_advanced_glasses_mask(bgr)
                        if faces:
                            # Lấy face tốt nhất
                            best_face = max(faces, key=lambda f: f['confidence'])
                            template = extract_face_template_advanced(bgr, best_face['bbox'])
                            
                            if template is not None:
                                new_templates.append(template)
                                new_names.append(name)
                                new_info[name] = {
                                    'id': user_id,
                                    'role': role,
                                    'avatar': avatar
                                }
                                print(f"   ✔ {os.path.basename(pose_path)} → [{name}] ({role})")
                                
                except Exception as e:
                    print(f"   ⚠️ Lỗi {pose_path}: {e}")
    
    conn.close()
    
    with lock:
        known_face_templates = new_templates
        known_face_names = new_names
        known_face_info = new_info
    
    unique_users = list(set(new_names))
    print(f"✅ Loaded {len(new_templates)} templates từ {len(unique_users)} users: {unique_users}")
# ============================================================
# API: STREAM LIÊN TỤC VÀ NHẬN DIỆN TỰ ĐỘNG
# ============================================================

@app.route('/recognize', methods=['POST'])
def recognize():
    """API với Motion Detection - chỉ phát hiện face khi có chuyển động"""
    data = request.json
    if not data or 'image_base64' not in data:
        return jsonify({"error": "Thiếu image_base64"}), 400

    try:
        # Decode ảnh
        img_data = base64.b64decode(data['image_base64'])
        nparr = np.frombuffer(img_data, np.uint8)
        bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if bgr is None:
            return jsonify({"face_count": 0, "faces": [], "motion": False}), 200

        # BƯỚC 1: Phát hiện chuyển động bằng Frame Diff
        has_motion, motion_pixels = detect_motion_frame_diff(bgr)
        
        print(f"🎯 Motion: {has_motion} ({motion_pixels} pixels)", end=" ")
        
        if not has_motion:
            # Không có chuyển động → không cần detect face
            print("→ Bỏ qua (không có chuyển động)")
            return jsonify({
                "face_count": 0,
                "faces": [],
                "motion": False,
                "motion_pixels": int(motion_pixels)
            }), 200
        
        # BƯỚC 2: Có chuyển động → Phát hiện khuôn mặt
        detected_faces = detect_faces_advanced_glasses_mask(bgr)
        
        print(f"→ {len(detected_faces)} faces")
        
        # Format kết quả
        faces_result = []
        for face in detected_faces:
            x, y, w, h = face['bbox']
            faces_result.append({
                'box': {
                    'top': int(y),
                    'right': int(x + w),
                    'bottom': int(y + h),
                    'left': int(x)
                },
                'confidence': float(face['confidence'])
            })
        
        return jsonify({
            "face_count": len(detected_faces),
            "faces": faces_result,
            "motion": True,
            "motion_pixels": int(motion_pixels)
        }), 200

    except Exception as e:
        print(f"\n❌ Lỗi /recognize: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e), "face_count": 0, "faces": [], "motion": False}), 500

@app.route('/smart_recognition', methods=['POST'])
def smart_recognition():
    """API nhận diện thông minh - tiết kiệm RAM ESP32-CAM"""
    global face_detection_state
    
    data = request.json
    if not data or 'image_base64' not in data:
        return jsonify({"error": "Thiếu image_base64"}), 400

    try:
        # Decode ảnh
        img_data = base64.b64decode(data['image_base64'])
        nparr = np.frombuffer(img_data, np.uint8)
        bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if bgr is None:
            return jsonify({"status": "no_image", "face_detected": False}), 200

        # Resize ảnh nhỏ hơn để tiết kiệm RAM khi xử lý
        height, width = bgr.shape[:2]
        print(f"   📥 Nhận ảnh từ ESP32-CAM: {width}x{height}")
        
        # Upscale và enhance ảnh nhỏ thành chất lượng cao
        enhanced_image = enhance_small_image_to_hd(bgr)
        
        # Phát hiện khuôn mặt với AI nâng cao trên ảnh đã upscale
        detected_faces = detect_faces_advanced_glasses_mask(enhanced_image)
        
        current_time = time.time()
        
        if len(detected_faces) == 0:
            # Không có face → reset state
            face_detection_state = {
                'face_detected': False,
                'stable_start_time': None,
                'last_detection_time': None,
                'capture_in_progress': False
            }
            return jsonify({
                "status": "no_face",
                "face_detected": False,
                "message": "Đang quét...",
                "instruction": "reduce_frequency"  # Báo cho relay giảm tần suất
            }), 200
        
        # Có face được phát hiện
        face_detection_state['last_detection_time'] = current_time
        
        if not face_detection_state['face_detected']:
            # Face mới được phát hiện
            face_detection_state['face_detected'] = True
            face_detection_state['stable_start_time'] = current_time
            print(f"👁️ Phát hiện {len(detected_faces)} khuôn mặt - Bắt đầu đếm 2 giây...")
            
            return jsonify({
                "status": "face_detected",
                "face_detected": True,
                "message": "Phát hiện khuôn mặt - Đứng yên...",
                "countdown": 2.0,
                "instruction": "increase_frequency"  # Báo cho relay tăng tần suất
            }), 200
        
        # Face đã được phát hiện trước đó
        stable_duration = current_time - face_detection_state['stable_start_time']
        
        if stable_duration < 2.0:
            # Chưa đủ 2 giây - chỉ trả về countdown
            remaining = 2.0 - stable_duration
            return jsonify({
                "status": "stabilizing",
                "face_detected": True,
                "message": f"Giữ yên {remaining:.1f}s nữa...",
                "countdown": remaining,
                "instruction": "maintain_frequency"
            }), 200
        
        # Đã ổn định 2 giây → BẮT ĐẦU CHỤP (chỉ 1 lần)
        if not face_detection_state['capture_in_progress']:
            face_detection_state['capture_in_progress'] = True
            print("📸 Đã đủ 2 giây ổn định - Bắt đầu chụp 4 ảnh...")
            
            return jsonify({
                "status": "ready_to_capture",
                "face_detected": True,
                "message": "Đang chụp ảnh...",
                "instruction": "start_capture"  # Báo cho relay bắt đầu chụp
            }), 200
        
        # Đang trong quá trình capture - không làm gì thêm
        return jsonify({
            "status": "capturing",
            "face_detected": True,
            "message": "Đang xử lý...",
            "instruction": "wait"
        }), 200

    except Exception as e:
        print(f"\n❌ Lỗi /smart_recognition: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e), "face_detected": False}), 500
def compare_with_database(captured_image_paths):
    """So sánh 4 ảnh đã chụp với database"""
    print(f"🔍 Phân tích {len(captured_image_paths)} ảnh...")
    
    captured_templates = []
    
    # Trích xuất templates từ 4 ảnh
    for i, img_path in enumerate(captured_image_paths):
        try:
            bgr = cv2.imread(img_path)
            if bgr is not None:
                enhanced = enhance_image_for_glasses_mask(bgr)
                faces = detect_faces_advanced_glasses_mask(enhanced)
                
                if faces:
                    best_face = max(faces, key=lambda f: f['confidence'])
                    template = extract_face_template_advanced(enhanced, best_face['bbox'])
                    
                    if template is not None:
                        captured_templates.append({
                            'template': template,
                            'confidence': best_face['confidence'],
                            'image_index': i
                        })
        except Exception as e:
            print(f"   ⚠️ Lỗi xử lý ảnh {i}: {e}")
    
    if len(captured_templates) == 0:
        return {
            "status": "no_face_in_capture",
            "message": "Không tìm thấy khuôn mặt trong ảnh đã chụp",
            "matched": False
        }
    
    print(f"💾 Trích xuất được {len(captured_templates)} templates")
    
    # So sánh với database
    with lock:
        local_templates = list(known_face_templates)
        local_names = list(known_face_names)
        local_info = dict(known_face_info)
    
    if len(local_templates) == 0:
        return {
            "status": "no_registered_users",
            "message": "Chưa có thành viên nào đăng ký",
            "matched": False
        }
    
    # Tìm match tốt nhất
    best_match = None
    best_confidence = 0.0
    best_name = None
    
    print(f"🔍 So sánh {len(captured_templates)} templates với {len(local_templates)} templates trong DB...")
    
    for captured in captured_templates:
        template = captured['template']
        
        for i, known_template in enumerate(local_templates):
            score = compare_faces_advanced_template(template, known_template)
            
            # Log điểm số cao nhất
            if score > 0.40:  # Chỉ log nếu > 40%
                print(f"   📊 So sánh với [{local_names[i]}]: {score*100:.1f}%")
            
            # Ngưỡng 0.50 cho template matching (giảm để dễ nhận diện hơn)
            if score > 0.50 and score > best_confidence:
                best_match = i
                best_confidence = score
                best_name = local_names[i]
    
    if best_match is not None and best_name:
        user_info = local_info.get(best_name, {})
        user_id = user_info.get('id', '')
        role = user_info.get('role', 'Thành viên')
        avatar = user_info.get('avatar', '')
        
        print(f"✅ Nhận diện thành công: {best_name} | ID={user_id} | Độ tin cậy: {best_confidence*100:.0f}%")
        
        return {
            "status": "recognized",
            "matched": True,
            "name": best_name,
            "id": user_id,
            "role": role,
            "avatar": avatar,
            "confidence": round(best_confidence, 3),
            "message": f"Xin chào {best_name}!",
            "greeting": f"Xin chào {best_name}! Chào mừng bạn về nhà.",
            "ai_method": "Advanced Template Matching + MediaPipe"
        }
    else:
        print(f"⚠️ Không nhận ra - Độ tin cậy cao nhất: {best_confidence*100:.0f}%")
        return {
            "status": "stranger",
            "matched": False,
            "name": "Người lạ",
            "confidence": round(best_confidence, 3),
            "message": "Phát hiện người lạ tại cửa!",
            "ai_method": "Advanced Template Matching + MediaPipe"
        }

# ============================================================
# API: ĐĂNG KÝ KHUÔN MẶT
# ============================================================

@app.route('/enroll', methods=['POST'])
def enroll():
    data = request.json
    if not data or 'image_base64' not in data or 'name' not in data:
        return jsonify({"error": "Thiếu dữ liệu"}), 400

    name = data['name'].strip()
    member_id = str(data.get('id', '')).strip()
    role = data.get('role', 'Thành viên')
    avatar = data.get('avatar', '')
    pose = int(data.get('pose', 1))

    if not name:
        return jsonify({"error": "Tên không được để trống"}), 400

    try:
        img_data = base64.b64decode(data['image_base64'])
        nparr = np.frombuffer(img_data, np.uint8)
        bgr = cv2.imdecode(nparr, cv2.IMREAD_COLOR)

        if bgr is None:
            return jsonify({"error": "Không decode được ảnh"}), 400

        # Phát hiện face bằng AI nâng cao
        faces = detect_faces_advanced_glasses_mask(bgr)
        
        if len(faces) == 0:
            return jsonify({"error": "⚠️ Không tìm thấy khuôn mặt! Chụp lại gần hơn."}), 400
        
        print(f"   ✓ AI phát hiện {len(faces)} khuôn mặt cho enroll")

        # Lưu ảnh
        filepath = os.path.join(IMG_DIR, f"{name}_pose{pose}.jpg")
        cv2.imwrite(filepath, bgr)
        print(f"💾 Lưu ảnh: {filepath}")

        # Cập nhật database
        conn = get_db()
        existing = conn.execute("SELECT id FROM members WHERE id = ?", (member_id,)).fetchone()

        if existing:
            conn.execute(f"UPDATE members SET name=?, role=?, avatar=?, pose{pose}=? WHERE id=?", 
                        (name, role, avatar, filepath, member_id))
        else:
            row = {
                "id": member_id, "name": name, "role": role, "avatar": avatar,
                "pose1": None, "pose2": None, "pose3": None,
                "enrolled_at": datetime.now().isoformat()
            }
            row[f"pose{pose}"] = filepath
            conn.execute(
                "INSERT INTO members (id, name, role, avatar, pose1, pose2, pose3, enrolled_at) VALUES (?,?,?,?,?,?,?,?)",
                (row["id"], row["name"], row["role"], row["avatar"], 
                 row["pose1"], row["pose2"], row["pose3"], row["enrolled_at"])
            )

        conn.commit()
        conn.close()

        load_known_faces()

        print(f"📥 [{name}] ID={member_id} Role={role} — Đã học góc {pose}/3")
        return jsonify({
            "message": f"✅ Đã học góc {pose}/3 của [{name}]!",
            "id": member_id,
            "name": name,
            "role": role,
            "pose_done": pose
        }), 200

    except Exception as e:
        print(f"\n❌ Lỗi /enroll: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500
# ============================================================
# API: QUẢN LÝ THÀNH VIÊN
# ============================================================

@app.route('/members', methods=['GET'])
def get_members():
    conn = get_db()
    rows = conn.execute("SELECT id, name, role, avatar, pose1, pose2, pose3, enrolled_at FROM members").fetchall()
    conn.close()
    members = [dict(r) for r in rows]
    return jsonify({"members": members, "count": len(members)}), 200

@app.route('/delete', methods=['POST'])
def delete_face():
    data = request.json
    if not data:
        return jsonify({"error": "Thiếu dữ liệu"}), 400
    
    # Hỗ trợ xóa theo name hoặc id
    name = data.get('name', '').strip()
    user_id = data.get('id', '').strip()
    
    if not name and not user_id:
        return jsonify({"error": "Thiếu tên hoặc ID"}), 400

    conn = get_db()
    
    # Tìm theo name hoặc id
    if user_id:
        row = conn.execute("SELECT id, name, pose1, pose2, pose3 FROM members WHERE id = ?", (user_id,)).fetchone()
    else:
        row = conn.execute("SELECT id, name, pose1, pose2, pose3 FROM members WHERE name = ?", (name,)).fetchone()

    if not row:
        conn.close()
        return jsonify({"error": f"Không tìm thấy user"}), 404

    user_name = row['name']
    
    # Xóa file ảnh
    deleted = []
    for key in ['pose1', 'pose2', 'pose3']:
        path = row[key]
        if path and os.path.exists(path):
            try:
                os.remove(path)
                deleted.append(path)
                print(f"🗑️ Đã xóa ảnh: {path}")
            except Exception as e:
                print(f"⚠️ Không xóa được {path}: {e}")

    # Xóa khỏi database
    if user_id:
        conn.execute("DELETE FROM members WHERE id = ?", (user_id,))
    else:
        conn.execute("DELETE FROM members WHERE name = ?", (name,))
    
    conn.commit()
    conn.close()

    # Reload lại templates
    load_known_faces()
    
    print(f"🗑️ Đã xóa [{user_name}] — {len(deleted)} file ảnh")
    return jsonify({"message": f"Đã xóa [{user_name}] ({len(deleted)} ảnh)"}), 200

@app.route('/status', methods=['GET'])
def get_status():
    with lock:
        template_count = len(known_face_templates)
        user_count = len(set(known_face_names))
        users = list(set(known_face_names))
    
    return jsonify({
        "status": "running",
        "templates_loaded": template_count,
        "registered_users": user_count,
        "users": users,
        "ai_features": [
            "MediaPipe Face Detection",
            "Advanced Template Matching",
            "Glasses/Mask Recognition",
            "Continuous Stream Recognition",
            "2-Second Stability Check",
            "Multi-Image Comparison"
        ]
    }), 200

@app.route('/capture_and_recognize', methods=['POST'])
def capture_and_recognize():
    """API chụp 4 ảnh và nhận diện - được gọi từ relay server sau khi face ổn định 2 giây"""
    try:
        print("📸 Bắt đầu chụp 4 ảnh từ ESP32-CAM...")
        
        captured_images = []
        current_time = int(time.time())
        
        # Chụp 4 ảnh từ ESP32-CAM với delay
        for i in range(4):
            try:
                # Gọi ESP32-CAM để chụp ảnh
                ESP32_IP = "192.168.110.38"  # ⚠️ IP ESP32-CAM
                response = requests.get(f'http://{ESP32_IP}:81/capture', timeout=5)
                
                if response.status_code == 200:
                    # Lưu ảnh tạm
                    temp_path = os.path.join(TEMP_DIR, f"capture_{current_time}_{i}.jpg")
                    with open(temp_path, 'wb') as f:
                        f.write(response.content)
                    captured_images.append(temp_path)
                    print(f"   ✓ Chụp ảnh {i+1}/4")
                    
                    # Delay giữa các ảnh
                    if i < 3:  # Không delay sau ảnh cuối
                        time.sleep(0.3)
                else:
                    print(f"   ⚠️ Lỗi chụp ảnh {i+1}: HTTP {response.status_code}")
                    
            except Exception as e:
                print(f"   ❌ Lỗi chụp ảnh {i+1}: {e}")
        
        if len(captured_images) == 0:
            return jsonify({
                "status": "capture_failed",
                "matched": False,
                "message": "Không thể chụp ảnh từ camera"
            }), 500
        
        print(f"💾 Đã chụp {len(captured_images)} ảnh, bắt đầu nhận diện...")
        
        # So sánh với database
        recognition_result = compare_with_database(captured_images)
        
        # Xóa ảnh tạm
        for temp_path in captured_images:
            try:
                os.remove(temp_path)
            except:
                pass
        
        print(f"🗑️ Đã xóa {len(captured_images)} ảnh tạm")
        
        # Reset state
        global face_detection_state
        face_detection_state = {
            'face_detected': False,
            'stable_start_time': None,
            'last_detection_time': None,
            'capture_in_progress': False
        }
        
        return jsonify(recognition_result), 200
        
    except Exception as e:
        print(f"\n❌ Lỗi /capture_and_recognize: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

@app.route('/auto_capture_compare', methods=['POST'])
def auto_capture_compare():
    """API nhận 4 ảnh base64 từ Flutter và so sánh - tương thích ngược"""
    data = request.json
    if not data or 'images_base64' not in data:
        return jsonify({"error": "Thiếu images_base64"}), 400
    
    try:
        images_base64 = data['images_base64']
        print(f"📸 Nhận {len(images_base64)} ảnh base64 từ Flutter...")
        
        captured_images = []
        current_time = int(time.time())
        
        # Decode và lưu ảnh tạm
        for i, img_b64 in enumerate(images_base64):
            try:
                img_data = base64.b64decode(img_b64)
                temp_path = os.path.join(TEMP_DIR, f"flutter_{current_time}_{i}.jpg")
                with open(temp_path, 'wb') as f:
                    f.write(img_data)
                captured_images.append(temp_path)
                print(f"   ✓ Lưu ảnh {i+1}/{len(images_base64)}")
            except Exception as e:
                print(f"   ⚠️ Lỗi decode ảnh {i+1}: {e}")
        
        if len(captured_images) == 0:
            return jsonify({
                "status": "decode_failed",
                "matched": False,
                "message": "Không thể decode ảnh"
            }), 400
        
        print(f"💾 Đã lưu {len(captured_images)} ảnh, bắt đầu nhận diện...")
        
        # So sánh với database
        recognition_result = compare_with_database(captured_images)
        
        # Xóa ảnh tạm
        for temp_path in captured_images:
            try:
                os.remove(temp_path)
            except:
                pass
        
        print(f"🗑️ Đã xóa {len(captured_images)} ảnh tạm")
        
        return jsonify(recognition_result), 200
        
    except Exception as e:
        print(f"\n❌ Lỗi /auto_capture_compare: {e}")
        traceback.print_exc()
        return jsonify({"error": str(e)}), 500

# ============================================================
# KHỞI ĐỘNG HỆ THỐNG
# ============================================================

if __name__ == '__main__':
    print("=" * 80)
    print("🚀 Đang khởi động hệ thống...")
    print("=" * 80)
    
    try:
        print("\n1️⃣ Khởi tạo database...")
        init_db()
        print("   ✅ Database OK")
    except Exception as e:
        print(f"   ❌ Lỗi init_db: {e}")
        traceback.print_exc()
    
    try:
        print("\n2️⃣ Load templates từ database...")
        load_known_faces()
        print("   ✅ Load templates OK")
    except Exception as e:
        print(f"   ❌ Lỗi load_known_faces: {e}")
        traceback.print_exc()
    
    print("\n" + "=" * 80)
    print("🚀 HỆ THỐNG NHẬN DIỆN KHUÔN MẶT NÂNG CAO")
    print("🧠 Công nghệ: MediaPipe + Frame Diff + Template Matching")
    print("✨ Tính năng đặc biệt:")
    print("   🎯 Motion Detection (Frame Diff) - tiết kiệm CPU")
    print("   😷 Nhận diện khi đeo khẩu trang")
    print("   🕶️ Nhận diện khi đeo kính")
    print("   📹 Stream liên tục + phát hiện tự động")
    print("   ⏱️ Giữ yên 2 giây → chụp 4 ảnh → so sánh")
    print("   👋 Hiển thị avatar + lời chào cá nhân")
    print("   🎯 Độ chính xác cao với ngưỡng 50%")
    print(f"   📁 Ảnh khuôn mặt: {IMG_DIR}/")
    print(f"   🗄️ Database: {DB_FILE}")
    print("📡 API Endpoints:")
    print("   POST /recognize → Motion + Face detection")
    print("   POST /smart_recognition → Nhận diện thông minh")
    print("   POST /capture_and_recognize → Chụp 4 ảnh và nhận diện")
    print("   POST /auto_capture_compare → So sánh 4 ảnh base64")
    print("   POST /enroll → Đăng ký khuôn mặt")
    print("   GET  /members → Danh sách thành viên")
    print("   POST /delete → Xóa thành viên")
    print("   GET  /status → Trạng thái hệ thống")
    print("=" * 80)
    app.run(host='0.0.0.0', port=5000, debug=False, threaded=True)