import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LiveMjpeg extends StatefulWidget {
  final String stream;
  final Widget Function(BuildContext, Object, StackTrace?)? error;

  const LiveMjpeg({super.key, required this.stream, this.error});

  @override
  State<LiveMjpeg> createState() => _LiveMjpegState();
}

class _LiveMjpegState extends State<LiveMjpeg> {
  Uint8List? _frame;
  Object?    _error;
  StreamSubscription? _sub;
  http.Client? _client;

  // Raw byte buffer — thao tác trực tiếp, không qua BytesBuilder
  static const _maxBuf = 128 * 1024; // 128KB — flush khi jitter
  final _buf = <int>[];

  @override
  void initState() { super.initState(); _connect(); }

  @override
  void didUpdateWidget(LiveMjpeg old) {
    super.didUpdateWidget(old);
    if (old.stream != widget.stream) { _disconnect(); _connect(); }
  }

  @override
  void dispose() { _disconnect(); super.dispose(); }

  void _disconnect() {
    _sub?.cancel(); _sub = null;
    _client?.close(); _client = null;
    _buf.clear();
  }

  void _connect() {
    if (widget.stream.isEmpty) return;
    _error = null;
    _buf.clear();
    _client = http.Client();
    final req = http.Request('GET', Uri.parse(widget.stream));

    _client!.send(req).then((res) {
      _sub = res.stream.listen(
        _onChunk,
        onError: (e, st) { if (mounted) setState(() => _error = e); },
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

  void _onChunk(List<int> chunk) {
    // Flush nếu buffer quá lớn (network jitter / ESP32 restart)
    if (_buf.length > _maxBuf) _buf.clear();

    _buf.addAll(chunk);

    // Scan tìm SOI cuối (FFD8) — bỏ frame cũ, chỉ giữ frame mới nhất
    int lastSoi = -1;
    for (int i = _buf.length - 2; i >= 0; i--) {
      if (_buf[i] == 0xFF && _buf[i + 1] == 0xD8) { lastSoi = i; break; }
    }
    if (lastSoi == -1) return;

    // Bỏ data trước SOI
    if (lastSoi > 0) _buf.removeRange(0, lastSoi);

    // Tìm EOI (FFD9) sau SOI
    int eoi = -1;
    for (int i = 2; i < _buf.length - 1; i++) {
      if (_buf[i] == 0xFF && _buf[i + 1] == 0xD9) { eoi = i + 2; break; }
    }
    if (eoi == -1) return; // frame chưa đủ, đợi chunk tiếp

    // Extract frame hoàn chỉnh
    final jpg = Uint8List.fromList(_buf.sublist(0, eoi));
    _buf.removeRange(0, eoi);

    if (mounted) setState(() => _frame = jpg);
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
    return Image.memory(
      _frame!,
      gaplessPlayback: true,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }
}
