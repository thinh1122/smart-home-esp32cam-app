import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/device_config_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/avatar_service.dart';
import '../../../core/services/app_notification_service.dart';
import '../../widgets/live_mjpeg.dart';
import '../lights/living_room_light_screen.dart';
import '../notifications/notifications_screen.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  final _notifSvc = AppNotificationService.instance;

  List<Map<String, dynamic>> _lights = [];
  final Map<String, bool>   _lightStates = {};
  final Map<String, double> _lightWatts  = {};

  bool _doorLocked = true;
  Key _streamKey = UniqueKey();
  Timer? _retryTimer;

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
    DatabaseHelper.deviceListNotifier.addListener(_loadDevices);
    DatabaseHelper.deviceStateNotifier.addListener(_loadDevices);
  }

  Future<void> _loadDevices() async {
    final rows = await DatabaseHelper.instance.getAllDevices(userId: AuthService.instance.userId);
    if (mounted) {
      setState(() {
        _lights = rows.where((d) => d['device_type'] == 'light').toList();
        for (final d in _lights) {
          final room = d['room'] as String;
          _lightStates[room] = (d['state'] as String?)?.toUpperCase() == 'ON';
          _lightWatts[room]  = (d['watt'] as num?)?.toDouble() ?? 0;
        }
      });
    }
  }

  void _onEsp32Changed() {
    if (mounted) setState(() => _streamKey = UniqueKey());
  }

  @override
  void dispose() {
    DeviceConfigService.instance.aiServerNotifier.removeListener(_onEsp32Changed);
    DatabaseHelper.deviceListNotifier.removeListener(_loadDevices);
    DatabaseHelper.deviceStateNotifier.removeListener(_loadDevices);
    _deviceSub?.cancel();
    _faceSub?.cancel();
    _bboxSub?.cancel();
    _powerSub?.cancel();
    _retryTimer?.cancel();
    _bboxClearTimer?.cancel();
    super.dispose();
  }

  Future<void> _connectMQTT() async {
    await MQTTService().connect();
    if (!mounted) return;
    MQTTService().resubscribeState();

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
        DatabaseHelper.instance.updateDeviceState(room, state, userId: AuthService.instance.userId);
      }
    });

    _faceSub = MQTTService().faceRecognitionStream.listen((event) {
      if (!mounted) return;
      final topic = event['topic'] as String;
      final data  = event['data'] as Map<String, dynamic>;
      if (topic == AppConfig.topicFaceResult && (data['matched'] as bool? ?? false)) {
        final name = data['name'] as String? ?? '';
        _showBanner('Xin chào $name! Chào mừng về nhà', AppColors.success);
      } else if (topic == AppConfig.topicFaceAlert) {
        _showBanner('CẢNH BÁO: Phát hiện người lạ!', AppColors.error);
      }
    });

    _powerSub = MQTTService().devicePowerStream.listen((event) {
      if (!mounted) return;
      final topic = event['topic'] as String;
      final data  = event['data'] as Map<String, dynamic>;
      final parts = topic.split('/');
      if (parts.length >= 4) {
        final room = parts[3];
        final watt = (data['watt'] as num?)?.toDouble() ?? 0;
        setState(() => _lightWatts[room] = watt);
        DatabaseHelper.instance.updateDeviceWatt(room, watt, userId: AuthService.instance.userId);
      }
    });

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
      if (mounted && DeviceConfigService.instance.hasEsp32Ip) {
        setState(() => _streamKey = UniqueKey());
      }
    });
  }

  void _toggleLight(String room, bool v) {
    setState(() => _lightStates[room] = v);
    MQTTService().controlLight(room, v);
    DatabaseHelper.instance.updateDeviceState(room, v ? 'ON' : 'OFF', userId: AuthService.instance.userId);
  }

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
  double get _totalWatt {
    final validRooms = _lights.map((d) => d['room'] as String).toSet();
    return _lightWatts.entries
        .where((e) => validRooms.contains(e.key))
        .fold(0.0, (a, b) => a + b.value);
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Chào buổi sáng';
    if (h < 17) return 'Chào buổi chiều';
    return 'Chào buổi tối';
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(ac)),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildRoomsRow(ac)),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildCameraPreview(ac)),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildSectionTitle('Điều khiển nhanh', ac)),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            SliverToBoxAdapter(child: _buildDeviceToggles(ac)),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AC ac) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        children: [
          ValueListenableBuilder<String?>(
            valueListenable: AvatarService.instance,
            builder: (_, path, __) {
              final img = AvatarService.instance.imageProvider;
              return GestureDetector(
                onTap: () async => AvatarService.instance.pickFromGallery(),
                child: Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: ac.accentDim, width: 2),
                    color: ac.accentDim,
                    image: img != null
                        ? DecorationImage(image: img, fit: BoxFit.cover)
                        : null,
                  ),
                  child: img == null
                      ? Center(
                          child: Text(
                            AuthService.instance.userName.isNotEmpty
                                ? AuthService.instance.userName[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                                color: ac.accentLight,
                                fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                        )
                      : null,
                ),
              );
            },
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_greeting, style: TextStyle(color: ac.textSecondary, fontSize: 13)),
                Text(AuthService.instance.userName,
                    style: TextStyle(color: ac.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          IconButton(
            onPressed: _loadDevices,
            icon: Icon(Icons.refresh_rounded, color: ac.iconMuted, size: 22),
          ),
          ListenableBuilder(
            listenable: _notifSvc,
            builder: (_, __) {
              final count = _notifSvc.unreadCount;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const _NotifPage())),
                    icon: Icon(
                      count > 0
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_rounded,
                      color: count > 0 ? Colors.orangeAccent : ac.textSecondary,
                      size: 26,
                    ),
                  ),
                  if (count > 0)
                    Positioned(
                      right: 4, top: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          count > 9 ? '9+' : '$count',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Cửa trước', style: TextStyle(color: ac.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
              Row(
                children: [
                  GestureDetector(
                    onTap: _reconnectStream,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: ac.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.refresh_rounded, color: ac.iconMuted, size: 16),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: ac.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ac.error.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 6, height: 6,
                            decoration: BoxDecoration(color: ac.error, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Text('LIVE', style: TextStyle(color: ac.error, fontSize: 10,
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
                  if (DeviceConfigService.instance.hasEsp32Ip)
                    LiveMjpeg(
                      key: _streamKey,
                      stream: AppConfig.streamUrl,
                      error: (ctx, err, stack) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _onStreamError());
                        return _buildCamOffline(ac);
                      },
                    )
                  else
                    _buildCamOffline(ac),
                  if (_faceBbox != null)
                    Positioned.fill(
                      child: CustomPaint(painter: _FaceBoxPainter(_faceBbox!)),
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

  Widget _buildCamOffline(AC ac) => Container(
    color: ac.cardElevated,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.videocam_off_rounded, color: ac.iconFaint, size: 40),
        const SizedBox(height: 8),
        Text('Camera offline\nVào Devices → BLE WiFi Setup để kết nối ESP32',
            textAlign: TextAlign.center,
            style: TextStyle(color: ac.iconFaint, fontSize: 11)),
      ],
    ),
  );

  Widget _buildSectionTitle(String title, AC ac) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: Text(title, style: TextStyle(color: ac.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
  );

  Widget _buildRoomsRow(AC ac) {
    final roomKeys = _lights.map((d) => d['room'] as String).toSet().toList();
    final allItems = <_RoomData>[
      ...roomKeys.map((room) {
        final isOn = _lightStates[room] ?? false;
        final label = _roomLabel(room);
        final icon = _roomIcon(room);
        return _RoomData(label, icon, ac.lightColor, isOn ? 1 : 0, room: room);
      }),
      _RoomData('Cửa chính', Icons.door_front_door_rounded,
          _doorLocked ? ac.success : ac.warning, _doorLocked ? 1 : 0),
    ];

    if (allItems.length == 1) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: ac.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: ac.border),
          ),
          child: Row(
            children: [
              Icon(Icons.lightbulb_outline_rounded, color: ac.iconFaint, size: 28),
              const SizedBox(width: 14),
              Text('Chưa có đèn nào được kết nối\nVào Devices → + để thêm thiết bị',
                  style: TextStyle(color: ac.textSecondary, fontSize: 12)),
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
        itemBuilder: (ctx, i) => _buildRoomCard(allItems[i], ac),
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

  Widget _buildRoomCard(_RoomData room, AC ac) {
    final isOn = room.activeDevices > 0;
    return Container(
      width: 115,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isOn ? ac.cardElevated : ac.card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: isOn ? room.color.withOpacity(0.35) : ac.border),
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
            child: Icon(room.icon, color: isOn ? room.color : ac.iconMuted, size: 20),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(room.name, style: TextStyle(color: ac.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                isOn ? 'Đang bật' : 'Đã tắt',
                style: TextStyle(color: isOn ? room.color : ac.textSecondary, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceToggles(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          if (_lights.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: ac.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: ac.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: ac.iconFaint, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Chưa có thiết bị đèn nào.\nVào tab Devices → + để thêm.',
                      style: TextStyle(color: ac.textSecondary, fontSize: 12))),
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
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildToggleCard(ac,
                d['name'] as String, subtitle,
                Icons.lightbulb_rounded, ac.lightColor,
                isOn, (v) => _toggleLight(room, v),
                onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => LivingRoomLightScreen(room: room))),
              ),
            );
          }),
          _buildToggleCard(ac,
            'Khoá cửa chính', _doorLocked ? 'Đang khoá · an toàn' : 'Đang mở · chú ý!',
            _doorLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            _doorLocked ? ac.success : ac.warning,
            _doorLocked, _toggleDoor,
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard(
    AC ac,
    String title, String subtitle, IconData icon, Color color,
    bool isActive, ValueChanged<bool> onChanged, {VoidCallback? onTap}
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isActive ? ac.cardElevated : ac.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isActive ? color.withOpacity(0.25) : ac.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Material(
              color: Colors.transparent,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20), bottomLeft: Radius.circular(20),
              ),
              child: InkWell(
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), bottomLeft: Radius.circular(20),
                ),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: color.withOpacity(isActive ? 0.18 : 0.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(icon, color: isActive ? color : ac.iconMuted, size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: TextStyle(color: ac.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Switch(
              value: isActive,
              onChanged: onChanged,
              activeColor: color,
              activeTrackColor: color.withOpacity(0.3),
              inactiveThumbColor: ac.iconMuted,
              inactiveTrackColor: ac.border,
            ),
          ),
        ],
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

    final cornerLen = w * 0.25;
    canvas.drawLine(Offset(x, y), Offset(x + cornerLen, y), paint);
    canvas.drawLine(Offset(x, y), Offset(x, y + cornerLen), paint);
    canvas.drawLine(Offset(x + w, y), Offset(x + w - cornerLen, y), paint);
    canvas.drawLine(Offset(x + w, y), Offset(x + w, y + cornerLen), paint);
    canvas.drawLine(Offset(x, y + h), Offset(x + cornerLen, y + h), paint);
    canvas.drawLine(Offset(x, y + h), Offset(x, y + h - cornerLen), paint);
    canvas.drawLine(Offset(x + w, y + h), Offset(x + w - cornerLen, y + h), paint);
    canvas.drawLine(Offset(x + w, y + h), Offset(x + w, y + h - cornerLen), paint);
  }

  @override
  bool shouldRepaint(_FaceBoxPainter old) => old.bbox != bbox;
}

class _NotifPage extends StatelessWidget {
  const _NotifPage();
  @override
  Widget build(BuildContext context) => const NotificationsScreen();
}
