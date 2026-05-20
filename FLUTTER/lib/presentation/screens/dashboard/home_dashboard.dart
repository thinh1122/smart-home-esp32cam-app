import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/device_config_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/notification_service.dart';
import '../../widgets/live_mjpeg.dart';
import '../lights/living_room_light_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  // Devices từ DB
  List<Map<String, dynamic>> _lights = [];

  // Device states — updated via MQTT (key = room)
  final Map<String, bool>   _lightStates = {};
  final Map<String, double> _lightWatts  = {};

  bool _doorLocked = true;
  bool _mqttConnected = false;
  Key _streamKey = UniqueKey();
  Timer? _retryTimer;

  // Trạng thái nhận diện khuôn mặt mới nhất từ MQTT
  Map<String, dynamic>? _lastFaceEvent;
  Timer? _faceEventClearTimer;

  // Bounding box khuôn mặt (tọa độ relative 0..1)
  Map<String, dynamic>? _faceBbox;
  Timer? _bboxClearTimer;

  StreamSubscription? _deviceSub;
  StreamSubscription? _faceSub;
  StreamSubscription? _bboxSub;
  StreamSubscription? _powerSub;

  @override
  void initState() {
    super.initState();
    _loadDevices();
    _connectMQTT();
    DeviceConfigService.instance.aiServerNotifier.addListener(_onEsp32Changed);
  }

  Future<void> _loadDevices() async {
    final rows = await DatabaseHelper.instance.getAllDevices();
    if (mounted) {
      setState(() {
        _lights = rows.where((d) => d['device_type'] == 'light').toList();
      });
    }
  }

  void _onEsp32Changed() {
    if (mounted) setState(() => _streamKey = UniqueKey());
  }

  @override
  void dispose() {
    DeviceConfigService.instance.aiServerNotifier.removeListener(_onEsp32Changed);
    _deviceSub?.cancel();
    _faceSub?.cancel();
    _bboxSub?.cancel();
    _powerSub?.cancel();
    _retryTimer?.cancel();
    _faceEventClearTimer?.cancel();
    _bboxClearTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectMQTT() async {
    final ok = await MQTTService().connect();
    if (!mounted) return;
    setState(() => _mqttConnected = ok);

    // Lắng nghe trạng thái thiết bị real-time từ MQTT
    _deviceSub = MQTTService().deviceStateStream.listen((event) {
      final topic = event['topic'] as String;
      final data = event['data'] as Map<String, dynamic>;
      final state = (data['state'] as String? ?? '').toUpperCase();
      if (!mounted) return;
      final parts = topic.split('/');
      if (topic.contains('door')) {
        setState(() => _doorLocked = state == 'LOCKED');
      } else if (parts.length >= 4) {
        final room = parts[3];
        setState(() => _lightStates[room] = state == 'ON');
      }
    });

    // Lắng nghe MQTT nhận diện khuôn mặt
    _faceSub = MQTTService().faceRecognitionStream.listen((event) {
      if (!mounted) return;
      final topic = event['topic'] as String;
      final data = event['data'] as Map<String, dynamic>;
      setState(() => _lastFaceEvent = {'topic': topic, ...data});
      _faceEventClearTimer?.cancel();
      _faceEventClearTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _lastFaceEvent = null);
      });

      if (topic == AppConfig.topicFaceResult && (data['matched'] as bool? ?? false)) {
        final name = data['name'] as String? ?? '';
        final role = data['role'] as String? ?? '';
        final conf = data['confidence'] != null
            ? '${((data['confidence'] as num) * 100).toStringAsFixed(0)}%'
            : '';
        _showBanner('Xin chào $name! Chào mừng về nhà 👋', AppColors.success);
        NotificationService.instance.showMemberRecognized(name: name, role: role, confidence: conf);
      } else if (topic == AppConfig.topicFaceAlert) {
        _showBanner('CẢNH BÁO: Phát hiện người lạ!', AppColors.error);
        NotificationService.instance.showStrangerAlert();
      }
    });

    // Lắng nghe power data từ ACS712 ESP32-S3
    _powerSub = MQTTService().devicePowerStream.listen((event) {
      if (!mounted) return;
      final topic = event['topic'] as String;
      final data  = event['data'] as Map<String, dynamic>;
      final parts = topic.split('/');
      if (parts.length >= 4) {
        final room = parts[3];
        final watt = (data['watt'] as num?)?.toDouble() ?? 0;
        setState(() => _lightWatts[room] = watt);
      }
    });

    // Lắng nghe bbox khuôn mặt để vẽ overlay
    _bboxSub = MQTTService().faceBboxStream.listen((bbox) {
      if (!mounted) return;
      if (bbox['clear'] == true) {
        _bboxClearTimer?.cancel();
        setState(() => _faceBbox = null);
        return;
      }
      setState(() => _faceBbox = bbox);
      _bboxClearTimer?.cancel();
      _bboxClearTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _faceBbox = null);
      });
    });
  }

  void _reconnectStream() {
    _retryTimer?.cancel();
    setState(() => _streamKey = UniqueKey());
  }

  void _onStreamError() {
    if (!mounted) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && AppConfig.streamUrl.isNotEmpty) {
        setState(() => _streamKey = UniqueKey());
      }
    });
  }

  // Toggle đèn → publish MQTT
  void _toggleLight(String room, bool v) {
    setState(() => _lightStates[room] = v);
    MQTTService().controlLight(room, v);
  }

  // Toggle cửa → publish MQTT
  void _toggleDoor(bool v) {
    setState(() => _doorLocked = v);
    MQTTService().controlDoor('front_door', v ? 'LOCK' : 'UNLOCK');
  }

  void _showBanner(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        duration: const Duration(seconds: 5),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  int get _lightsOn => _lightStates.values.where((v) => v).length;
  double get _totalWatt => _lightWatts.values.fold(0.0, (a, b) => a + b);

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Chào buổi sáng';
    if (h < 17) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
            SliverToBoxAdapter(child: _buildStatsBar()),
            SliverToBoxAdapter(child: const SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildCameraPreview()),
            SliverToBoxAdapter(child: const SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildSectionTitle('Phòng')),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildRoomsRow()),
            SliverToBoxAdapter(child: const SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildSectionTitle('Điều khiển nhanh')),
            SliverToBoxAdapter(child: const SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildDeviceToggles()),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.accentDim, width: 2),
              image: const DecorationImage(
                image: NetworkImage('https://i.pravatar.cc/150?img=11'),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                const Text('Nguyễn Phùng Thịnh',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // MQTT status dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (_mqttConnected ? AppColors.success : AppColors.error).withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: (_mqttConnected ? AppColors.success : AppColors.error).withOpacity(0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: BoxDecoration(
                    color: _mqttConnected ? AppColors.success : AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _mqttConnected ? 'Online' : 'Offline',
                  style: TextStyle(
                    color: _mqttConnected ? AppColors.success : AppColors.error,
                    fontSize: 11, fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          _buildStatChip(Icons.lightbulb_rounded, AppColors.lightColor, '$_lightsOn', 'Đèn bật'),
          const SizedBox(width: 10),
          _buildStatChip(
            _doorLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            _doorLocked ? AppColors.success : AppColors.warning,
            _doorLocked ? 'Khoá' : 'Mở',
            'Cửa',
          ),
          const SizedBox(width: 10),
          _buildStatChip(Icons.wifi_rounded, _mqttConnected ? AppColors.info : AppColors.textSecondary,
              _mqttConnected ? 'On' : 'Off', 'MQTT'),
          const SizedBox(width: 10),
          _buildStatChip(
            Icons.bolt_rounded,
            _totalWatt > 0 ? AppColors.warning : AppColors.textSecondary,
            '${_totalWatt.toStringAsFixed(0)}W',
            'Công suất',
          ),
          const SizedBox(width: 10),
          _buildFaceChip(),
        ],
      ),
    );
  }

  Widget _buildFaceChip() {
    final event = _lastFaceEvent;
    final isStranger = event != null && event['topic'] == AppConfig.topicFaceAlert;
    final isKnown    = event != null && event['topic'] == AppConfig.topicFaceResult && (event['matched'] as bool? ?? false);
    final hasEvent   = isStranger || isKnown;

    final color = isStranger ? AppColors.error : isKnown ? AppColors.success : AppColors.textSecondary;
    final icon  = isStranger ? Icons.warning_amber_rounded : isKnown ? Icons.face_rounded : Icons.notifications_none_rounded;
    final value = isStranger ? 'Lạ' : isKnown ? (event!['name'] as String? ?? 'OK') : '--';
    final label = isStranger ? 'Cảnh báo' : isKnown ? 'Nhận diện' : 'Thông báo';

    return Expanded(
      child: GestureDetector(
        onTap: hasEvent ? () => _showFaceEventDetail(event!) : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: hasEvent ? color.withOpacity(0.12) : AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasEvent ? color.withOpacity(0.4) : Colors.white.withOpacity(0.06),
              width: hasEvent ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(height: 6),
              Text(
                value,
                style: TextStyle(color: hasEvent ? color : Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  void _showFaceEventDetail(Map<String, dynamic> event) {
    final isStranger = event['topic'] == AppConfig.topicFaceAlert;
    final name       = event['name'] as String? ?? 'Người lạ';
    final conf       = event['confidence'] as double?;
    final color      = isStranger ? AppColors.error : AppColors.success;
    final icon       = isStranger ? Icons.warning_amber_rounded : Icons.check_circle_rounded;

    showDialog(
      context: context,
      builder: (_) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AlertDialog(
          backgroundColor: AppColors.card,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: color.withOpacity(0.15), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                isStranger ? 'Phát hiện người lạ!' : 'Nhận diện thành công',
                style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              if (conf != null) ...[
                const SizedBox(height: 6),
                Text('Độ chính xác: ${(conf * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
              if (!isStranger && event['role'] != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accentDim,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(event['role'] as String,
                      style: const TextStyle(color: AppColors.accentLight, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Đóng', style: TextStyle(color: AppColors.accentLight, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, Color color, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 9)),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraPreview() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Cửa trước', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  GestureDetector(
                    onTap: _reconnectStream,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white38, size: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 6, height: 6,
                            decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('LIVE', style: TextStyle(color: AppColors.error, fontSize: 10,
                            fontWeight: FontWeight.bold, letterSpacing: 1)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (AppConfig.streamUrl.isNotEmpty)
                    LiveMjpeg(
                      key: _streamKey,
                      stream: AppConfig.streamUrl,
                      error: (ctx, err, stack) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _onStreamError());
                        return _buildCamOffline();
                      },
                    )
                  else
                    _buildCamOffline(),
                  // Bounding box overlay khi AI detect khuôn mặt
                  if (_faceBbox != null)
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _FaceBoxPainter(_faceBbox!),
                      ),
                    ),
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 70,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black.withOpacity(0.7), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildCamOffline() => Container(
    color: AppColors.cardElevated,
    child: const Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.videocam_off_rounded, color: Colors.white30, size: 40),
        SizedBox(height: 8),
        Text('Camera offline\nVào Devices → BLE WiFi Setup để kết nối ESP32',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white30, fontSize: 11)),
      ],
    ),
  );

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
  );

  Widget _buildRoomsRow() {
    // Lấy danh sách phòng unique từ DB
    final roomKeys = _lights.map((d) => d['room'] as String).toSet().toList();
    final allItems = <_RoomData>[
      ...roomKeys.map((room) {
        final isOn = _lightStates[room] ?? false;
        final label = _roomLabel(room);
        final icon = _roomIcon(room);
        return _RoomData(label, icon, AppColors.lightColor, isOn ? 1 : 0, room: room);
      }),
      _RoomData('Cửa chính', Icons.door_front_door_rounded,
          _doorLocked ? AppColors.success : AppColors.warning, _doorLocked ? 1 : 0),
    ];

    if (allItems.length == 1) {
      // Chỉ có cửa chính, chưa có đèn
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white10),
          ),
          child: const Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: Colors.white24, size: 28),
              SizedBox(width: 14),
              Text('Chưa có đèn nào được kết nối\nVào Devices → + để thêm thiết bị',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: allItems.length,
        itemBuilder: (ctx, i) => _buildRoomCard(allItems[i]),
      ),
    );
  }

  String _roomLabel(String key) {
    const map = {
      'living_room': 'Phòng khách', 'bedroom': 'Phòng ngủ',
      'kitchen': 'Nhà bếp', 'bathroom': 'Nhà vệ sinh',
      'bedroom2': 'Phòng ngủ 2', 'garage': 'Nhà xe',
    };
    return map[key] ?? key;
  }

  IconData _roomIcon(String key) {
    const map = {
      'living_room': Icons.weekend_rounded, 'bedroom': Icons.bed_rounded,
      'kitchen': Icons.kitchen_rounded, 'bathroom': Icons.shower_rounded,
      'bedroom2': Icons.bed_rounded, 'garage': Icons.garage_rounded,
    };
    return map[key] ?? Icons.lightbulb_rounded;
  }

  Widget _buildRoomCard(_RoomData room) {
    final isOn = room.activeDevices > 0;
    return Container(
      width: 115,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOn ? AppColors.cardElevated : AppColors.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isOn ? room.color.withOpacity(0.35) : Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: room.color.withOpacity(isOn ? 0.2 : 0.07),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(room.icon, color: isOn ? room.color : Colors.white30, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                isOn ? 'Đang bật' : 'Đã tắt',
                style: TextStyle(color: isOn ? room.color : AppColors.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceToggles() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (_lights.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: Colors.white24, size: 22),
                  SizedBox(width: 12),
                  Expanded(child: Text('Chưa có thiết bị đèn nào.\nVào tab Devices → + để thêm.',
                      style: TextStyle(color: Colors.white38, fontSize: 12))),
                ],
              ),
            ),
          ..._lights.asMap().entries.map((e) {
            final d = e.value;
            final room = d['room'] as String;
            final isOn = _lightStates[room] ?? false;
            final watt = _lightWatts[room] ?? 0.0;
            final subtitle = watt > 0 ? '${watt.round()}W · MQTT' : 'MQTT';
            return Padding(
              padding: EdgeInsets.only(bottom: e.key < _lights.length - 1 || true ? 12 : 0),
              child: _buildToggleCard(
                d['name'] as String, subtitle,
                Icons.lightbulb_rounded, AppColors.lightColor,
                isOn, (v) => _toggleLight(room, v),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room))),
              ),
            );
          }),
          const SizedBox(height: 0),
          _buildToggleCard(
            'Khoá cửa chính', _doorLocked ? 'Đang khoá · an toàn' : 'Đang mở · chú ý!',
            _doorLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            _doorLocked ? AppColors.success : AppColors.warning,
            _doorLocked, _toggleDoor,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard(
    String title, String subtitle, IconData icon, Color color,
    bool isActive, ValueChanged<bool> onChanged, {VoidCallback? onTap}
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: isActive ? AppColors.cardElevated : AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? color.withOpacity(0.25) : Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(isActive ? 0.18 : 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: isActive ? color : Colors.white30, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Switch(
            value: isActive,
            onChanged: onChanged,
            activeColor: color,
            activeTrackColor: color.withOpacity(0.3),
            inactiveThumbColor: Colors.white30,
            inactiveTrackColor: Colors.white10,
          ),
        ],
      ),
    ),
    );
  }
}

class _RoomData {
  final String name;
  final IconData icon;
  final Color color;
  final int activeDevices;
  final String? room;
  const _RoomData(this.name, this.icon, this.color, this.activeDevices, {this.room});
}

// Vẽ bounding box xanh lên camera overlay
class _FaceBoxPainter extends CustomPainter {
  final Map<String, dynamic> bbox;
  _FaceBoxPainter(this.bbox);

  @override
  void paint(Canvas canvas, Size size) {
    final x = (bbox['x'] as num).toDouble() * size.width;
    final y = (bbox['y'] as num).toDouble() * size.height;
    final w = (bbox['w'] as num).toDouble() * size.width;
    final h = (bbox['h'] as num).toDouble() * size.height;

    final paint = Paint()
      ..color = const Color(0xFF00FF88)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;

    // Vẽ 4 góc thay vì full box — đẹp hơn
    final cornerLen = w * 0.25;
    // Top-left
    canvas.drawLine(Offset(x, y), Offset(x + cornerLen, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + cornerLen), paint);
    // Top-right
    canvas.drawLine(Offset(x + w, y), Offset(x + w - cornerLen, y), paint);
    canvas.drawLine(Offset(x + w, y), Offset(x + w, y + cornerLen), paint);
    // Bottom-left
    canvas.drawLine(Offset(x, y + h), Offset(x + cornerLen, y + h), paint);
    canvas.drawLine(Offset(x, y + h), Offset(x, y + h - cornerLen), paint);
    // Bottom-right
    canvas.drawLine(Offset(x + w, y + h), Offset(x + w - cornerLen, y + h), paint);
    canvas.drawLine(Offset(x + w, y + h), Offset(x + w, y + h - cornerLen), paint);
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) => old.bbox != bbox;
}
