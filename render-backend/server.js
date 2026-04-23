require('dotenv').config();
const express = require('express');
const mqtt = require('mqtt');
const { Pool } = require('pg');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const axios = require('axios');

const app = express();
const PORT = process.env.PORT || 3000;

// ============================================================
// MIDDLEWARE
// ============================================================
app.use(helmet());
app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(morgan('combined'));

// ============================================================
// POSTGRESQL CONNECTION
// ============================================================
const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
  ssl: process.env.NODE_ENV === 'production' ? { rejectUnauthorized: false } : false
});

pool.on('connect', () => {
  console.log('✅ PostgreSQL connected');
});

pool.on('error', (err) => {
  console.error('❌ PostgreSQL error:', err);
});

// ============================================================
// HIVEMQ MQTT CONNECTION
// ============================================================
const mqttOptions = {
  host: process.env.HIVEMQ_HOST,
  port: parseInt(process.HIVEMQ_PORT) || 8883,
  protocol: process.env.HIVEMQ_USE_TLS === 'true' ? 'mqtts' : 'mqtt',
  username: process.env.HIVEMQ_USERNAME,
  password: process.env.HIVEMQ_PASSWORD,
  clientId: `render_backend_${Math.random().toString(16).slice(3)}`,
  clean: true,
  reconnectPeriod: 5000,
  connectTimeout: 30000
};

let mqttClient = null;
let mqttConnected = false;

function connectMQTT() {
  console.log('🔌 Connecting to HiveMQ...');
  mqttClient = mqtt.connect(mqttOptions);

  mqttClient.on('connect', () => {
    console.log('✅ HiveMQ MQTT connected');
    mqttConnected = true;
    
    // Subscribe to all topics
    const topics = [
      'home/face_recognition/detected',
      'home/face_recognition/result',
      'home/face_recognition/alert',
      'home/devices/+/+/state',
      'home/logs/+',
      'home/analytics/stats'
    ];
    
    topics.forEach(topic => {
      mqttClient.subscribe(topic, (err) => {
        if (!err) console.log(`📡 Subscribed to: ${topic}`);
      });
    });
  });

  mqttClient.on('message', async (topic, message) => {
    try {
      const payload = JSON.parse(message.toString());
      console.log(`📨 MQTT Message [${topic}]:`, payload);
      
      // Xử lý message theo topic
      await handleMQTTMessage(topic, payload);
    } catch (error) {
      console.error('❌ Error handling MQTT message:', error);
    }
  });

  mqttClient.on('error', (error) => {
    console.error('❌ MQTT Error:', error);
    mqttConnected = false;
  });

  mqttClient.on('close', () => {
    console.log('⚠️ MQTT connection closed');
    mqttConnected = false;
  });

  mqttClient.on('reconnect', () => {
    console.log('🔄 MQTT reconnecting...');
  });
}

// Xử lý MQTT messages
async function handleMQTTMessage(topic, payload) {
  try {
    // Face recognition result
    if (topic === 'home/face_recognition/result') {
      await pool.query(
        `INSERT INTO face_recognition_logs (member_id, action, confidence, is_stranger, detected_at, location)
         VALUES ((SELECT id FROM members WHERE name = $1), $2, $3, $4, NOW(), $5)`,
        [payload.name || null, payload.action, payload.confidence, payload.is_stranger || false, payload.location || 'front_door']
      );
      console.log('✅ Face recognition log saved');
    }
    
    // Device state change
    if (topic.startsWith('home/devices/') && topic.endsWith('/state')) {
      const parts = topic.split('/');
      const deviceType = parts[2];
      const deviceName = parts[3];
      
      await pool.query(
        `INSERT INTO device_logs (device_type, device_name, action, mqtt_topic, payload, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [deviceType, deviceName, payload.state || payload.action, topic, JSON.stringify(payload)]
      );
      console.log(`✅ Device log saved: ${deviceType}/${deviceName}`);
    }
    
    // System logs
    if (topic.startsWith('home/logs/')) {
      await pool.query(
        `INSERT INTO system_logs (level, message, metadata, created_at)
         VALUES ($1, $2, $3, NOW())`,
        [payload.level || 'info', payload.message, JSON.stringify(payload.metadata || {})]
      );
    }
  } catch (error) {
    console.error('❌ Error saving to database:', error);
  }
}

// Publish MQTT message
function publishMQTT(topic, payload) {
  if (!mqttConnected || !mqttClient) {
    console.error('❌ MQTT not connected');
    return false;
  }
  
  mqttClient.publish(topic, JSON.stringify(payload), { qos: 1 }, (err) => {
    if (err) {
      console.error(`❌ Failed to publish to ${topic}:`, err);
    } else {
      console.log(`📤 Published to ${topic}:`, payload);
    }
  });
  
  return true;
}

// ============================================================
// API ROUTES
// ============================================================

// Health check
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    mqtt: mqttConnected,
    database: pool.totalCount > 0,
    timestamp: new Date().toISOString()
  });
});

// MQTT Status
app.get('/api/mqtt/status', (req, res) => {
  res.json({
    connected: mqttConnected,
    host: process.env.HIVEMQ_HOST,
    clientId: mqttClient?.options?.clientId
  });
});

// ============================================================
// MEMBERS API
// ============================================================

// Get all members
app.get('/api/members', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT id, user_id, name, role, avatar_url, enrolled_at FROM members ORDER BY enrolled_at DESC'
    );
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error('❌ Error fetching members:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Enroll new member
app.post('/api/members/enroll', async (req, res) => {
  try {
    const { user_id, name, role, avatar_url, pose1_url, pose2_url, pose3_url } = req.body;
    
    const result = await pool.query(
      `INSERT INTO members (user_id, name, role, avatar_url, pose1_url, pose2_url, pose3_url, enrolled_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, NOW())
       RETURNING *`,
      [user_id, name, role || 'Member', avatar_url, pose1_url, pose2_url, pose3_url]
    );
    
    // Publish to MQTT
    publishMQTT('home/members/enrolled', {
      user_id,
      name,
      timestamp: new Date().toISOString()
    });
    
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error('❌ Error enrolling member:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Delete member
app.delete('/api/members/:id', async (req, res) => {
  try {
    const { id } = req.params;
    
    const result = await pool.query(
      'DELETE FROM members WHERE user_id = $1 OR id = $2 RETURNING *',
      [id, id]
    );
    
    if (result.rowCount === 0) {
      return res.status(404).json({ success: false, error: 'Member not found' });
    }
    
    // Publish to MQTT
    publishMQTT('home/members/deleted', {
      user_id: id,
      timestamp: new Date().toISOString()
    });
    
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error('❌ Error deleting member:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================
// FACE RECOGNITION API
// ============================================================

// Get face recognition history
app.get('/api/face-recognition/history', async (req, res) => {
  try {
    const { limit = 50, offset = 0 } = req.query;
    
    const result = await pool.query(
      `SELECT frl.*, m.name, m.user_id, m.avatar_url
       FROM face_recognition_logs frl
       LEFT JOIN members m ON frl.member_id = m.id
       ORDER BY frl.detected_at DESC
       LIMIT $1 OFFSET $2`,
      [limit, offset]
    );
    
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error('❌ Error fetching history:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Log face recognition result
app.post('/api/face-recognition/log', async (req, res) => {
  try {
    const { name, user_id, action, confidence, is_stranger, image_url, location } = req.body;
    
    let memberId = null;
    if (name && !is_stranger) {
      const memberResult = await pool.query(
        'SELECT id FROM members WHERE name = $1 OR user_id = $2',
        [name, user_id]
      );
      if (memberResult.rows.length > 0) {
        memberId = memberResult.rows[0].id;
      }
    }
    
    const result = await pool.query(
      `INSERT INTO face_recognition_logs (member_id, action, confidence, image_url, is_stranger, detected_at, location)
       VALUES ($1, $2, $3, $4, $5, NOW(), $6)
       RETURNING *`,
      [memberId, action, confidence, image_url, is_stranger || false, location || 'front_door']
    );
    
    // Publish to MQTT
    publishMQTT('home/face_recognition/result', {
      name: name || 'Unknown',
      confidence,
      is_stranger,
      action,
      timestamp: new Date().toISOString()
    });
    
    res.json({ success: true, data: result.rows[0] });
  } catch (error) {
    console.error('❌ Error logging face recognition:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================
// DEVICE CONTROL API
// ============================================================

// Control device via MQTT
app.post('/api/devices/control', async (req, res) => {
  try {
    const { device_type, device_name, action, payload } = req.body;
    
    const topic = `home/devices/${device_type}/${device_name}/command`;
    const success = publishMQTT(topic, { action, ...payload, timestamp: Date.now() });
    
    if (success) {
      // Log to database
      await pool.query(
        `INSERT INTO device_logs (device_type, device_name, action, mqtt_topic, payload, created_at)
         VALUES ($1, $2, $3, $4, $5, NOW())`,
        [device_type, device_name, action, topic, JSON.stringify(payload)]
      );
      
      res.json({ success: true, message: 'Command sent' });
    } else {
      res.status(503).json({ success: false, error: 'MQTT not connected' });
    }
  } catch (error) {
    console.error('❌ Error controlling device:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Get device status
app.get('/api/devices/status', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT DISTINCT ON (device_type, device_name) 
       device_type, device_name, action, payload, created_at
       FROM device_logs
       ORDER BY device_type, device_name, created_at DESC`
    );
    
    res.json({ success: true, data: result.rows });
  } catch (error) {
    console.error('❌ Error fetching device status:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================
// ANALYTICS API
// ============================================================

// Dashboard analytics
app.get('/api/analytics/dashboard', async (req, res) => {
  try {
    const [membersCount, logsToday, strangersToday, devicesActive] = await Promise.all([
      pool.query('SELECT COUNT(*) FROM members'),
      pool.query(`SELECT COUNT(*) FROM face_recognition_logs WHERE detected_at >= CURRENT_DATE`),
      pool.query(`SELECT COUNT(*) FROM face_recognition_logs WHERE is_stranger = true AND detected_at >= CURRENT_DATE`),
      pool.query(`SELECT COUNT(DISTINCT device_name) FROM device_logs WHERE created_at >= NOW() - INTERVAL '1 hour'`)
    ]);
    
    res.json({
      success: true,
      data: {
        total_members: parseInt(membersCount.rows[0].count),
        logs_today: parseInt(logsToday.rows[0].count),
        strangers_today: parseInt(strangersToday.rows[0].count),
        devices_active: parseInt(devicesActive.rows[0].count),
        timestamp: new Date().toISOString()
      }
    });
  } catch (error) {
    console.error('❌ Error fetching analytics:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// ============================================================
// DATABASE INITIALIZATION
// ============================================================
async function initDatabase() {
  try {
    // Create tables if not exist
    await pool.query(`
      CREATE TABLE IF NOT EXISTS members (
        id SERIAL PRIMARY KEY,
        user_id VARCHAR(50) UNIQUE NOT NULL,
        name VARCHAR(100) NOT NULL,
        role VARCHAR(50) DEFAULT 'Member',
        avatar_url TEXT,
        pose1_url TEXT,
        pose2_url TEXT,
        pose3_url TEXT,
        enrolled_at TIMESTAMP DEFAULT NOW(),
        updated_at TIMESTAMP DEFAULT NOW()
      );
      
      CREATE TABLE IF NOT EXISTS face_recognition_logs (
        id SERIAL PRIMARY KEY,
        member_id INTEGER REFERENCES members(id) ON DELETE SET NULL,
        action VARCHAR(50) NOT NULL,
        confidence FLOAT,
        image_url TEXT,
        is_stranger BOOLEAN DEFAULT FALSE,
        detected_at TIMESTAMP DEFAULT NOW(),
        location VARCHAR(50) DEFAULT 'front_door'
      );
      
      CREATE TABLE IF NOT EXISTS device_logs (
        id SERIAL PRIMARY KEY,
        device_type VARCHAR(50) NOT NULL,
        device_name VARCHAR(100) NOT NULL,
        action VARCHAR(50) NOT NULL,
        triggered_by INTEGER REFERENCES members(id) ON DELETE SET NULL,
        mqtt_topic VARCHAR(200),
        payload JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      CREATE TABLE IF NOT EXISTS system_logs (
        id SERIAL PRIMARY KEY,
        level VARCHAR(20) NOT NULL,
        message TEXT NOT NULL,
        metadata JSONB,
        created_at TIMESTAMP DEFAULT NOW()
      );
      
      CREATE INDEX IF NOT EXISTS idx_face_logs_detected_at ON face_recognition_logs(detected_at DESC);
      CREATE INDEX IF NOT EXISTS idx_device_logs_created_at ON device_logs(created_at DESC);
      CREATE INDEX IF NOT EXISTS idx_system_logs_created_at ON system_logs(created_at DESC);
    `);
    
    console.log('✅ Database tables initialized');
  } catch (error) {
    console.error('❌ Error initializing database:', error);
  }
}

// ============================================================
// START SERVER
// ============================================================
async function startServer() {
  try {
    // Initialize database
    await initDatabase();
    
    // Connect to MQTT
    connectMQTT();
    
    // Start Express server
    app.listen(PORT, '0.0.0.0', () => {
      console.log('='.repeat(60));
      console.log(`🚀 Render Backend Server running on port ${PORT}`);
      console.log(`📡 HiveMQ: ${process.env.HIVEMQ_HOST}`);
      console.log(`🗄️  PostgreSQL: Connected`);
      console.log('='.repeat(60));
    });
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
}

startServer();

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('⚠️ SIGTERM received, shutting down gracefully...');
  if (mqttClient) mqttClient.end();
  pool.end();
  process.exit(0);
});
