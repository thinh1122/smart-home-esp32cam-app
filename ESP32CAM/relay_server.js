const express = require('express');
const http = require('http');
const WebSocket = require('ws');
const axios = require('axios');

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server });

// Cấu hình
const ESP32_IP = '192.168.110.38';  // ⚠️ IP ESP32-CAM
const RELAY_PORT = 8080;
const PYTHON_PORT = 5000;

// Lưu frame mới nhất
let latestFrame = null;
let frameTimestamp = 0;
let frameCount = 0;
let lastErrorTime = 0;
let consecutiveErrors = 0;
const MAX_CONSECUTIVE_ERRORS = 5;

// CORS
app.use((req, res, next) => {
    res.header('Access-Control-Allow-Origin', '*');
    res.header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    res.header('Access-Control-Allow-Headers', 'Content-Type');
    next();
});

app.use(express.json({ limit: '10mb' }));

console.log('🚀 ESP32-CAM Relay Server (OPTIMIZED) khởi động...');

// ============================================================
// CHỨC NĂNG 1: LẤY FRAME TỪ ESP32 - TỐI ƯU HÓA
// ============================================================
async function fetchFrameFromESP32() {
    try {
        const response = await axios.get(`http://${ESP32_IP}:81/capture`, {
            responseType: 'arraybuffer',
            timeout: 3000,  // Giảm xuống 3s để phản hồi nhanh hơn
            maxContentLength: 100000  // Giới hạn 100KB
        });
        
        if (response.status === 200) {
            latestFrame = Buffer.from(response.data);
            frameTimestamp = Date.now();
            frameCount++;
            consecutiveErrors = 0;  // Reset error counter
            
            // Broadcast tới tất cả WebSocket clients
            broadcastFrame();
            
            // Log mỗi 20 frame
            if (frameCount % 20 === 0) {
                console.log(`📸 ${frameCount} frames | Lỗi liên tiếp: 0`);
            }
        }
    } catch (error) {
        consecutiveErrors++;
        
        // Chỉ log lỗi khi vượt ngưỡng hoặc mỗi 30 giây
        const now = Date.now();
        if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS || !lastErrorTime || now - lastErrorTime > 30000) {
            console.log(`⚠️ ESP32-CAM lỗi ${consecutiveErrors}/${MAX_CONSECUTIVE_ERRORS}: ${error.message}`);
            lastErrorTime = now;
        }
        
        // Nếu quá nhiều lỗi liên tiếp, giảm tần suất
        if (consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
            console.log(`🔴 ESP32-CAM quá tải! Giảm tần suất xuống 0.1 FPS...`);
            setStreamFrequency(10000, "Quá tải → 0.1 FPS");
        }
    }
}

// Tần suất stream thông minh - TỐI ƯU HÓA
let currentInterval = null;
let isDetectingFace = false;

function setStreamFrequency(intervalMs, reason) {
    if (currentInterval) {
        clearInterval(currentInterval);
    }
    
    currentInterval = setInterval(() => {
        fetchFrameFromESP32();
    }, intervalMs);
    
    const fps = (1000 / intervalMs).toFixed(2);
    console.log(`⚡ Tần suất: ${fps} FPS (${reason})`);
}

function adjustStreamFrequency(faceDetected) {
    // Reset error counter khi có face detection thành công
    if (faceDetected || !faceDetected) {
        consecutiveErrors = 0;
    }
    
    if (faceDetected && !isDetectingFace) {
        // Có face → tăng lên 2 FPS để stream mượt
        setStreamFrequency(500, "Face detected → 2 FPS");
        isDetectingFace = true;
    } else if (!faceDetected && isDetectingFace) {
        // Mất face → giảm xuống 1 FPS (vẫn mượt)
        setStreamFrequency(1000, "No face → 1 FPS");
        isDetectingFace = false;
    }
}

// Bắt đầu với tần suất 1 FPS (mượt hơn)
setStreamFrequency(1000, "Khởi động → 1 FPS");

// ============================================================
// CHỨC NĂNG 2: WEBSOCKET STREAM CHO FLUTTER
// ============================================================
function broadcastFrame() {
    if (!latestFrame) return;
    
    wss.clients.forEach(client => {
        if (client.readyState === WebSocket.OPEN) {
            try {
                client.send(latestFrame);
            } catch (error) {
                console.log('⚠️ Lỗi gửi frame qua WebSocket');
            }
        }
    });
}

wss.on('connection', (ws) => {
    console.log('📱 Flutter app kết nối WebSocket');
    
    // Gửi frame mới nhất ngay lập tức
    if (latestFrame) {
        try {
            ws.send(latestFrame);
        } catch (error) {
            console.log('⚠️ Lỗi gửi frame đầu tiên');
        }
    }
    
    ws.on('close', () => {
        console.log('📱 Flutter app ngắt kết nối');
    });
    
    ws.on('error', (error) => {
        console.log('⚠️ WebSocket error:', error.message);
    });
});

// ============================================================
// CHỨC NĂNG 3: HTTP ENDPOINTS - TỐI ƯU HÓA
// ============================================================

// Endpoint cho Flutter lấy frame đơn lẻ
app.get('/capture', (req, res) => {
    if (!latestFrame) {
        return res.status(503).json({ error: 'Chưa có frame' });
    }
    
    res.set({
        'Content-Type': 'image/jpeg',
        'Content-Length': latestFrame.length,
        'Cache-Control': 'no-cache'
    });
    res.send(latestFrame);
});

// MJPEG Stream cho Flutter (fallback) - TỐI ƯU HÓA
app.get('/stream', (req, res) => {
    res.writeHead(200, {
        'Content-Type': 'multipart/x-mixed-replace; boundary=frame',
        'Cache-Control': 'no-cache',
        'Connection': 'close'
    });
    
    const sendFrame = () => {
        if (latestFrame && !res.writableEnded) {
            try {
                res.write('--frame\r\n');
                res.write('Content-Type: image/jpeg\r\n');
                res.write(`Content-Length: ${latestFrame.length}\r\n\r\n`);
                res.write(latestFrame);
                res.write('\r\n');
            } catch (error) {
                clearInterval(interval);
            }
        }
    };
    
    // Gửi frame đầu tiên
    sendFrame();
    
    // Gửi frame mới mỗi 100ms (10 FPS) để stream realtime
    const interval = setInterval(sendFrame, 100);
    
    req.on('close', () => {
        clearInterval(interval);
        console.log('📱 MJPEG stream đóng');
    });
});

// Endpoint kiểm tra có face không - TỐI ƯU HÓA
app.post('/recognize', async (req, res) => {
    try {
        const response = await axios.post(`http://127.0.0.1:${PYTHON_PORT}/recognize`, req.body, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 8000  // Giảm timeout xuống 8s
        });
        res.json(response.data);
    } catch (error) {
        console.log(`❌ /recognize: ${error.message}`);
        res.status(500).json({ error: 'Python server không phản hồi', face_count: 0, faces: [] });
    }
});

// Proxy cho auto_capture_compare
app.post('/auto_capture_compare', async (req, res) => {
    try {
        const response = await axios.post(`http://127.0.0.1:${PYTHON_PORT}/auto_capture_compare`, req.body, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 15000
        });
        res.json(response.data);
    } catch (error) {
        console.log(`❌ /auto_capture_compare: ${error.message}`);
        res.status(500).json({ error: 'Python server không phản hồi' });
    }
});

// Proxy cho enroll
app.post('/enroll', async (req, res) => {
    try {
        const response = await axios.post(`http://127.0.0.1:${PYTHON_PORT}/enroll`, req.body, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 15000
        });
        res.json(response.data);
    } catch (error) {
        console.log(`❌ /enroll: ${error.message}`);
        res.status(500).json({ error: 'Python server không phản hồi' });
    }
});

// Proxy cho members
app.get('/members', async (req, res) => {
    try {
        const response = await axios.get(`http://127.0.0.1:${PYTHON_PORT}/members`, {
            timeout: 5000
        });
        res.json(response.data);
    } catch (error) {
        console.log(`❌ /members: ${error.message}`);
        res.status(500).json({ error: 'Python server không phản hồi' });
    }
});

// Proxy cho delete
app.post('/delete', async (req, res) => {
    try {
        const response = await axios.post(`http://127.0.0.1:${PYTHON_PORT}/delete`, req.body, {
            headers: { 'Content-Type': 'application/json' },
            timeout: 5000
        });
        res.json(response.data);
    } catch (error) {
        console.log(`❌ /delete: ${error.message}`);
        res.status(500).json({ error: 'Python server không phản hồi' });
    }
});

// Status endpoint
app.get('/status', (req, res) => {
    res.json({
        status: 'online',
        esp32_connected: latestFrame !== null && consecutiveErrors < MAX_CONSECUTIVE_ERRORS,
        last_frame: frameTimestamp,
        frame_count: frameCount,
        consecutive_errors: consecutiveErrors,
        clients: wss.clients.size,
        current_fps: isDetectingFace ? 0.5 : 0.2
    });
});

// ============================================================
// KHỞI ĐỘNG SERVER
// ============================================================
server.listen(RELAY_PORT, '0.0.0.0', () => {
    console.log('='.repeat(60));
    console.log(`🌐 Relay Server: http://0.0.0.0:${RELAY_PORT}`);
    console.log(`📡 ESP32-CAM: http://${ESP32_IP}:81`);
    console.log(`🤖 Python AI: http://127.0.0.1:${PYTHON_PORT}`);
    console.log('');
    console.log('📱 Flutter endpoints:');
    console.log(`   GET  /stream    → MJPEG stream (300ms/frame)`);
    console.log(`   GET  /capture   → Single frame`);
    console.log(`   POST /recognize → Face detection`);
    console.log(`   POST /auto_capture_compare → Face recognition`);
    console.log(`   POST /enroll    → Face enrollment`);
    console.log(`   GET  /members   → Member list`);
    console.log(`   GET  /status    → Server status`);
    console.log('');
    console.log('⚡ Tối ưu hóa:');
    console.log('   - Tần suất thấp: 0.2 FPS (5s/frame)');
    console.log('   - Có face: 0.5 FPS (2s/frame)');
    console.log('   - Timeout: 3s');
    console.log('   - Max errors: 5 liên tiếp');
    console.log('='.repeat(60));
});
