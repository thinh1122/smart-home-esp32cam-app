import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_config.dart';
import '../../../core/services/auth_service.dart';
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

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  final _picker = ImagePicker();

  final List<Uint8List?> _images = [null, null, null];
  final List<String?> _base64s = [null, null, null];

  bool _uploading = false;
  bool _done = false;
  String? _errorMsg;

  static const _poseLabels = ['Chính diện', 'Nghiêng phải', 'Nghiêng trái'];
  static const _poseIcons = [
    Icons.face_rounded,
    Icons.rotate_right_rounded,
    Icons.rotate_left_rounded,
  ];
  static const _poseSubs = [
    'Nhìn thẳng, rõ mặt, đủ sáng',
    'Nghiêng nhẹ sang phải ~20°',
    'Nghiêng nhẹ sang trái ~20°',
  ];

  int get _filledCount => _images.where((e) => e != null).length;
  bool get _canUpload => _filledCount == 3 && !_uploading;

  Future<void> _pickImage(int index) async {
    final result = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 640,
      maxHeight: 640,
    );
    if (result == null) return;

    final bytes = await result.readAsBytes();
    setState(() {
      _images[index] = bytes;
      _base64s[index] = base64Encode(bytes);
      _errorMsg = null;
    });
  }

  Future<void> _upload() async {
    if (!_canUpload) return;
    setState(() { _uploading = true; _errorMsg = null; });

    try {
      for (int pose = 0; pose < 3; pose++) {
        final body = jsonEncode({
          'id': widget.memberId,
          'user_id': AuthService.instance.userId,
          'name': widget.memberName,
          'role': widget.memberRole,
          'image_base64': _base64s[pose],
          'pose': pose + 1,
          'avatar': pose == 0 ? _base64s[0] : '',
        });

        final res = await http.post(
          Uri.parse(AppConfig.enrollUrl),
          headers: {'Content-Type': 'application/json'},
          body: body,
        ).timeout(const Duration(seconds: 15));

        if (res.statusCode != 200) {
          final msg = jsonDecode(res.body)['error'] ?? 'Lỗi server pose ${pose + 1}';
          setState(() { _errorMsg = msg; _uploading = false; });
          return;
        }
      }

      setState(() { _done = true; _uploading = false; });
    } catch (e) {
      setState(() {
        _errorMsg = 'Không kết nối được AI Server.\nKiểm tra WiFi và server.';
        _uploading = false;
      });
    }
  }

  void _finish() => Navigator.pop(context, _base64s[0]);

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    return Scaffold(
      backgroundColor: ac.bg,
      appBar: AppBar(
        backgroundColor: ac.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: ac.textSecondary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đăng ký khuôn mặt',
                style: TextStyle(color: ac.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(widget.memberName,
                style: TextStyle(color: ac.textSecondary, fontSize: 12)),
          ],
        ),
      ),
      body: _done ? _buildDoneView() : _buildPickView(ac),
    );
  }

  Widget _buildPickView(AC ac) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Row(
            children: List.generate(3, (i) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: i < 2 ? 6 : 0),
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: _images[i] != null ? AppColors.success : ac.cardElevated,
                ),
              ),
            )),
          ),
        ),

        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$_filledCount/3 ảnh đã chọn',
                  style: TextStyle(color: ac.textSecondary, fontSize: 12)),
              Text(_filledCount == 3 ? 'Sẵn sàng đăng ký ✓' : 'Chọn đủ 3 ảnh',
                  style: TextStyle(
                    color: _filledCount == 3 ? AppColors.success : ac.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600,
                  )),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: 3,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _buildImageSlot(ac, i),
          ),
        ),

        if (_errorMsg != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.error.withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMsg!,
                      style: const TextStyle(color: AppColors.error, fontSize: 12))),
                ],
              ),
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: _uploading
                ? Container(
                    height: 56,
                    decoration: BoxDecoration(
                      color: ac.accentDim,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: ac.accentLight, strokeWidth: 2)),
                        const SizedBox(width: 12),
                        Text('Đang đăng ký...',
                            style: TextStyle(color: ac.accentLight,
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  )
                : ElevatedButton.icon(
                    onPressed: _canUpload ? _upload : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _canUpload ? ac.accent : ac.cardElevated,
                      minimumSize: const Size(double.infinity, 56),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                      elevation: _canUpload ? 4 : 0,
                    ),
                    icon: Icon(Icons.upload_rounded,
                        color: _canUpload ? Colors.white : ac.textSecondary),
                    label: Text(
                      _canUpload ? 'Đăng ký khuôn mặt' : 'Chọn đủ 3 ảnh để tiếp tục',
                      style: TextStyle(
                        color: _canUpload ? Colors.white : ac.textSecondary,
                        fontSize: 15, fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageSlot(AC ac, int index) {
    final hasImage = _images[index] != null;
    return GestureDetector(
      onTap: () => _pickImage(index),
      child: Container(
        height: 110,
        decoration: BoxDecoration(
          color: hasImage ? ac.cardElevated : ac.card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: hasImage ? AppColors.success.withOpacity(0.4) : ac.border,
            width: hasImage ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(20)),
              child: SizedBox(
                width: 110,
                height: 110,
                child: hasImage
                    ? Image.memory(_images[index]!, fit: BoxFit.cover)
                    : Container(
                        color: ac.cardElevated,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_poseIcons[index], color: ac.textSecondary, size: 28),
                            const SizedBox(height: 4),
                            Text('Chọn ảnh',
                                style: TextStyle(color: ac.textSecondary, fontSize: 10)),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(width: 16),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: (hasImage ? AppColors.success : ac.accent).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Pose ${index + 1}',
                            style: TextStyle(
                              color: hasImage ? AppColors.success : ac.accentLight,
                              fontSize: 10, fontWeight: FontWeight.bold,
                            )),
                      ),
                      if (hasImage) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.check_circle_rounded,
                            color: AppColors.success, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_poseLabels[index],
                      style: TextStyle(
                          color: ac.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(_poseSubs[index],
                      style: TextStyle(color: ac.textSecondary, fontSize: 11)),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Icon(
                hasImage ? Icons.edit_rounded : Icons.add_photo_alternate_rounded,
                color: hasImage ? AppColors.success : ac.accentLight,
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDoneView() {
    final ac = AC.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100, height: 100,
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.15),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.success.withOpacity(0.5), width: 2),
              ),
              child: const Icon(Icons.check_rounded, color: AppColors.success, size: 56),
            ),
            const SizedBox(height: 24),
            Text('Đăng ký thành công!',
                style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(
              '3 ảnh của ${widget.memberName} đã được lưu vào hệ thống nhận diện.',
              style: TextStyle(color: ac.textSecondary, fontSize: 14),
              textAlign: TextAlign.center,
            ),

            if (_images[0] != null) ...[
              const SizedBox(height: 24),
              CircleAvatar(
                radius: 48,
                backgroundImage: MemoryImage(_images[0]!),
              ),
            ],

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
                child: const Text('Hoàn tất',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
