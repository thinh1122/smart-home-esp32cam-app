class LogEntry {
  final int? id;
  final DateTime timestamp;
  final String action;
  final String detail;
  final String? imageUrl;

  const LogEntry({
    this.id,
    required this.timestamp,
    required this.action,
    required this.detail,
    this.imageUrl,
  });

  factory LogEntry.fromMap(Map<String, dynamic> map) => LogEntry(
    id: map['id'] as int?,
    timestamp: DateTime.tryParse(map['timestamp'] as String? ?? '') ?? DateTime.now(),
    action: map['action'] as String,
    detail: map['detail'] as String,
    imageUrl: map['imageUrl'] as String?,
  );

  String get timeString {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  bool get isSuccess => action.contains('thành công') || action.contains('✅');
  bool get isWarning => action.contains('Cảnh báo') || action.contains('⚠️');
}
