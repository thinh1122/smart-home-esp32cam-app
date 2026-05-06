import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/config/app_config.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/device_config_service.dart';
import '../../widgets/live_mjpeg.dart';

class HomeDashboard extends StatefulWidget {
  const HomeDashboard({super.key});

  @override
  State<HomeDashboard> createState() => _HomeDashboardState();
}

class _HomeDashboardState extends State<HomeDashboard> {
  // Device states — updated via MQTT
  bool _livingRoomLight = false;
  bool _bedroomLight = false;
  bool _kitchenLight = false;
  bool _doorLocked = true;
  bool _mqttConnected = false;
  Key _streamKey = UniqueKey();
  Timer? _retryTimer;

  // Trạng thái nhận diện khuôn mặt mới nhất từ MQTT
  Map<String, dynamic>? _lastFaceEvent;
  Timer? _faceEventClearTimer;

  StreamSubscription? _deviceSub;
  StreamSubscription? _faceSub;

  @override
  void initState() {
    super.initState();
    _connectMQTT();
    DeviceConfigService.instance.aiServerNotifier.addListener(_onEsp32Changed);
  }

  void _onEsp32Changed() {
    if (mounted) setState(() => _streamKey = UniqueKey());
  }

  @override
  void dispose() {
    DeviceConfigService.instance.aiServerNotifier.removeListener(_onEsp32Changed);
    _deviceSub?.cancel();
    _faceSub?.cancel();
    _retryTimer?.cancel();
    _faceEventClearTimer?.cancel();
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
      setState(() {
        if (topic.contains('living_room')) _livingRoomLight = state == 'ON';
        if (topic.contains('bedroom')) _bedroomLight = state == 'ON';
        if (topic.contains('kitchen')) _kitchenLight = state == 'ON';
        if (topic.contains('door')) _doorLocked = state == 'LOCKED';
      });
    });

    // Lắng nghe MQTT nhận diện khuôn mặt
    _faceSub = MQTTService().faceRecognitionStream.listen((event) {
      if (!mounted) return;
      final topic = event['topic'] as String;
      final data = event['data'] as Map<String, dynamic>;
      setState(() => _lastFaceEvent = {'topic': topic, ...data});
      // Xóa thông báo sau 10 giây
      _faceEventClearTimer?.cancel();
      _faceEventClearTimer = Timer(const Duration(seconds: 10), () {
        if (mounted) setState(() => _lastFaceEvent = null);
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
    setState(() {
      if (room == 'living_room') _livingRoomLight = v;
      if (room == 'bedroom') _bedroomLight = v;
      if (room == 'kitchen') _kitchenLight = v;
    });
    MQTTService().controlLight(room, v);
  }

  // Toggle cửa → publish MQTT
  void _toggleDoor(bool v) {
    setState(() => _doorLocked = v);
    MQTTService().controlDoor('front_door', v ? 'LOCK' : 'UNLOCK');
  }

  int get _lightsOn => [_livingRoomLight, _bedroomLight, _kitchenLight].where((v) => v).length;

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
            child: SizedBox(
              height: 190, width: double.infinity,
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
                  Positioned(top: 12, left: 12, child: _cornerMark(top: true, left: true)),
                  Positioned(top: 12, right: 12, child: _cornerMark(top: true, left: false)),
                  Positioned(bottom: 12, left: 12, child: _cornerMark(top: false, left: true)),
                  Positioned(bottom: 12, right: 12, child: _cornerMark(top: false, left: false)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cornerMark({required bool top, required bool left}) => Container(
    width: 16, height: 16,
    decoration: BoxDecoration(
      border: Border(
        top: top ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        bottom: !top ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        left: left ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        right: !left ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
      ),
    ),
  );

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
    final rooms = [
      _RoomData('Phòng khách', Icons.weekend_rounded, AppColors.accentLight, _livingRoomLight ? 1 : 0),
      _RoomData('Phòng ngủ', Icons.bed_rounded, AppColors.lightColor, _bedroomLight ? 1 : 0),
      _RoomData('Nhà bếp', Icons.kitchen_rounded, AppColors.climateColor, _kitchenLight ? 1 : 0),
      _RoomData('Cửa chính', Icons.door_front_door_rounded,
          _doorLocked ? AppColors.success : AppColors.warning, _doorLocked ? 1 : 0),
    ];
    return SizedBox(
      height: 120,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemCount: rooms.length,
        itemBuilder: (ctx, i) => _buildRoomCard(rooms[i]),
      ),
    );
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
          _buildToggleCard(
            'Đèn phòng khách', 'Trần · điều khiển qua MQTT',
            Icons.lightbulb_rounded, AppColors.lightColor,
            _livingRoomLight, (v) => _toggleLight('living_room', v),
          ),
          const SizedBox(height: 12),
          _buildToggleCard(
            'Đèn phòng ngủ', 'Đèn ngủ · điều khiển qua MQTT',
            Icons.bed_rounded, AppColors.accentLight,
            _bedroomLight, (v) => _toggleLight('bedroom', v),
          ),
          const SizedBox(height: 12),
          _buildToggleCard(
            'Đèn nhà bếp', 'Bếp · điều khiển qua MQTT',
            Icons.kitchen_rounded, AppColors.climateColor,
            _kitchenLight, (v) => _toggleLight('kitchen', v),
          ),
          const SizedBox(height: 12),
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
    bool isActive, ValueChanged<bool> onChanged,
  ) {
    return Container(
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
    );
  }
}

class _RoomData {
  final String name;
  final IconData icon;
  final Color color;
  final int activeDevices;
  const _RoomData(this.name, this.icon, this.color, this.activeDevices);
}
