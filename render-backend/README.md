# Smart Home Render Backend

Backend server cho hệ thống nhà thông minh ESP32-CAM với HiveMQ MQTT và PostgreSQL.

## 🚀 Features

- **MQTT Integration**: Kết nối với HiveMQ Cloud để điều khiển thiết bị realtime
- **PostgreSQL Database**: Lưu trữ members, logs, analytics
- **RESTful API**: Endpoints cho Flutter app
- **Auto Sync**: Tự động sync dữ liệu giữa MQTT và Database
- **Cloud Hosting**: Deploy trên Render với free tier

## 📦 Tech Stack

- **Runtime**: Node.js 18+
- **Framework**: Express.js
- **MQTT Client**: mqtt.js
- **Database**: PostgreSQL (Render)
- **Security**: Helmet, CORS, JWT

## 🔧 Installation

### Local Development

```bash
# Install dependencies
npm install

# Copy environment file
cp .env.example .env

# Edit .env with your credentials
nano .env

# Run server
npm start

# Or with nodemon for development
npm run dev
```

### Deploy to Render

1. Push code to GitHub
2. Create PostgreSQL database on Render
3. Create Web Service on Render
4. Connect GitHub repo
5. Add environment variables
6. Deploy!

## 🌐 API Endpoints

### Health & Status
```
GET  /health                    - Health check
GET  /api/mqtt/status           - MQTT connection status
```

### Members
```
GET    /api/members             - Get all members
POST   /api/members/enroll      - Enroll new member
DELETE /api/members/:id         - Delete member
```

### Face Recognition
```
GET  /api/face-recognition/history  - Get recognition history
POST /api/face-recognition/log      - Log recognition result
```

### Device Control
```
POST /api/devices/control       - Control device via MQTT
GET  /api/devices/status        - Get all device status
```

### Analytics
```
GET  /api/analytics/dashboard   - Get dashboard analytics
```

## 📡 MQTT Topics

### Subscribe (Backend listens to)
```
home/face_recognition/detected
home/face_recognition/result
home/face_recognition/alert
home/devices/+/+/state
home/logs/+
home/analytics/stats
```

### Publish (Backend sends to)
```
home/devices/{type}/{name}/command
home/members/enrolled
home/members/deleted
```

## 🗄️ Database Schema

### members
```sql
id, user_id, name, role, avatar_url, 
pose1_url, pose2_url, pose3_url, 
enrolled_at, updated_at
```

### face_recognition_logs
```sql
id, member_id, action, confidence, 
image_url, is_stranger, detected_at, location
```

### device_logs
```sql
id, device_type, device_name, action, 
triggered_by, mqtt_topic, payload, created_at
```

### system_logs
```sql
id, level, message, metadata, created_at
```

## 🔐 Environment Variables

```env
# HiveMQ
HIVEMQ_HOST=xxxxxxxx.s1.eu.hivemq.cloud
HIVEMQ_PORT=8883
HIVEMQ_USERNAME=your_username
HIVEMQ_PASSWORD=your_password
HIVEMQ_USE_TLS=true

# PostgreSQL (Render provides this)
DATABASE_URL=postgresql://...

# Server
PORT=3000
NODE_ENV=production

# Security
JWT_SECRET=your_jwt_secret
API_KEY=your_api_key

# External Services
PYTHON_AI_URL=http://192.168.110.101:5000
ESP32_IP=192.168.110.38
```

## 📊 Monitoring

### View Logs
```bash
# On Render Dashboard
Dashboard → Service → Logs
```

### Query Database
```sql
-- Total members
SELECT COUNT(*) FROM members;

-- Today's detections
SELECT COUNT(*) FROM face_recognition_logs 
WHERE detected_at >= CURRENT_DATE;

-- Strangers detected
SELECT COUNT(*) FROM face_recognition_logs 
WHERE is_stranger = true;
```

## 🐛 Troubleshooting

### MQTT not connecting
- Check HiveMQ credentials
- Verify port 8883 is open
- Ensure TLS is enabled

### Database connection failed
- Check DATABASE_URL is correct
- Verify SSL is enabled
- Check if database is sleeping (free tier)

### Service sleeping (Free tier)
- Render free tier sleeps after 15 min inactivity
- Use cron job to ping /health every 10 min
- Or upgrade to paid plan ($7/month)

## 📝 License

MIT

## 👤 Author

Nguyễn Phùng Thịnh
