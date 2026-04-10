import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'database_helper.dart';

class FrontDoorCamScreen extends StatefulWidget {
  const FrontDoorCamScreen({Key? key}) : super(key: key);

  @override
  State<FrontDoorCamScreen> createState() => _FrontDoorCamScreenState();
}

class _FrontDoorCamScreenState extends State<FrontDoorCamScreen> {
  final Color _bgColor = const Color(0xFF14141E);
  final Color _cardColor = const Color(0xFF1E1E2A);
  final Color _accentColor = const Color(0xFFA5B4FC);
  final Color _textColor = Colors.white;

  // Danh sách từ SQLite Local Database
  List<Map<String, dynamic>> _members = [];
  List<Map<String, dynamic>> _logs = [];

  bool _isStreamActive = true;

  // Nhận diện khuôn mặt
  List<Map<String, dynamic>> _recognizedFaces = [];
  Timer? _recognizeTimer;
  bool _isRecognizing = false;
  bool _isCapturing = false;  // Flag mới để tránh spam
  
  // Biến để theo dõi khuôn mặt ổn định
  DateTime? _faceDetectedTime;
  bool _faceStable = false;
  int _stableFaceCount = 0;

  static const String _esp32Ip = '192.168.110.38';      // ⚠️ IP ESP32-CAM
  static const String _relayIp = '192.168.110.101';    // IP máy tính (không có dấu cách!)
  static const String _relayPort = '8080';

  @override
  void initState() {
    super.initState();
    _loadData();
    // Định kỳ 3 giây gửi 1 frame lên Python để nhận diện
    _recognizeTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_isStreamActive) _sendFrameForRecognition();
    });
  }

  @override
  void dispose() {
    _recognizeTimer?.cancel();
    super.dispose();
  }

  // Chụp 1 frame từ Relay Server rồi gửi nhận diện
  Future<void> _sendFrameForRecognition() async {
    if (_isRecognizing || _isCapturing) return;  // Thêm check _isCapturing
    _isRecognizing = true;
    try {
      // BƯỚC 1: Chụp 1 ảnh để kiểm tra chuyển động và khuôn mặt
      final testRes = await http
          .get(Uri.parse('http://$_relayIp:$_relayPort/capture'))
          .timeout(const Duration(seconds: 2));
          
      if (testRes.statusCode != 200) return;
      
      // Gửi ảnh test để kiểm tra motion + face
      final testBase64 = base64Encode(testRes.bodyBytes);
      final faceCheckRes = await http
          .post(
            Uri.parse('http://$_relayIp:$_relayPort/recognize'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'image_base64': testBase64}),
          )
          .timeout(const Duration(seconds: 3));
      
      if (faceCheckRes.statusCode != 200) return;
      
      final faceCheckJson = jsonDecode(faceCheckRes.body);
      final hasMotion = faceCheckJson['motion'] ?? false;
      final faceCount = faceCheckJson['face_count'] ?? 0;
      final faces = List<Map<String, dynamic>>.from(
        (faceCheckJson['faces'] as List? ?? []).map((f) => Map<String, dynamic>.from(f)),
      );
      
      // Nếu không có chuyển động hoặc không có face thì reset
      if (!hasMotion || faceCount == 0) {
        _faceDetectedTime = null;
        _faceStable = false;
        _stableFaceCount = 0;
        
        // Xóa khung focus cũ
        if (mounted) {
          setState(() {
            _recognizedFaces = [];
          });
        }
        return;
      }
      
      // BƯỚC 2: Có chuyển động + có face → Kiểm tra ổn định 2 giây
      final now = DateTime.now();
      
      if (_faceDetectedTime == null) {
        // Lần đầu phát hiện khuôn mặt
        _faceDetectedTime = now;
        _stableFaceCount = 1;
        debugPrint('👁️ Phát hiện chuyển động + khuôn mặt - Bắt đầu đếm...');
      } else {
        // Đã phát hiện trước đó, kiểm tra thời gian
        final duration = now.difference(_faceDetectedTime!);
        _stableFaceCount++;
        
        if (duration.inSeconds < 2) {
          // Chưa đủ 2 giây - hiển thị đang chờ
          final remainingTime = 2 - duration.inSeconds;
          debugPrint('⏳ Khuôn mặt ổn định ${duration.inSeconds}s/2s - Còn ${remainingTime}s...');
          
          // Hiển thị khung chờ
          if (mounted && faces.isNotEmpty) {
            setState(() {
              _recognizedFaces = faces.map((face) => {
                'matched': null,
                'name': 'Giữ nguyên ${remainingTime}s...',
                'id': '',
                'confidence': 0.0,
                'box': face['box'] ?? {'top': 50, 'right': 200, 'bottom': 150, 'left': 50}
              }).toList();
            });
          }
          return; // Chưa đủ thời gian, thoát
        } else if (!_faceStable) {
          // Đủ 2 giây và chưa bắt đầu nhận diện
          _faceStable = true;
          debugPrint('✅ Khuôn mặt ổn định 2s → Bắt đầu nhận diện!');
        }
      }
      
      // Nếu chưa ổn định thì không tiếp tục
      if (!_faceStable) return;
      
      // Đánh dấu đang chụp để tránh spam
      if (_isCapturing) return;
      _isCapturing = true;
      
      // Hiển thị khung đang nhận diện (CHỈ 1 LẦN)
      if (mounted) {
        setState(() {
          _recognizedFaces = [{
            'matched': null,
            'name': 'Đang nhận diện...',
            'id': '',
            'confidence': 0.0,
            'box': {'top': 50, 'right': 200, 'bottom': 150, 'left': 50}
          }];
        });
      }
      
      debugPrint('📸 Bắt đầu chụp ảnh tự động sau ${_stableFaceCount} lần phát hiện...');
      
      // BƯỚC 3: Chụp 4 ảnh trong 2 giây (đã có 1 ảnh test)
      List<String> capturedImages = [testBase64]; // Dùng luôn ảnh test
      
      for (int i = 1; i < 4; i++) {
        final captureRes = await http
            .get(Uri.parse('http://$_relayIp:$_relayPort/capture'))
            .timeout(const Duration(seconds: 2));
            
        if (captureRes.statusCode == 200) {
          final base64Image = base64Encode(captureRes.bodyBytes);
          capturedImages.add(base64Image);
        }
        
        // Đợi 500ms trước khi chụp ảnh tiếp theo
        if (i < 3) await Future.delayed(const Duration(milliseconds: 500));
      }
      
      if (capturedImages.isEmpty) return;
      
      debugPrint('📸 Đã chụp ${capturedImages.length} ảnh để so sánh...');
      
      // BƯỚC 4: Gửi tất cả ảnh để so sánh
      final recognizeRes = await http
          .post(
            Uri.parse('http://$_relayIp:$_relayPort/auto_capture_compare'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'images_base64': capturedImages}),
          )
          .timeout(const Duration(seconds: 10));

      if (recognizeRes.statusCode == 200) {
        final json = jsonDecode(recognizeRes.body);
        
        if (json['matched'] == true) {
          // Nhận diện thành công
          final name = json['name'] as String;
          final id = json['id'] as String;
          final confidence = (json['confidence'] as num).toDouble();
          final pct = (confidence * 100).toStringAsFixed(0);
          
          debugPrint('✅ $name | ID=$id | Độ chính xác: $pct% | 🚪 MỞ CỬA!');
          
          await DatabaseHelper.instance.addLog(
            '✅ Nhận diện thành công',
            '$name${id.isNotEmpty ? " — ID: $id" : ""} xuất hiện tại cửa ($pct%)',
          );
          
          // Hiển thị lời chào
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.waving_hand, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '👋 Xin chào $name! Chào mừng bạn về nhà.',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          
          // Cập nhật UI với kết quả nhận diện
          if (mounted) {
            setState(() {
              _recognizedFaces = [{
                'matched': true,
                'name': name,
                'id': id,
                'confidence': confidence,
                'box': {'top': 50, 'right': 200, 'bottom': 150, 'left': 50}
              }];
            });
          }
        } else {
          // Người lạ
          debugPrint('⚠️ PHÁT HIỆN NGƯỜI LẠ TẠI CỬA! 🚨');
          
          await DatabaseHelper.instance.addLog(
            '⚠️ Cảnh báo: Người lạ',
            'Phát hiện khuôn mặt không xác định tại cửa chính',
          );
          
          // Hiển thị cảnh báo người lạ
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 28),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        '🚨 CẢNH BÁO: Phát hiện người lạ tại cửa!',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.red.shade700,
                duration: const Duration(seconds: 5),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          
          // Cập nhật UI với cảnh báo người lạ
          if (mounted) {
            setState(() {
              _recognizedFaces = [{
                'matched': false,
                'name': 'Nguoi la',
                'id': '',
                'confidence': 0.0,
                'box': {'top': 50, 'right': 200, 'bottom': 150, 'left': 50}
              }];
            });
          }
        }

        // Reset trạng thái sau khi nhận diện xong
        _faceDetectedTime = null;
        _faceStable = false;
        _stableFaceCount = 0;
        _isCapturing = false;  // Reset flag

        // Reload Recent Activity
        if (mounted) {
          final updatedLogs = await DatabaseHelper.instance.getLogs();
          if (mounted) setState(() => _logs = updatedLogs);
        }
      }
    } on Exception catch (e) {
      // Lỗi mạng - reset trạng thái
      _faceDetectedTime = null;
      _faceStable = false;
      _stableFaceCount = 0;
      _isCapturing = false;  // Reset flag khi lỗi
    } finally {
      _isRecognizing = false;
    }
  }

  Future<void> _loadData() async {
    final members = await DatabaseHelper.instance.getAllMembers();
    final logs = await DatabaseHelper.instance.getLogs();
    setState(() {
      _members = members;
      _logs = logs;
    });

    // Nếu DB trống hoàn toàn, tạo mồi dữ liệu mẫu để tránh trắng màn ảnh
    if (_members.isEmpty && _logs.isEmpty) {
      _seedInitialData();
    }
  }

  Future<void> _seedInitialData() async {
    await DatabaseHelper.instance.insertMember({'id': '0', 'name': 'Nguyễn Phùng Thịnh', 'role': 'Admin / Chủ nhà', 'avatar': 'https://i.pravatar.cc/150?img=11'});
    await DatabaseHelper.instance.insertMember({'id': '1', 'name': 'Mẹ', 'role': 'Thành viên', 'avatar': 'https://i.pravatar.cc/150?img=43'});
    await DatabaseHelper.instance.insertMember({'id': '2', 'name': 'Bố', 'role': 'Thành viên', 'avatar': 'https://i.pravatar.cc/150?img=52'});
    await DatabaseHelper.instance.addLog('Power On', 'Hệ thống Smart Home ESP32-CAM khởi động thành công');
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAppBar(context),
              const SizedBox(height: 24),
              _buildCameraFeed(),
              const SizedBox(height: 24),
              _buildQuickActions(),
              const SizedBox(height: 24),
              _buildRecentActivity(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(context),
    );
  }

  Widget _buildAppBar(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            InkWell(
              onTap: () {
                if (Navigator.canPop(context)) Navigator.pop(context);
              },
              child: const CircleAvatar(
                radius: 20,
                backgroundImage: NetworkImage('https://i.pravatar.cc/150?img=11'),
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              'Front Door\nCam',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, height: 1.2),
            ),
          ],
        ),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  const Text('LIVE', style: TextStyle(color: Colors.redAccent, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Icon(Icons.notifications_none_rounded, color: _accentColor),
          ],
        )
      ],
    );
  }

  Widget _buildCameraFeed() {
    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(36),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(36),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Stream trực tiếp từ ESP32-CAM (điện thoại kết nối được)
            if (_isStreamActive)
              Mjpeg(
                isLive: true,
                error: (context, error, stack) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.videocam_off, color: Colors.redAccent, size: 36),
                        SizedBox(height: 8),
                        Text('Không kết nối được cam\nKiểm tra ESP32-CAM đã bật chưa',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.redAccent, fontSize: 12, height: 1.5)),
                      ],
                    ),
                  );
                },
                stream: 'http://$_relayIp:$_relayPort/stream', // Từ Relay Server
              )
            else
              Container(
                color: Colors.black,
                child: const Center(child: Text('Đang chuẩn bị camera...', style: TextStyle(color: Colors.cyanAccent, fontSize: 12))),
              ),

            // Bốn góc khung chữ thập (Reticle)
            Positioned(top: 20, left: 20, child: _buildCornerMark(top: true, left: true)),
            Positioned(top: 20, right: 20, child: _buildCornerMark(top: true, left: false)),
            Positioned(bottom: 20, left: 20, child: _buildCornerMark(top: false, left: true)),
            Positioned(bottom: 20, right: 20, child: _buildCornerMark(top: false, left: false)),

            // Cột thông tin
            Positioned(
              top: 40,
              left: 40,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildGlasPill(Icons.wifi, 'Strong Connection', Colors.cyanAccent),
                  const SizedBox(height: 12),
                  _buildGlasPill(Icons.battery_4_bar, '84%', Colors.amberAccent),
                ],
              ),
            ),

            // Badge nhận diện khuôn mặt (hiện bên dưới)
            if (_recognizedFaces.isNotEmpty)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: _recognizedFaces.map((face) {
                    final matched = face['matched'];
                    final name = face['name'] as String;
                    final pct = ((face['confidence'] as num).toDouble() * 100).toStringAsFixed(0);
                    
                    // Xác định màu sắc dựa trên trạng thái
                    Color bgColor, borderColor, iconColor;
                    IconData iconData;
                    String displayText;
                    
                    if (matched == null) {
                      // Đang nhận diện - màu xanh dương
                      bgColor = Colors.blue.withOpacity(0.35);
                      borderColor = Colors.blueAccent;
                      iconColor = Colors.blueAccent;
                      iconData = Icons.face_retouching_natural;
                      displayText = '🔍 ĐANG NHẬN DIỆN...';
                    } else if (matched == true) {
                      // Nhận diện thành công - màu xanh lá
                      bgColor = Colors.green.withOpacity(0.35);
                      borderColor = Colors.greenAccent;
                      iconColor = Colors.greenAccent;
                      iconData = Icons.check_circle;
                      displayText = name;
                    } else {
                      // Người lạ - màu cam
                      bgColor = Colors.orange.withOpacity(0.40);
                      borderColor = Colors.orangeAccent;
                      iconColor = Colors.orangeAccent;
                      iconData = Icons.warning_amber_rounded;
                      displayText = '⚠️ NGƯỜI LẠ';
                    }
                    
                    // Tìm avatar của người được nhận diện
                    final memberMatch = _members.where((m) => m['name'] == name).toList();
                    final avatarData = memberMatch.isNotEmpty ? memberMatch.first['avatar'] as String? : null;
                    
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: bgColor,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: borderColor, width: 1.5),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Avatar hoặc icon
                              if (matched == true && avatarData != null)
                                CircleAvatar(
                                  radius: 16,
                                  backgroundImage: avatarData.startsWith('http')
                                      ? NetworkImage(avatarData) as ImageProvider
                                      : MemoryImage(base64Decode(avatarData)),
                                )
                              else
                                Icon(iconData, color: iconColor, size: 22),
                              const SizedBox(width: 8),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayText,
                                    style: TextStyle(
                                      color: borderColor,
                                      fontSize: 13,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  if (matched == true)
                                    Text(
                                      'Độ chính xác: $pct%',
                                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                                    )
                                  else if (matched == null)
                                    const Text(
                                      'Đang xử lý...',
                                      style: TextStyle(color: Colors.white70, fontSize: 10),
                                    )
                                  else
                                    const Text(
                                      'Không nhận ra khuôn mặt',
                                      style: TextStyle(color: Colors.white70, fontSize: 10),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCornerMark({required bool top, required bool left}) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        border: Border(
          top: top ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          bottom: !top ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          left: left ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
          right: !left ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildGlasPill(IconData icon, String text, Color iconColor) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withOpacity(0.1)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: iconColor, size: 14),
              const SizedBox(width: 8),
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildActionBtn('Thành viên', Icons.person, true, null, onTap: () => _showMembersBottomSheet(context))),
            const SizedBox(width: 16),
            Expanded(child: _buildActionBtn('Record', Icons.circle, false, Colors.red[300])),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildActionBtn('Snapshot', Icons.camera_alt, false, Colors.cyanAccent)),
            const SizedBox(width: 16),
            Expanded(child: _buildActionBtn('Alarm', Icons.campaign, false, Colors.orangeAccent)),
          ],
        ),
      ],
    );
  }

  Widget _buildActionBtn(String title, IconData icon, bool isPrimary, Color? iconColor, {VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: isPrimary ? _accentColor : _cardColor,
          borderRadius: BorderRadius.circular(32),
          boxShadow: isPrimary ? [BoxShadow(color: _accentColor.withOpacity(0.3), blurRadius: 20, spreadRadius: 2)] : [],
        ),
        child: Column(
          children: [
            Icon(icon, color: isPrimary ? Colors.black : (iconColor ?? Colors.white), size: 28),
            const SizedBox(height: 12),
            Text(title, style: TextStyle(color: isPrimary ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentActivity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(color: _cardColor, borderRadius: BorderRadius.circular(36)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tiêu đề & Cụm nút lân cận
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Recent Activity', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('Scroll back to view motion\nevents', style: TextStyle(color: Colors.grey[400], fontSize: 12, height: 1.4)),
                    ],
                  ),
                ),
                Row(
                  children: [
                    _buildIconBtn(Icons.calendar_month),
                    const SizedBox(width: 12),
                    _buildIconBtn(Icons.filter_list),
                  ],
                )
              ],
            ),
          ),
          const SizedBox(height: 32),
          
          // Timeline Graph
          _buildTimeline(),
          const SizedBox(height: 32),
          
          // SQL Logs
          if (_logs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: _logs.map((log) {
                  final DateTime time = DateTime.tryParse(log['timestamp']) ?? DateTime.now();
                  final String timeString = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.history, color: Colors.cyanAccent),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log['action'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text(log['detail'], style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                        Text(timeString, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ],
                    )
                  );
                }).toList(),
              )
            )
          else
             const Padding(
               padding: EdgeInsets.symmetric(horizontal: 24),
               child: Text('Chưa có lịch sử hoạt động', style: TextStyle(color: Colors.white54)),
             )
        ],
      ),
    );
  }

  Widget _buildIconBtn(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: Colors.white, size: 20),
    );
  }

  Widget _buildTimeline() {
    return Column(
      children: [
        // Nhãn giờ
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: ['12:00', '13:00', '14:00', '15:00', '16:00', '17:00', '18:00']
                .map((e) => Text(e, style: const TextStyle(color: Colors.grey, fontSize: 10)))
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        // Thanh Timeline
        Container(
          height: 60,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(color: const Color(0xFF14141E), borderRadius: BorderRadius.circular(30)),
          child: Stack(
            children: [
              // Vạch dọc
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(6, (index) => Container(width: 1, color: Colors.white.withOpacity(0.05))),
              ),
              // Cục sự kiện 1 (Vàng nhạt - hộp)
              Positioned(
                left: 45,
                top: 15,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: Colors.amber.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.amber.withOpacity(0.5))),
                  child: const Icon(Icons.outbox, color: Colors.amber, size: 14),
                ),
              ),
              // Cục sự kiện 2 (Xanh lơ - người)
              Positioned(
                left: 140,
                top: 15,
                child: Container(
                  width: 60,
                  height: 30,
                  decoration: BoxDecoration(color: Colors.cyan.withOpacity(0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.cyan.withOpacity(0.5))),
                  child: const Center(child: Icon(Icons.person, color: Colors.cyanAccent, size: 14)),
                ),
              ),
              // Cục sự kiện 3 (Xanh dương đậm - hộp)
              Positioned(
                left: 200,
                top: 15,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: Colors.blue.withOpacity(0.2), shape: BoxShape.circle, border: Border.all(color: Colors.blue.withOpacity(0.5))),
                  child: const Icon(Icons.inventory_2, color: Colors.blueAccent, size: 14),
                ),
              ),
              // Thanh sáng báo mốc thời gian hiện tại
              Positioned(
                left: 135, // căn đoạn 15:00
                top: 0,
                bottom: 0,
                child: Container(
                  width: 3,
                  decoration: BoxDecoration(
                    color: _accentColor,
                    boxShadow: [BoxShadow(color: _accentColor, blurRadius: 10, spreadRadius: 2)], // Glow
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }

  Widget _buildThumbnail(String url, String time) {
    return Container(
      width: 140,
      height: 90,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
        image: DecorationImage(image: NetworkImage(url), fit: BoxFit.cover, colorFilter: ColorFilter.mode(Colors.black.withOpacity(0.2), BlendMode.darken)),
      ),
      child: Align(
        alignment: Alignment.bottomLeft,
        child: Container(
          margin: const EdgeInsets.all(8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(8)),
          child: Text(time, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  void _showMembersBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          margin: const EdgeInsets.only(top: 24),
          decoration: const BoxDecoration(
            color: Color(0xFF1E1E2A),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(height: 4, width: 40, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 24),
              const Text('Nhận diện khuôn mặt', style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Danh sách thành viên gia đình được phép mở cửa', style: TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 24),

              Expanded(
                child: ListView.builder(
                  itemCount: _members.length,
                  itemBuilder: (context, index) {
                    final member = _members[index];
                    return _buildMemberItem(member['id']!, member['name']!, member['role']!, member['avatar']!, () async {
                      // Xóa trên Python server (xóa ảnh + database server)
                      try {
                        await http.post(
                          Uri.parse('http://$_relayIp:$_relayPort/delete'),
                          headers: {'Content-Type': 'application/json'},
                          body: jsonEncode({'id': member['id']!, 'name': member['name']!}),
                        ).timeout(const Duration(seconds: 5));
                      } catch (e) {
                        debugPrint('⚠️ Không xóa được trên server: $e');
                      }
                      
                      // Xóa trong SQLite local
                      await DatabaseHelper.instance.deleteMember(member['id']!);
                      await DatabaseHelper.instance.addLog('Xoá Database', 'Đã gỡ quyền truy cập của Face ID: ${member['name']}');
                      await _loadData();
                      Navigator.pop(context);
                      _showMembersBottomSheet(context); // Tải lại menu cập nhật DB
                    });
                  },
                ),
              ),

              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context); // Đóng menu
                    // Mở Form yêu cầu khai báo ID và Tên
                    _showAddMemberDialog(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFA5B4FC),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  icon: const Icon(Icons.camera_front, color: Colors.black, size: 24),
                  label: const Text('Thêm khuôn mặt mới', style: TextStyle(color: Colors.black, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showAddMemberDialog(BuildContext context) {
    final TextEditingController nameController = TextEditingController();
    final TextEditingController idController = TextEditingController(text: _members.length.toString());

    showDialog(
      context: this.context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text('Khai báo ID & Tên', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: idController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'ID',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(16)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA5B4FC)), borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Tên thành viên',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.white24), borderRadius: BorderRadius.circular(16)),
                  focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Color(0xFFA5B4FC)), borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ]
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFA5B4FC),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                String name = nameController.text.trim();
                String id = idController.text.trim();
                if (name.isEmpty || id.isEmpty) return;
                
                Navigator.pop(context); // Đóng form khai báo

                // Chuyển sang màn hình Mở Camera & Chụp thủ công
                _showFaceCaptureDialog(this.context, id, name);
              },
              child: const Text('Tiếp tục', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            )
          ]
        );
      }
    );
  }

  void _showFaceCaptureDialog(BuildContext context, String id, String name) {
    setState(() { _isStreamActive = false; }); // Tạm ngắt camera ngoài

    Future.delayed(const Duration(milliseconds: 600), () {
      int captureStep = 0;
      String? firstCapturedBase64; // Lưu tấm ảnh đầu tiên để làm avatar
      bool isCapturing = false;    // Trạng thái đang chụp
      final List<String> instructions = [
        '📸 BƯỚC 1/3: Nhìn thẳng vào Camera',
        '📸 BƯỚC 2/3: Xoay mặt sang PHẢI',
        '📸 BƯỚC 3/3: Xoay mặt sang TRÁI',
        '✅ Xong! Căn giữa và bấm LƯU HÌNH ẢNH'
      ];

      if (!mounted) return;
      showDialog(
        context: this.context,
        barrierDismissible: false,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                backgroundColor: const Color(0xFF1E1E2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                contentPadding: const EdgeInsets.all(16),
                title: Text('Hướng camera vào ' + name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Text(instructions[captureStep], style: TextStyle(color: captureStep == 3 ? Colors.greenAccent : Colors.cyanAccent, fontSize: 16, fontWeight: FontWeight.bold, height: 1.4), textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        height: 220,
                        width: double.infinity,
                        color: Colors.black26,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Mjpeg(
                              isLive: true,
                              error: (context, error, stack) => const Center(child: Text('Lỗi kết nối Camera', style: TextStyle(color: Colors.redAccent))),
                              stream: 'http://$_relayIp:$_relayPort/stream', // Stream từ Relay Server
                            ),
                            if (captureStep == 3)
                              Container(
                                color: Colors.black.withOpacity(0.5),
                                child: const Center(child: Icon(Icons.check_circle, color: Colors.greenAccent, size: 80)),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: isCapturing
                          ? const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    width: 20, height: 20,
                                    child: CircularProgressIndicator(color: Colors.cyanAccent, strokeWidth: 2.5),
                                  ),
                                  SizedBox(width: 12),
                                  Text('Đang chụp...', style: TextStyle(color: Colors.cyanAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            )
                          : captureStep < 3
                              ? ElevatedButton.icon(
                                  onPressed: () async {
                                    setDialogState(() => isCapturing = true);
                                    try {
                                      // 1. Chụp ảnh từ Relay Server
                                      final response = await http
                                          .get(Uri.parse('http://$_relayIp:$_relayPort/capture'))
                                          .timeout(const Duration(seconds: 5));

                                      if (response.statusCode == 200) {
                                        final base64Image = base64Encode(response.bodyBytes);
                                        // Lưu tấm đầu tiên làm avatar
                                        if (captureStep == 0) firstCapturedBase64 = base64Image;

                                        // 2. Gửi Relay Server học góc này (kèm id để lưu registry)
                                        try {
                                          await http.post(
                                            Uri.parse('http://$_relayIp:$_relayPort/enroll'),
                                            headers: {'Content-Type': 'application/json'},
                                            body: jsonEncode({
                                              'id':           id,   // ID thành viên
                                              'name':         name,
                                              'image_base64': base64Image,
                                              'pose':         captureStep + 1, // 1, 2 hoặc 3
                                            }),
                                          ).timeout(const Duration(seconds: 6));
                                        } catch (_) {
                                          debugPrint('Relay server chưa bật, bỏ qua.');
                                        }

                                        setDialogState(() {
                                          captureStep++;
                                          isCapturing = false;
                                        });
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          SnackBar(
                                            content: Text('✅ Chụp tấm $captureStep/3 — đã gửi Python!'),
                                            backgroundColor: Colors.green,
                                            duration: const Duration(seconds: 1),
                                          ),
                                        );
                                      } else {
                                        setDialogState(() => isCapturing = false);
                                        ScaffoldMessenger.of(this.context).showSnackBar(
                                          const SnackBar(content: Text('⚠️ Chụp thất bại! Thử lại.'), backgroundColor: Colors.redAccent),
                                        );
                                      }
                                    } catch (e) {
                                      setDialogState(() => isCapturing = false);
                                      ScaffoldMessenger.of(this.context).showSnackBar(
                                        const SnackBar(content: Text('⚠️ Không kết nối được ESP32!'), backgroundColor: Colors.redAccent),
                                      );
                                    }
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.camera, color: Colors.blueAccent, size: 28),
                                  label: Text(
                                    'CHỤP TẤM ${captureStep + 1}',
                                    style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : ElevatedButton.icon(
                                  onPressed: () {
                                    // Đã chụp & gửi xong 3 góc → lưu vào SQLite
                                    Navigator.pop(context, firstCapturedBase64);
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.greenAccent,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  ),
                                  icon: const Icon(Icons.save, color: Colors.black, size: 28),
                                  label: const Text('LƯU HÌNH ẢNH', style: TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold)),
                                ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Hủy bỏ', style: TextStyle(color: Colors.white54, fontSize: 16)),
                    ),
                  ]
                ),
              )
              );
            }
          );
        }
      ).then((resultBase64) { 
        if (!mounted) return;
        setState(() { _isStreamActive = true; }); // Mở lại camera ngoài
        
        if (resultBase64 != null && resultBase64 is String) {
            bool exists = _members.any((member) => member['id'] == id);
            if (!exists) {
                DatabaseHelper.instance.insertMember({
                    'id': id,
                    'name': name,
                    'role': 'Duyệt bằng Python AI',
                    'avatar': resultBase64,
                }).then((_) {
                     DatabaseHelper.instance.addLog('✅ Đăng ký thành công', 'Đã đăng ký khuôn mặt mới: $name (ID: $id)');
                     _loadData();
                });
            }

            // ── Thông báo thành công 1.5 giây rồi tự đóng ──────────────
            ScaffoldMessenger.of(this.context)
              ..hideCurrentSnackBar()
              ..showSnackBar(
                SnackBar(
                  duration: const Duration(milliseconds: 1500),
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                  content: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A3A2A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.greenAccent.withOpacity(0.6), width: 1.5),
                      boxShadow: [BoxShadow(color: Colors.greenAccent.withOpacity(0.2), blurRadius: 20, spreadRadius: 2)],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 28),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Đăng ký thành công! 🎉', style: TextStyle(color: Colors.greenAccent, fontSize: 14, fontWeight: FontWeight.bold)),
                              Text('Đã học khuôn mặt của $name', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );

            // Đợi 1.5 giây rồi đóng
            Future.delayed(const Duration(milliseconds: 1600), () {
              if (mounted) Navigator.pop(this.context);
            });
        }
      });
    });
  }

  void _showMemberDetailsDialog(String id, String name, String role, String avatarUrl) {
    showDialog(
      context: this.context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E1E2A),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          contentPadding: const EdgeInsets.all(24),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 50,
                backgroundImage: avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) as ImageProvider : MemoryImage(base64Decode(avatarUrl)),
              ),
              const SizedBox(height: 16),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(color: _accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: Text('ID: $id', style: TextStyle(color: _accentColor, fontSize: 14, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 8),
              Text(role, style: const TextStyle(color: Colors.white54, fontSize: 14)),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E2E3E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Đóng', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        );
      }
    );
  }

  Widget _buildMemberItem(String id, String name, String role, String avatarUrl, VoidCallback onDelete) {
    return GestureDetector(
      onTap: () => _showMemberDetailsDialog(id, name, role, avatarUrl),
      child: Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: avatarUrl.startsWith('http') ? NetworkImage(avatarUrl) as ImageProvider : MemoryImage(base64Decode(avatarUrl)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _accentColor.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                      child: Text('ID: $id', style: TextStyle(color: _accentColor, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(width: 8),
                    Text(role, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.1), shape: BoxShape.circle),
              child: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
            ),
          ),
        ],
      ),
    ));
  }

  Widget _buildBottomNav(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        border: Border(top: BorderSide(color: Colors.white10)),
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(Icons.home_filled, 'HOME', false, context),
            _buildNavItem(Icons.sports_esports, 'DEVICES', true), // Dashboard/Robot icon alternative
            _buildNavItem(Icons.light, 'SCENES', false),
            _buildNavItem(Icons.person_outline, 'PROFILE', false),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(IconData icon, String label, bool isActive, [BuildContext? context]) {
    return GestureDetector(
      onTap: () {
        if (label == 'HOME' && context != null) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      },
      child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isActive ? _accentColor.withOpacity(0.9) : Colors.transparent,
            shape: BoxShape.circle,
            boxShadow: isActive ? [BoxShadow(color: _accentColor.withOpacity(0.4), blurRadius: 10, spreadRadius: 2)] : [],
          ),
          child: Icon(icon, color: isActive ? Colors.black : const Color(0xFF8E8E9F), size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: isActive ? _accentColor : const Color(0xFF8E8E9F), fontSize: 10, fontWeight: FontWeight.bold)),
      ],
    ),
    );
  }
}
