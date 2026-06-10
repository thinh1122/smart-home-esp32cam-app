import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import '../../widgets/live_mjpeg.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/device_config_service.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../data/models/log_model.dart';
import '../members/members_screen.dart';

class FrontDoorCamScreen extends StatefulWidget {
  const FrontDoorCamScreen({super.key});

  @override
  State<FrontDoorCamScreen> createState() => _FrontDoorCamScreenState();
}

class _FrontDoorCamScreenState extends State<FrontDoorCamScreen> {
  List<LogEntry> _logs = [];

  Key _streamKey = UniqueKey();
  bool _isStreamActive = true;
  bool _isStreamConnected = false;
  Timer? _retryTimer;

  List<Map<String, dynamic>> _recognizedFaces = [];

  StreamSubscription? _mqttFaceSub;

  @override
  void initState() {
    super.initState();
    _loadData();
    _listenMQTT();
    DeviceConfigService.instance.aiServerNotifier.addListener(_onAiServerChanged);
  }

  void _onAiServerChanged() {
    if (mounted) setState(() => _streamKey = UniqueKey());
  }

  @override
  void dispose() {
    DeviceConfigService.instance.aiServerNotifier.removeListener(_onAiServerChanged);
    _mqttFaceSub?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  void _listenMQTT() {
    MQTTService().connect().then((_) {
      _mqttFaceSub = MQTTService().faceRecognitionStream.listen((event) {
        final topic = event['topic'] as String;
        final data  = event['data']  as Map<String, dynamic>;

        if (topic == AppConfig.topicFaceAlert) {
          DatabaseHelper.instance.addLog('Cảnh báo: Người lạ', 'Phát hiện khuôn mặt không xác định tại cửa');
          if (mounted) {
            _showBanner('CẢNH BÁO: Phát hiện người lạ!', AppColors.error);
            setState(() => _recognizedFaces = [data]);
          }
        } else if (topic == AppConfig.topicFaceResult) {
          final matched = data['matched'] as bool? ?? false;
          if (matched) {
            final name       = data['name'] as String? ?? '';
            final confidence = data['confidence'] != null
                ? '${((data['confidence'] as num) * 100).toStringAsFixed(0)}%'
                : '';
            DatabaseHelper.instance.addLog('Nhận diện thành công', '$name tại cửa · $confidence');
          }
          if (mounted) {
            _showBanner(
              matched ? 'Xin chào ${data['name']}! Chào mừng về nhà 👋' : 'Người lạ tại cửa',
              matched ? AppColors.success : AppColors.error,
            );
            setState(() => _recognizedFaces = [data]);
            Future.delayed(const Duration(seconds: 8), () {
              if (mounted) setState(() => _recognizedFaces = []);
            });
          }
        }

        DatabaseHelper.instance.getLogs(limit: 30).then((logs) {
          if (mounted) setState(() => _logs = logs.map(LogEntry.fromMap).toList());
        });
      });
    });
  }

  void _reconnectStream() {
    _retryTimer?.cancel();
    setState(() {
      _streamKey = UniqueKey();
      _isStreamConnected = false;
    });
  }

  void _onStreamError() {
    if (!mounted) return;
    setState(() => _isStreamConnected = false);
    _retryTimer?.cancel();
    _retryTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && AppConfig.streamUrl.isNotEmpty) {
        setState(() => _streamKey = UniqueKey());
      }
    });
  }

  void _showBanner(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
        backgroundColor: color,
        duration: const Duration(seconds: 4),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ));
  }

  Future<void> _loadData() async {
    final logs = await DatabaseHelper.instance.getLogs(limit: 30);
    if (!mounted) return;
    if (logs.isEmpty) {
      await DatabaseHelper.instance.addLog('Hệ thống khởi động', 'Smart Home ESP32-CAM online');
      final fresh = await DatabaseHelper.instance.getLogs(limit: 30);
      if (mounted) setState(() => _logs = fresh.map(LogEntry.fromMap).toList());
    } else {
      setState(() => _logs = logs.map(LogEntry.fromMap).toList());
    }
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
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildCameraFeed(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildActionButtons(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
            SliverToBoxAdapter(child: _buildActivitySection(ac)),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AC ac) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Front Door', style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text('Security Camera', style: TextStyle(color: ac.textSecondary, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              GestureDetector(
                onTap: _reconnectStream,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ac.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ac.border),
                  ),
                  child: Icon(Icons.refresh_rounded, color: ac.textSecondary, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.error.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7, height: 7,
                      decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    const Text('LIVE', style: TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCameraFeed(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 240,
          color: ac.cardElevated,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_isStreamActive && AppConfig.streamUrl.isNotEmpty)
                LiveMjpeg(
                  key: _streamKey,
                  stream: AppConfig.streamUrl,
                  error: (ctx, err, stack) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => _onStreamError());
                    return _buildStreamError(ac);
                  },
                ),

              Positioned(top: 14, left: 14, child: _cornerMark(top: true, left: true)),
              Positioned(top: 14, right: 14, child: _cornerMark(top: true, left: false)),
              Positioned(bottom: 14, left: 14, child: _cornerMark(top: false, left: true)),
              Positioned(bottom: 14, right: 14, child: _cornerMark(top: false, left: false)),

              Positioned(
                top: 36, left: 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _glassPill(Icons.wifi_rounded, 'Direct Stream', AppColors.info),
                    const SizedBox(height: 8),
                    _glassPill(Icons.memory_rounded, 'ESP32-CAM', Colors.white60),
                  ],
                ),
              ),

              if (_recognizedFaces.isNotEmpty)
                Positioned(
                  bottom: 14, left: 14, right: 14,
                  child: _buildFaceOverlay(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStreamError(AC ac) {
    final hasIp = DeviceConfigService.instance.hasEsp32Ip;
    return Container(
      color: ac.cardElevated,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(hasIp ? Icons.videocam_off_rounded : Icons.wifi_off_rounded, color: ac.iconFaint, size: 44),
          const SizedBox(height: 12),
          Text(
            hasIp ? 'Camera offline' : 'Chưa cấu hình ESP32',
            style: TextStyle(color: ac.iconMuted, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            hasIp ? AppConfig.streamUrl : 'Vào Devices → BLE WiFi Setup để kết nối ESP32',
            style: TextStyle(color: ac.iconFaint, fontSize: 10),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _reconnectStream,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: ac.accentDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: ac.accentLight, size: 16),
                  const SizedBox(width: 8),
                  Text('Reconnect', style: TextStyle(color: ac.accentLight, fontSize: 13, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFaceOverlay() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _faceOverlayColor.withOpacity(0.25),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _faceOverlayColor.withOpacity(0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_faceOverlayIcon, color: _faceOverlayColor, size: 20),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _recognizedFaces.first['name'] as String,
                      style: TextStyle(color: _faceOverlayColor, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    if ((_recognizedFaces.first['matched'] as bool?) == true)
                      Text(
                        'Độ chính xác: ${((_recognizedFaces.first['confidence'] as double) * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(color: Colors.white60, fontSize: 10),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color get _faceOverlayColor {
    final matched = _recognizedFaces.first['matched'];
    if (matched == null) return AppColors.info;
    return (matched as bool) ? AppColors.success : AppColors.warning;
  }

  IconData get _faceOverlayIcon {
    final matched = _recognizedFaces.first['matched'];
    if (matched == null) return Icons.face_retouching_natural;
    return (matched as bool) ? Icons.check_circle_rounded : Icons.warning_amber_rounded;
  }

  Widget _glassPill(IconData icon, String text, Color iconColor) => ClipRRect(
    borderRadius: BorderRadius.circular(20),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.35),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: iconColor, size: 13),
            const SizedBox(width: 6),
            Text(text, style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    ),
  );

  Widget _cornerMark({required bool top, required bool left}) => Container(
    width: 14, height: 14,
    decoration: BoxDecoration(
      border: Border(
        top: top ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        bottom: !top ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        left: left ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
        right: !left ? const BorderSide(color: Colors.white60, width: 2) : BorderSide.none,
      ),
    ),
  );

  Widget _buildActionButtons(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _actionBtn(ac, 'Members', Icons.people_alt_rounded, ac.accentLight, isPrimary: true, onTap: _goToMembers)),
          const SizedBox(width: 12),
          Expanded(child: _actionBtn(ac, 'Snapshot', Icons.camera_alt_rounded, AppColors.info, onTap: _takeSnapshot)),
          const SizedBox(width: 12),
          Expanded(child: _actionBtn(ac, 'Alarm', Icons.campaign_rounded, AppColors.warning)),
        ],
      ),
    );
  }

  Widget _actionBtn(AC ac, String label, IconData icon, Color color, {bool isPrimary = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isPrimary ? ac.accentDim : ac.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isPrimary ? ac.accentLight.withOpacity(0.4) : ac.border),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: isPrimary ? ac.accentLight : ac.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: ac.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: ac.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Recent Activity', style: TextStyle(color: ac.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: ac.cardElevated, borderRadius: BorderRadius.circular(10)),
                    child: Icon(Icons.filter_list_rounded, color: ac.textSecondary, size: 16),
                  ),
                ],
              ),
            ),
            if (_logs.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text('No activity yet', style: TextStyle(color: ac.textSecondary)),
              )
            else
              ..._logs.take(8).map((log) => _buildLogItem(ac, log)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(AC ac, LogEntry log) {
    final color = log.isSuccess ? AppColors.success : log.isWarning ? AppColors.warning : ac.textSecondary;
    final icon = log.isSuccess ? Icons.check_circle_rounded : log.isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ac.cardElevated,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(log.action, style: TextStyle(color: ac.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(log.detail, style: TextStyle(color: ac.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(log.timeString, style: TextStyle(color: ac.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  void _goToMembers() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const MembersScreen()));
  }

  Future<void> _takeSnapshot() async {
    try {
      final res = await http.get(Uri.parse(AppConfig.captureUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final b64 = base64Encode(res.bodyBytes);
        await DatabaseHelper.instance.addLog('Snapshot', 'Chụp ảnh thủ công');
        if (mounted) _showBanner('Snapshot đã lưu', AppColors.success);
        if (mounted) {
          final ac = AC.of(context);
          showDialog(
            context: context,
            builder: (_) => Dialog(
              backgroundColor: ac.card,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.memory(res.bodyBytes, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 12),
                    TextButton(onPressed: () => Navigator.pop(context), child: Text('Đóng', style: TextStyle(color: ac.accentLight))),
                  ],
                ),
              ),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) _showBanner('Không thể chụp ảnh', AppColors.error);
    }
  }
}
