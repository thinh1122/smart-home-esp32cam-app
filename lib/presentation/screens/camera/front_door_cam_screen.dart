import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'dart:convert';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/database_helper.dart';
import '../../../data/models/member_model.dart';
import '../../../data/models/log_model.dart';

class FrontDoorCamScreen extends StatefulWidget {
  const FrontDoorCamScreen({super.key});

  @override
  State<FrontDoorCamScreen> createState() => _FrontDoorCamScreenState();
}

class _FrontDoorCamScreenState extends State<FrontDoorCamScreen> {
  List<Member> _members = [];
  List<LogEntry> _logs = [];

  // Stream state
  Key _streamKey = UniqueKey(); // reset to force MJPEG reconnect
  bool _isStreamActive = true;
  bool _isStreamConnected = false; // tracked via error callback

  // Face recognition state machine
  List<Map<String, dynamic>> _recognizedFaces = [];
  Timer? _recognizeTimer;
  bool _isRecognizing = false;
  bool _isCapturing = false;
  DateTime? _faceDetectedTime;
  bool _faceStable = false;
  int _stableFaceCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _recognizeTimer = Timer.periodic(
      Duration(seconds: AppConfig.recognitionIntervalSeconds),
      (_) { if (_isStreamActive && !_isCapturing) _sendFrameForRecognition(); },
    );
  }

  @override
  void dispose() {
    _recognizeTimer?.cancel();
    super.dispose();
  }

  // ── Reconnect stream ──────────────────────────────────────────────────────
  void _reconnectStream() {
    setState(() {
      _streamKey = UniqueKey();
      _isStreamConnected = false;
    });
  }

  // ── Face recognition pipeline ─────────────────────────────────────────────
  Future<void> _sendFrameForRecognition() async {
    if (_isRecognizing || _isCapturing) return;
    _isRecognizing = true;

    try {
      // Step 1: Grab test frame
      final testRes = await http
          .get(Uri.parse(AppConfig.captureUrl))
          .timeout(const Duration(seconds: 3));
      if (testRes.statusCode != 200) return;

      final testBase64 = base64Encode(testRes.bodyBytes);

      // Step 2: Check for motion + face
      final checkRes = await http
          .post(
            Uri.parse(AppConfig.recognizeUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': testBase64}),
          )
          .timeout(const Duration(seconds: 4));
      if (checkRes.statusCode != 200) return;

      final checkJson = jsonDecode(checkRes.body);
      final hasMotion = checkJson['motion'] as bool? ?? false;
      final faceCount = checkJson['face_count'] as int? ?? 0;
      final faces = List<Map<String, dynamic>>.from(
        (checkJson['faces'] as List? ?? []).map((f) => Map<String, dynamic>.from(f)),
      );

      if (!hasMotion || faceCount == 0) {
        // Reset stable tracking
        _faceDetectedTime = null;
        _faceStable = false;
        _stableFaceCount = 0;
        if (mounted && _recognizedFaces.isNotEmpty) {
          setState(() => _recognizedFaces = []);
        }
        return;
      }

      // Step 3: Wait for face to be stable for 2 seconds
      final now = DateTime.now();
      if (_faceDetectedTime == null) {
        _faceDetectedTime = now;
        _stableFaceCount = 1;
        return;
      }

      final elapsed = now.difference(_faceDetectedTime!);
      _stableFaceCount++;

      if (elapsed.inSeconds < AppConfig.faceStableThresholdSeconds) {
        // Show countdown overlay
        if (mounted && faces.isNotEmpty) {
          final remaining = AppConfig.faceStableThresholdSeconds - elapsed.inSeconds;
          setState(() {
            _recognizedFaces = [{
              'matched': null,
              'name': 'Hold still... ${remaining}s',
              'confidence': 0.0,
            }];
          });
        }
        return;
      }

      if (_faceStable || _isCapturing) return;
      _faceStable = true;
      _isCapturing = true;

      // Show "processing" overlay
      if (mounted) {
        setState(() {
          _recognizedFaces = [{'matched': null, 'name': 'Recognizing...', 'confidence': 0.0}];
        });
      }

      // Step 4: Capture 4 frames (reuse test frame as first)
      final capturedImages = <String>[testBase64];
      for (int i = 1; i < 4; i++) {
        try {
          final r = await http
              .get(Uri.parse(AppConfig.captureUrl))
              .timeout(const Duration(seconds: 2));
          if (r.statusCode == 200) capturedImages.add(base64Encode(r.bodyBytes));
        } catch (_) {}
        if (i < 3) await Future.delayed(const Duration(milliseconds: 500));
      }

      // Step 5: Send all frames for comparison
      final recRes = await http
          .post(
            Uri.parse(AppConfig.autoCaptureCompareUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'images_base64': capturedImages}),
          )
          .timeout(const Duration(seconds: 12));

      if (recRes.statusCode != 200) return;
      final recJson = jsonDecode(recRes.body);

      if (recJson['matched'] == true) {
        final name = recJson['name'] as String;
        final id = recJson['id'] as String? ?? '';
        final confidence = (recJson['confidence'] as num).toDouble();
        final pct = (confidence * 100).toStringAsFixed(0);

        await DatabaseHelper.instance.addLog(
          'Nhận diện thành công',
          '$name${id.isNotEmpty ? " (ID: $id)" : ""} tại cửa · $pct%',
        );

        if (mounted) {
          _showBanner('Xin chào $name! Chào mừng về nhà 👋', AppColors.success);
          setState(() {
            _recognizedFaces = [{'matched': true, 'name': name, 'id': id, 'confidence': confidence}];
          });
        }
      } else {
        await DatabaseHelper.instance.addLog(
          'Cảnh báo: Người lạ',
          'Phát hiện khuôn mặt không xác định tại cửa chính',
        );
        if (mounted) {
          _showBanner('CẢNH BÁO: Phát hiện người lạ tại cửa!', AppColors.error);
          setState(() {
            _recognizedFaces = [{'matched': false, 'name': 'Unknown', 'confidence': 0.0}];
          });
        }
      }

      // Reload logs
      if (mounted) {
        final updatedLogs = await DatabaseHelper.instance.getLogs(limit: 30);
        if (mounted) {
          setState(() => _logs = updatedLogs.map(LogEntry.fromMap).toList());
        }
      }
    } catch (e) {
      debugPrint('Recognition error: $e');
    } finally {
      _isRecognizing = false;
      _faceDetectedTime = null;
      _faceStable = false;
      _stableFaceCount = 0;
      _isCapturing = false;
    }
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

  // ── Data loading ──────────────────────────────────────────────────────────
  Future<void> _loadData() async {
    final members = await DatabaseHelper.instance.getAllMembers();
    final logs = await DatabaseHelper.instance.getLogs(limit: 30);
    if (!mounted) return;
    setState(() {
      _members = members.map(Member.fromMap).toList();
      _logs = logs.map(LogEntry.fromMap).toList();
    });
    if (_members.isEmpty) _seedData();
  }

  Future<void> _seedData() async {
    await DatabaseHelper.instance.insertMember({'id': '0', 'name': 'Nguyễn Phùng Thịnh', 'role': 'Admin', 'avatar': 'https://i.pravatar.cc/150?img=11'});
    await DatabaseHelper.instance.insertMember({'id': '1', 'name': 'Mẹ', 'role': 'Thành viên', 'avatar': 'https://i.pravatar.cc/150?img=43'});
    await DatabaseHelper.instance.insertMember({'id': '2', 'name': 'Bố', 'role': 'Thành viên', 'avatar': 'https://i.pravatar.cc/150?img=52'});
    await DatabaseHelper.instance.addLog('Hệ thống khởi động', 'Smart Home ESP32-CAM online');
    _loadData();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildCameraFeed()),
            SliverToBoxAdapter(child: const SizedBox(height: 20)),
            SliverToBoxAdapter(child: _buildActionButtons()),
            SliverToBoxAdapter(child: const SizedBox(height: 24)),
            SliverToBoxAdapter(child: _buildActivitySection()),
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Front Door', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              SizedBox(height: 2),
              Text('Security Camera', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
          Row(
            children: [
              // Reconnect button
              GestureDetector(
                onTap: _reconnectStream,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Icon(Icons.refresh_rounded, color: Colors.white70, size: 20),
                ),
              ),
              const SizedBox(width: 10),
              // Live badge
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

  Widget _buildCameraFeed() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Container(
          height: 240,
          color: AppColors.cardElevated,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // MJPEG stream — key forces full rebuild on reconnect
              if (_isStreamActive)
                Mjpeg(
                  key: _streamKey,
                  isLive: true,
                  stream: AppConfig.streamUrl,
                  error: (ctx, err, stack) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && _isStreamConnected) setState(() => _isStreamConnected = false);
                    });
                    return _buildStreamError();
                  },
                ),

              // Corner reticle marks
              Positioned(top: 14, left: 14, child: _cornerMark(top: true, left: true)),
              Positioned(top: 14, right: 14, child: _cornerMark(top: true, left: false)),
              Positioned(bottom: 14, left: 14, child: _cornerMark(top: false, left: true)),
              Positioned(bottom: 14, right: 14, child: _cornerMark(top: false, left: false)),

              // Info pills top-left
              Positioned(
                top: 36, left: 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _glassPill(Icons.wifi_rounded, 'Relay Connected', AppColors.info),
                    const SizedBox(height: 8),
                    _glassPill(Icons.memory_rounded, 'ESP32-CAM', Colors.white60),
                  ],
                ),
              ),

              // Face recognition result overlay
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

  Widget _buildStreamError() {
    return Container(
      color: AppColors.cardElevated,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 44),
          const SizedBox(height: 12),
          const Text('Camera offline', style: TextStyle(color: Colors.white54, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(AppConfig.streamUrl, style: const TextStyle(color: Colors.white30, fontSize: 10)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: _reconnectStream,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.accentDim,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded, color: AppColors.accentLight, size: 16),
                  SizedBox(width: 8),
                  Text('Reconnect', style: TextStyle(color: AppColors.accentLight, fontSize: 13, fontWeight: FontWeight.bold)),
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

  Widget _buildActionButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(child: _actionBtn('Members', Icons.people_alt_rounded, AppColors.accentLight, isPrimary: true, onTap: () => _showMembersSheet())),
          const SizedBox(width: 12),
          Expanded(child: _actionBtn('Snapshot', Icons.camera_alt_rounded, AppColors.info)),
          const SizedBox(width: 12),
          Expanded(child: _actionBtn('Alarm', Icons.campaign_rounded, AppColors.warning)),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, {bool isPrimary = false, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: isPrimary ? AppColors.accentDim : AppColors.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isPrimary ? AppColors.accentLight.withOpacity(0.4) : Colors.white10),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(color: isPrimary ? AppColors.accentLight : Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildActivitySection() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Recent Activity', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.filter_list_rounded, color: Colors.white70, size: 16),
                  ),
                ],
              ),
            ),
            if (_logs.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text('No activity yet', style: TextStyle(color: AppColors.textSecondary)),
              )
            else
              ..._logs.take(8).map((log) => _buildLogItem(log)),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildLogItem(LogEntry log) {
    final color = log.isSuccess ? AppColors.success : log.isWarning ? AppColors.warning : AppColors.textSecondary;
    final icon = log.isSuccess ? Icons.check_circle_rounded : log.isWarning ? Icons.warning_amber_rounded : Icons.info_outline_rounded;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                Text(log.action, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(log.detail, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(log.timeString, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }

  // ── Members bottom sheet ───────────────────────────────────────────────────
  void _showMembersSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Registered Faces', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    GestureDetector(
                      onTap: () { Navigator.pop(context); _showAddMemberDialog(); },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(color: AppColors.accentDim, shape: BoxShape.circle),
                        child: const Icon(Icons.add, color: AppColors.accentLight, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _members.length,
                  itemBuilder: (ctx, i) => _buildMemberTile(_members[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMemberTile(Member member) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundImage: member.imageProvider,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(member.name, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: AppColors.accentDim, borderRadius: BorderRadius.circular(8)),
                      child: Text('ID: ${member.id}', style: const TextStyle(color: AppColors.accentLight, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(member.role, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _deleteMember(member),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: AppColors.error.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: const Icon(Icons.delete_outline_rounded, color: AppColors.error, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMember(Member member) async {
    try {
      await http.post(
        Uri.parse(AppConfig.deleteUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'id': member.id, 'name': member.name}),
      ).timeout(const Duration(seconds: 5));
    } catch (_) {}
    await DatabaseHelper.instance.deleteMember(member.id);
    await DatabaseHelper.instance.addLog('Xoá thành viên', 'Đã gỡ quyền: ${member.name}');
    if (mounted) Navigator.pop(context);
    await _loadData();
    if (mounted) _showMembersSheet();
  }

  // ── Add member dialog ─────────────────────────────────────────────────────
  void _showAddMemberDialog() {
    final nameCtrl = TextEditingController();
    final idCtrl = TextEditingController(text: _members.length.toString());

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Add Face ID', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _textField(idCtrl, 'ID', Icons.tag_rounded),
            const SizedBox(height: 12),
            _textField(nameCtrl, 'Name', Icons.person_rounded),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            onPressed: () {
              final name = nameCtrl.text.trim();
              final id = idCtrl.text.trim();
              if (name.isEmpty || id.isEmpty) return;
              Navigator.pop(ctx);
              _startFaceCapture(id, name);
            },
            child: const Text('Next', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label, IconData icon) => TextField(
    controller: ctrl,
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.textSecondary),
      prefixIcon: Icon(icon, color: AppColors.textSecondary, size: 18),
      enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(14)),
      focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: AppColors.accentLight), borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: AppColors.surface,
    ),
  );

  // ── Face capture wizard ───────────────────────────────────────────────────
  void _startFaceCapture(String id, String name) {
    setState(() => _isStreamActive = false);

    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      int step = 0;
      String? avatarBase64;
      bool capturing = false;

      final steps = [
        'STEP 1/3 — Look straight at camera',
        'STEP 2/3 — Turn slightly to the RIGHT',
        'STEP 3/3 — Turn slightly to the LEFT',
        'Done! Tap SAVE to finish',
      ];

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => StatefulBuilder(
          builder: (ctx, setDs) => AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            contentPadding: const EdgeInsets.all(16),
            title: Text('Register: $name', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(steps[step], style: TextStyle(color: step == 3 ? AppColors.success : AppColors.info, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      height: 200, width: double.infinity,
                      child: Stack(fit: StackFit.expand, children: [
                        Mjpeg(isLive: true, stream: AppConfig.streamUrl,
                          error: (c, e, s) => const Center(child: Text('Camera offline', style: TextStyle(color: Colors.white54)))),
                        if (step == 3)
                          Container(color: Colors.black54, child: const Center(child: Icon(Icons.check_circle_rounded, color: AppColors.success, size: 64))),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (capturing)
                    const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: AppColors.info, strokeWidth: 2)),
                      SizedBox(width: 12),
                      Text('Capturing...', style: TextStyle(color: AppColors.info)),
                    ])
                  else if (step < 3)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: () async {
                          setDs(() => capturing = true);
                          try {
                            final r = await http.get(Uri.parse(AppConfig.captureUrl)).timeout(const Duration(seconds: 5));
                            if (r.statusCode == 200) {
                              final b64 = base64Encode(r.bodyBytes);
                              if (step == 0) avatarBase64 = b64;
                              await http.post(Uri.parse(AppConfig.enrollUrl),
                                headers: {'Content-Type': 'application/json'},
                                body: jsonEncode({'id': id, 'name': name, 'image_base64': b64, 'pose': step + 1}),
                              ).timeout(const Duration(seconds: 7));
                              setDs(() { step++; capturing = false; });
                            } else { setDs(() => capturing = false); }
                          } catch (_) { setDs(() => capturing = false); }
                        },
                        icon: const Icon(Icons.camera_alt_rounded, color: Colors.black, size: 22),
                        label: Text('CAPTURE ${step + 1}/3', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    )
                  else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                        onPressed: () => Navigator.pop(ctx, avatarBase64),
                        icon: const Icon(Icons.save_rounded, color: Colors.black, size: 22),
                        label: const Text('SAVE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                      ),
                    ),
                  const SizedBox(height: 4),
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel', style: TextStyle(color: AppColors.textSecondary))),
                ],
              ),
            ),
          ),
        ),
      ).then((result) {
        if (!mounted) return;
        setState(() => _isStreamActive = true);
        if (result is String) {
          final exists = _members.any((m) => m.id == id);
          if (!exists) {
            DatabaseHelper.instance.insertMember({'id': id, 'name': name, 'role': 'Face ID', 'avatar': result})
              .then((_) {
                DatabaseHelper.instance.addLog('Đăng ký khuôn mặt', '$name (ID: $id)');
                _loadData();
              });
          }
          _showBanner('Đã đăng ký khuôn mặt: $name', AppColors.success);
        }
      });
    });
  }
}
