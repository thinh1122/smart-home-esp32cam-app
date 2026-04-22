import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/services/member_sync_service.dart';
import '../../../core/theme/app_theme.dart';

class FaceEnrollScreen extends StatefulWidget {
  final String memberId;
  final String memberName;
  final String memberRole;

  const FaceEnrollScreen({
    super.key,
    required this.memberId,
    required this.memberName,
    required this.memberRole,
  });

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> with SingleTickerProviderStateMixin {
  int _currentPose = 0; // 0=thẳng, 1=phải, 2=trái
  bool _capturing = false;
  bool _done = false;
  String? _errorMsg;
  String? _avatarBase64; // lưu ảnh pose 1 làm avatar
  late AnimationController _pulseCtrl;
  late Animation<double> _pulse;

  static const _poses = [
    _PoseInfo(
      label: 'Nhìn thẳng vào camera',
      sub: 'Giữ khuôn mặt ở giữa khung hình',
      icon: Icons.face_rounded,
    ),
    _PoseInfo(
      label: 'Nghiêng đầu sang PHẢI',
      sub: 'Nhẹ nhàng, khoảng 20–30 độ',
      icon: Icons.rotate_right_rounded,
    ),
    _PoseInfo(
      label: 'Nghiêng đầu sang TRÁI',
      sub: 'Nhẹ nhàng, khoảng 20–30 độ',
      icon: Icons.rotate_left_rounded,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    if (_capturing || _done) return;
    setState(() { _capturing = true; _errorMsg = null; });

    try {
      // 1. Chụp ảnh từ ESP32
      final res = await http
          .get(Uri.parse(AppConfig.captureUrl))
          .timeout(const Duration(seconds: 6));

      if (res.statusCode != 200) {
        setState(() { _errorMsg = 'Camera không phản hồi, thử lại'; _capturing = false; });
        return;
      }

      final b64 = base64Encode(res.bodyBytes);
      if (_currentPose == 0) _avatarBase64 = b64;

      // 2. Gửi lên AI server để enroll pose này
      final error = await MemberSyncService.instance.enrollPose(
        id: widget.memberId,
        name: widget.memberName,
        role: widget.memberRole,
        imageBase64: b64,
        pose: _currentPose + 1,
        avatar: _currentPose == 0 ? b64 : (_avatarBase64 ?? ''),
      );

      if (error != null) {
        setState(() { _errorMsg = error; _capturing = false; });
        return;
      }

      // 3. Tiến sang pose tiếp theo
      if (_currentPose < 2) {
        setState(() { _currentPose++; _capturing = false; });
      } else {
        setState(() { _done = true; _capturing = false; });
      }
    } catch (e) {
      setState(() { _errorMsg = 'Lỗi: $e'; _capturing = false; });
    }
  }

  void _finish() {
    Navigator.pop(context, _avatarBase64);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white70, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đăng ký khuôn mặt', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.memberName, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          ],
        ),
      ),
      body: _done ? _buildDoneView() : _buildEnrollView(),
    );
  }

  Widget _buildEnrollView() {
    final pose = _poses[_currentPose];
    return Column(
      children: [
        // Progress bar
        _buildProgressBar(),

        // Camera feed
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Mjpeg(
                    isLive: true,
                    stream: AppConfig.streamUrl,
                    error: (c, e, s) => Container(
                      color: AppColors.cardElevated,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 40),
                            SizedBox(height: 8),
                            Text('Camera offline', style: TextStyle(color: Colors.white38)),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Face guide overlay
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulse,
                      builder: (_, __) => Transform.scale(
                        scale: _capturing ? 1.0 : _pulse.value,
                        child: _buildFaceGuide(pose.icon),
                      ),
                    ),
                  ),

                  // Pose number chip
                  Positioned(
                    top: 16, right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.accentLight.withOpacity(0.4)),
                      ),
                      child: Text(
                        '${_currentPose + 1} / 3',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  // Capturing flash
                  if (_capturing)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),

        // Instruction + button
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              children: [
                Icon(pose.icon, color: AppColors.accentLight, size: 32),
                const SizedBox(height: 10),
                Text(
                  pose.label,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                Text(
                  pose.sub,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),

                if (_errorMsg != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                        const SizedBox(width: 8),
                        Flexible(child: Text(_errorMsg!, style: const TextStyle(color: AppColors.error, fontSize: 12))),
                      ],
                    ),
                  ),
                ],

                const Spacer(),

                // Capture button
                SizedBox(
                  width: double.infinity,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: _capturing
                        ? Container(
                            key: const ValueKey('loading'),
                            height: 56,
                            decoration: BoxDecoration(
                              color: AppColors.accentDim,
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: AppColors.accentLight, strokeWidth: 2)),
                                SizedBox(width: 12),
                                Text('Đang xử lý...', style: TextStyle(color: AppColors.accentLight, fontSize: 15, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        : ElevatedButton.icon(
                            key: const ValueKey('capture'),
                            onPressed: _capture,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              minimumSize: const Size(double.infinity, 56),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              elevation: 4,
                            ),
                            icon: const Icon(Icons.camera_alt_rounded, size: 22),
                            label: Text(
                              _errorMsg != null ? 'Thử lại' : 'CHỤP POSE ${_currentPose + 1}/3',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: List.generate(3, (i) {
          final done = i < _currentPose;
          final active = i == _currentPose;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: done
                    ? AppColors.success
                    : active
                        ? AppColors.accent
                        : AppColors.surface,
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildFaceGuide(IconData poseIcon) {
    return Container(
      width: 160,
      height: 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(80),
        border: Border.all(
          color: _capturing ? AppColors.success : AppColors.accentLight.withOpacity(0.7),
          width: 2.5,
        ),
      ),
      child: _capturing
          ? const Center(child: Icon(Icons.check_circle_outline_rounded, color: AppColors.success, size: 48))
          : null,
    );
  }

  Widget _buildDoneView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.success.withOpacity(0.5), width: 2),
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            const Text('Đăng ký thành công!', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              '3 pose của ${widget.memberName} đã được lưu vào hệ thống nhận diện.',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _finish,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  minimumSize: const Size(double.infinity, 56),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
                child: const Text('Hoàn tất', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PoseInfo {
  final String label;
  final String sub;
  final IconData icon;
  const _PoseInfo({required this.label, required this.sub, required this.icon});
}
