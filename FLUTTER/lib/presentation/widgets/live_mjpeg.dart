import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// MJPEG widget — luôn hiển thị frame mới nhất, không lag buffer.
///
/// Cơ chế:
///   - Tìm SOI (FFD8) cuối cùng trong buffer → bỏ hết data trước đó
///   - Nếu buffer vượt MAX_BUF_BYTES → flush, chỉ giữ chunk cuối
///     (tránh buffer phình to khi network jitter / di chuyển ESP32)
///   - Reconnect tự động sau 1s khi stream đóng hoặc lỗi
class LiveMjpeg extends StatefulWidget {
  final String stream;
  final Widget Function(BuildContext, Object, StackTrace?)? error;

  const LiveMjpeg({super.key, required this.stream, this.error});

  @override
  State<LiveMjpeg> createState() => _LiveMjpegState();
}

class _LiveMjpegState extends State<LiveMjpeg> {
  Uint8List? _frame;
  Object?   _error;
  StreamSubscription? _sub;
  http.Client? _client;

  static const _soi      = 0xFF;
  static const _soiMark  = 0xD8;
  static const _eoiMark  = 0xD9;

  // Nếu buffer vượt ngưỡng này → flush ngay, không để tích lũy
  static const _maxBuf   = 256 * 1024; // 256 KB

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void didUpdateWidget(LiveMjpeg old) {
    super.didUpdateWidget(old);
    if (old.stream != widget.stream) {
      _disconnect();
      _connect();
    }
  }

  @override
  void dispose() {
    _disconnect();
    super.dispose();
  }

  void _disconnect() {
    _sub?.cancel();
    _sub = null;
    _client?.close();
    _client = null;
  }

  void _connect() {
    if (widget.stream.isEmpty) return;
    _error   = null;
    _client  = http.Client();
    final req = http.Request('GET', Uri.parse(widget.stream));

    _client!.send(req).then((res) {
      final buf = <int>[];

      _sub = res.stream.listen(
        (chunk) {
          // Nếu buffer đã quá lớn (network jitter / ESP di chuyển) → flush
          // Giữ lại chunk hiện tại để không mất SOI đang đến
          if (buf.length > _maxBuf) {
            buf.clear();
          }

          buf.addAll(chunk);

          // Tìm SOI cuối cùng — skip thẳng đến frame mới nhất
          int lastSoi = -1;
          for (int i = buf.length - 2; i >= 0; i--) {
            if (buf[i] == _soi && buf[i + 1] == _soiMark) {
              lastSoi = i;
              break;
            }
          }
          if (lastSoi == -1) return;

          // Bỏ hết data trước frame mới nhất
          if (lastSoi > 0) buf.removeRange(0, lastSoi);

          // Tìm EOI của frame này
          int eoi = -1;
          for (int i = 2; i < buf.length - 1; i++) {
            if (buf[i] == _soi && buf[i + 1] == _eoiMark) {
              eoi = i + 2;
              break;
            }
          }
          if (eoi == -1) return; // frame chưa đủ, đợi chunk tiếp

          final jpg = Uint8List.fromList(buf.sublist(0, eoi));
          buf.removeRange(0, eoi);

          if (mounted) setState(() => _frame = jpg);
        },
        onError: (e, st) {
          if (mounted) setState(() => _error = e);
        },
        onDone: () {
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _connect();
          });
        },
        cancelOnError: true,
      );
    }).catchError((e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return widget.error?.call(context, _error!, null) ??
          const Center(
            child: Icon(Icons.videocam_off_rounded,
                color: Colors.white24, size: 44),
          );
    }
    if (_frame == null) {
      return const Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30),
      );
    }
    return Image.memory(
      _frame!,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
