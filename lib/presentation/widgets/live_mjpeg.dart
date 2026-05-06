import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// MJPEG widget tự parse stream — không có internal buffer, luôn hiện frame mới nhất.
class LiveMjpeg extends StatefulWidget {
  final String stream;
  final Widget Function(BuildContext, Object, StackTrace?)? error;

  const LiveMjpeg({super.key, required this.stream, this.error});

  @override
  State<LiveMjpeg> createState() => _LiveMjpegState();
}

class _LiveMjpegState extends State<LiveMjpeg> {
  Uint8List? _frame;
  Object? _error;
  StreamSubscription? _sub;
  http.Client? _client;

  static const _soi = 0xFF;
  static const _soiMarker = 0xD8;
  static const _eoiMarker = 0xD9;

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
    _error = null;
    _client = http.Client();
    final req = http.Request('GET', Uri.parse(widget.stream));
    _client!.send(req).then((res) {
      final buf = <int>[];
      _sub = res.stream.listen(
        (chunk) {
          buf.addAll(chunk);
          // Luôn tìm frame MỚI NHẤT — bỏ qua các frame cũ tích tụ trong buffer
          while (true) {
            // Tìm SOI cuối cùng để lấy frame mới nhất
            int lastSoi = -1;
            for (int i = buf.length - 2; i >= 0; i--) {
              if (buf[i] == _soi && buf[i + 1] == _soiMarker) {
                lastSoi = i;
                break;
              }
            }
            if (lastSoi == -1) break;

            // Tìm EOI sau SOI đó
            int eoi = -1;
            for (int i = lastSoi + 2; i < buf.length - 1; i++) {
              if (buf[i] == _soi && buf[i + 1] == _eoiMarker) {
                eoi = i + 2;
                break;
              }
            }
            if (eoi == -1) break;

            // Có frame hoàn chỉnh — lấy và xóa buffer trước đó
            final jpg = Uint8List.fromList(buf.sublist(lastSoi, eoi));
            buf.removeRange(0, eoi);
            if (mounted) setState(() => _frame = jpg);
            break;
          }
        },
        onError: (e, st) {
          if (mounted) setState(() => _error = e);
        },
        onDone: () {
          // Reconnect sau 1s nếu stream bị đóng
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
          const Center(child: Icon(Icons.videocam_off_rounded, color: Colors.white24, size: 44));
    }
    if (_frame == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white30));
    }
    return Image.memory(_frame!, gaplessPlayback: true, fit: BoxFit.cover,
        width: double.infinity, height: double.infinity);
  }
}
