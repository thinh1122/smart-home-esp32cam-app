import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/mqtt_service.dart';
import '../../../core/services/database_helper.dart';
import '../../../core/services/auth_service.dart';
import '../../widgets/painters/brightness_ring_painter.dart';

// Model 1 hẹn giờ — luu/chay tren ESP32 (NVS + NTP), Flutter chi hien thi va dong bo qua MQTT
class _ScheduleEntry {
  final String id;
  bool turnOn;
  int hour;
  int minute;
  bool enabled;
  Duration remaining;

  _ScheduleEntry({
    required this.id,
    required this.turnOn,
    required this.hour,
    required this.minute,
    this.enabled = true,
  }) : remaining = _calcRemaining(hour, minute);

  static Duration _calcRemaining(int h, int m) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, h, m);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  String get timeLabel =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

class LivingRoomLightScreen extends StatefulWidget {
  final String room;
  final bool initialOn;
  const LivingRoomLightScreen({super.key, this.room = 'living_room', this.initialOn = false});

  @override
  State<LivingRoomLightScreen> createState() => _LivingRoomLightScreenState();
}

class _LivingRoomLightScreenState extends State<LivingRoomLightScreen> {
  late bool _isOn;
  double _brightness = 1.0;
  Timer? _brightnessDebounce;

  final List<_ScheduleEntry> _schedules = [];
  Timer? _countdownTicker;

  StreamSubscription? _stateSub;
  String get _topicSchedSet  => 'home/devices/light/${widget.room}/schedule/set';
  String get _topicSchedDel  => 'home/devices/light/${widget.room}/schedule/delete';
  String get _topicSchedList => 'home/devices/light/${widget.room}/schedule/list';

  @override
  void initState() {
    super.initState();
    _isOn = widget.initialOn;
    DatabaseHelper.instance.getDevicesByRoom(widget.room, userId: AuthService.instance.userId).then((rows) {
      if (rows.isNotEmpty && mounted) {
        setState(() => _isOn = (rows.first['state'] as String?)?.toUpperCase() == 'ON');
      }
    });
    _stateSub = MQTTService().deviceStateStream.listen((msg) {
      final topic = msg['topic'] as String;
      final data  = msg['data'];
      if (topic == 'home/devices/light/${widget.room}/state') {
        final map = data as Map<String, dynamic>;
        final stateStr = (map['state'] as String?)?.toUpperCase() ?? 'OFF';
        final on = stateStr == 'ON';
        if (mounted) setState(() => _isOn = on);
        DatabaseHelper.instance.updateDeviceState(widget.room, stateStr, userId: AuthService.instance.userId);
      } else if (topic == _topicSchedList) {
        final list = data as List<dynamic>;
        if (mounted) {
          setState(() {
            _schedules.clear();
            for (final raw in list) {
              final o = raw as Map<String, dynamic>;
              _schedules.add(_ScheduleEntry(
                id:      o['id'] as String,
                turnOn:  o['turnOn'] as bool? ?? false,
                hour:    (o['hour']   as num?)?.toInt() ?? 0,
                minute:  (o['minute'] as num?)?.toInt() ?? 0,
                enabled: o['enabled'] as bool? ?? false,
              ));
            }
          });
        }
      }
    });
    // ESP32 luu va kich hoat hen gio — Flutter chi can dem ngược hien thi
    _countdownTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        for (final s in _schedules) {
          if (s.enabled) s.remaining = _ScheduleEntry._calcRemaining(s.hour, s.minute);
        }
      });
    });
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _brightnessDebounce?.cancel();
    _countdownTicker?.cancel();
    super.dispose();
  }

  void _toggleLight(bool v) {
    setState(() => _isOn = v);
    MQTTService().controlLight(widget.room, v);
    DatabaseHelper.instance.updateDeviceState(widget.room, v ? 'ON' : 'OFF', userId: AuthService.instance.userId);
    if (v) {
      setState(() => _brightness = 1.0);
      _publishBrightness(1.0);
    }
  }

  void _publishBrightness(double value) {
    _brightnessDebounce?.cancel();
    _brightnessDebounce = Timer(const Duration(milliseconds: 300), () {
      MQTTService().publish('home/devices/light/${widget.room}/brightness', {
        'brightness': (value * 100).round(),
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    });
  }

  // ── Thêm hẹn giờ mới — gửi cho ESP32 lưu NVS và tự kích hoạt qua NTP ──
  void _addSchedule(int hour, int minute, bool turnOn) {
    final id = 'sch_${DateTime.now().millisecondsSinceEpoch}';
    final entry = _ScheduleEntry(id: id, turnOn: turnOn, hour: hour, minute: minute, enabled: true);
    setState(() => _schedules.insert(0, entry));
    MQTTService().publish(_topicSchedSet, {
      'id': id, 'hour': hour, 'minute': minute, 'turnOn': turnOn, 'enabled': true,
    });
  }

  // ── Bật/tắt 1 hẹn giờ ───────────────────────────────────────
  void _toggleSchedule(_ScheduleEntry entry, bool val) {
    setState(() => entry.enabled = val);
    MQTTService().publish(_topicSchedSet, {
      'id': entry.id, 'hour': entry.hour, 'minute': entry.minute,
      'turnOn': entry.turnOn, 'enabled': val,
    });
  }

  // ── Xoá 1 hẹn giờ ───────────────────────────────────────────
  void _deleteSchedule(String id) {
    final idx = _schedules.indexWhere((s) => s.id == id);
    if (idx < 0) return;
    setState(() => _schedules.removeAt(idx));
    MQTTService().publish(_topicSchedDel, {'id': id});
  }

  void _showTimerPicker() {
    final ac = AC.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: ac.card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _TimerPickerSheet(
        currentlyOn: _isOn,
        schedules: List.unmodifiable(_schedules),
        onAdd: (hour, minute, turnOn) {
          Navigator.pop(ctx);
          _addSchedule(hour, minute, turnOn);
        },
        onToggle: (id, val) {
          final s = _schedules.firstWhere((e) => e.id == id, orElse: () => _schedules.first);
          _toggleSchedule(s, val);
          setState(() {});
        },
        onDelete: (id) {
          _deleteSchedule(id);
        },
      ),
    );
  }

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
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
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            SliverToBoxAdapter(child: _buildBrightnessCard(ac)),
            if (_schedules.isNotEmpty) ...[
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              SliverToBoxAdapter(child: _buildScheduleList(ac)),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
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
          Row(
            children: [
              if (Navigator.canPop(context))
                IconButton(
                  icon: Icon(Icons.arrow_back_ios_rounded, color: ac.textSecondary),
                  onPressed: () => Navigator.pop(context),
                ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_roomLabel(widget.room),
                      style: TextStyle(color: ac.textPrimary, fontSize: 22, fontWeight: FontWeight.bold)),
                  Text('Điều khiển đèn · ${widget.room}',
                      style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                ],
              ),
            ],
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: _isOn ? ac.accentDim : ac.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _isOn ? ac.accentLight.withOpacity(0.4) : ac.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 8, height: 8,
                      decoration: BoxDecoration(
                          color: _isOn ? ac.success : ac.textDim,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Text(_isOn ? 'ON' : 'OFF',
                      style: TextStyle(
                          color: _isOn ? ac.accentLight : ac.textSecondary,
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Switch(
                value: _isOn,
                onChanged: _toggleLight,
                activeColor: ac.accentLight,
                activeTrackColor: ac.accentDim,
                inactiveThumbColor: ac.iconMuted,
                inactiveTrackColor: ac.border,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessCard(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        decoration: BoxDecoration(
          color: ac.card,
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: ac.border),
        ),
        child: Column(
          children: [
            GestureDetector(
              onPanUpdate: (details) {
                if (!_isOn) return;
                const center = Offset(120, 120);
                final pos = details.localPosition;
                final angle = atan2(pos.dy - center.dy, pos.dx - center.dx);
                final norm = (angle - pi / 2) / (2 * pi);
                final newBrightness = (norm + 1) % 1;
                setState(() => _brightness = newBrightness);
                _publishBrightness(newBrightness);
              },
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 240, height: 240,
                    child: CustomPaint(
                      painter: BrightnessRingPainter(
                        percentage: _isOn ? _brightness : 0,
                        accentColor: _isOn ? ac.accentLight : ac.iconFaint,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('BRIGHTNESS',
                        style: TextStyle(
                            color: _isOn ? ac.textSecondary : ac.textDim,
                            fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isOn ? '${(_brightness * 100).round()}%' : 'OFF',
                        style: TextStyle(
                          color: _isOn ? ac.textPrimary : ac.textSecondary,
                          fontSize: 52, fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.wb_sunny_rounded,
                              color: _isOn ? ac.lightColor : ac.iconFaint, size: 15),
                          const SizedBox(width: 6),
                          Text(
                            _isOn ? 'Đang bật' : 'Đang tắt',
                            style: TextStyle(
                                color: _isOn ? ac.lightColor : ac.textDim,
                                fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(child: _ctrlBtn(ac,
                  Icons.power_settings_new_rounded, 'BẬT/TẮT', !_isOn,
                  () => _toggleLight(!_isOn),
                )),
                const SizedBox(width: 14),
                Expanded(child: _ctrlBtn(ac,
                  Icons.timer_rounded, 'HẸN GIỜ',
                  _schedules.any((s) => s.enabled),
                  _showTimerPicker,
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleList(AC ac) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Hẹn giờ', style: TextStyle(color: ac.textSecondary, fontSize: 13,
                    fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                Text('${_schedules.where((s) => s.enabled).length} đang bật',
                    style: TextStyle(color: ac.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: ac.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ac.border),
            ),
            child: Column(
              children: _schedules.asMap().entries.map((e) {
                final i = e.key;
                final s = e.value;
                return Column(
                  children: [
                    Dismissible(
                      key: Key(s.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 20),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(
                              i == 0 && _schedules.length == 1 ? 20
                            : i == 0 ? 20 : i == _schedules.length - 1 ? 20 : 0),
                        ),
                        child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                      ),
                      onDismissed: (_) => _deleteSchedule(s.id),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s.timeLabel,
                                      style: TextStyle(
                                          color: s.enabled ? ac.textPrimary : ac.textSecondary,
                                          fontSize: 34, fontWeight: FontWeight.w300,
                                          letterSpacing: -1)),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Icon(
                                        s.turnOn ? Icons.power_rounded : Icons.power_off_rounded,
                                        color: s.enabled
                                            ? (s.turnOn ? ac.accentLight : Colors.blueGrey.shade300)
                                            : ac.textDim,
                                        size: 13,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        s.turnOn ? 'Hẹn bật' : 'Hẹn tắt',
                                        style: TextStyle(
                                            color: s.enabled ? ac.textSecondary : ac.textDim,
                                            fontSize: 12),
                                      ),
                                      if (s.enabled) ...[
                                        const SizedBox(width: 8),
                                        Text('· ${_formatRemaining(s.remaining)}',
                                            style: TextStyle(
                                                color: s.turnOn ? ac.accentLight : Colors.blueGrey.shade300,
                                                fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: s.enabled,
                              onChanged: (val) => _toggleSchedule(s, val),
                              activeColor: ac.accentLight,
                              activeTrackColor: ac.accentDim,
                              inactiveThumbColor: ac.iconMuted,
                              inactiveTrackColor: ac.border,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (i < _schedules.length - 1)
                      Divider(height: 1, color: ac.divider, indent: 18),
                  ],
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Text('Vuốt sang trái để xoá', style: TextStyle(color: ac.textDim, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _ctrlBtn(AC ac, IconData icon, String label, bool isActive, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? 0.35 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 22),
          decoration: BoxDecoration(
            color: isActive ? ac.accentDim : ac.border,
            borderRadius: BorderRadius.circular(36),
            border: Border.all(
                color: isActive ? ac.accentLight.withOpacity(0.3) : ac.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: isActive ? ac.accentLight : ac.textSecondary, size: 26),
              const SizedBox(height: 10),
              Text(label,
                  style: TextStyle(
                      color: isActive ? ac.accentLight : ac.textSecondary,
                      fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
            ],
          ),
        ),
      ),
    );
  }

  String _roomLabel(String key) {
    const map = {
      'living_room': 'Phòng khách', 'bedroom': 'Phòng ngủ',
      'kitchen': 'Nhà bếp', 'bathroom': 'Nhà vệ sinh',
      'bedroom2': 'Phòng ngủ 2', 'garage': 'Nhà xe',
    };
    return map[key] ?? key;
  }
}

// ── Bottom sheet thêm hẹn giờ mới ───────────────────────────────
class _TimerPickerSheet extends StatefulWidget {
  final bool currentlyOn;
  final List<_ScheduleEntry> schedules;
  final void Function(int hour, int minute, bool turnOn) onAdd;
  final void Function(String id, bool val) onToggle;
  final void Function(String id) onDelete;

  const _TimerPickerSheet({
    required this.currentlyOn,
    required this.schedules,
    required this.onAdd,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  State<_TimerPickerSheet> createState() => _TimerPickerSheetState();
}

class _TimerPickerSheetState extends State<_TimerPickerSheet> {
  late bool _turnOn;
  // 0 = Lịch sử, 1 = Đếm ngược, 2 = Giờ cụ thể
  int _tab = 0;

  int _cdHour = 0;
  int _cdMin  = 30;

  late FixedExtentScrollController _hourCtrl;
  late FixedExtentScrollController _minCtrl;
  int _targetHour = 0;
  int _targetMin  = 0;

  @override
  void initState() {
    super.initState();
    _turnOn = !widget.currentlyOn;
    final now = DateTime.now();
    _targetHour = now.hour;
    _targetMin  = now.minute;
    _hourCtrl = FixedExtentScrollController(initialItem: _targetHour);
    _minCtrl  = FixedExtentScrollController(initialItem: _targetMin);
    // Nếu đã có hẹn giờ thì mở thẳng tab lịch sử
    _tab = widget.schedules.isNotEmpty ? 0 : 1;
  }

  @override
  void dispose() {
    _hourCtrl.dispose();
    _minCtrl.dispose();
    super.dispose();
  }

  Duration _durationUntil(int h, int m) {
    final now = DateTime.now();
    var target = DateTime(now.year, now.month, now.day, h, m);
    if (!target.isAfter(now)) target = target.add(const Duration(days: 1));
    return target.difference(now);
  }

  String _formatRemaining(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final ac = AC.of(context);
    final accentColor = _turnOn ? ac.accentLight : Colors.blueGrey.shade300;
    final accentDim   = _turnOn ? ac.accentDim   : Colors.blueGrey.withOpacity(0.3);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Center(child: Container(width: 40, height: 4,
              decoration: BoxDecoration(color: ac.iconFaint, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 16),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: accentDim, borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.timer_rounded, color: accentColor, size: 20),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_turnOn ? 'Hẹn giờ bật đèn' : 'Hẹn giờ tắt đèn',
                          style: TextStyle(color: ac.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                      Text(_turnOn ? 'Đèn tự bật đúng giờ bạn chọn' : 'Đèn tự tắt đúng giờ bạn chọn',
                          style: TextStyle(color: ac.textSecondary, fontSize: 12)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _tab = 2),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: ac.accentDim,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.add_rounded, color: ac.accentLight, size: 20),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: ac.border,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  _tabBtn('Lịch sử',    Icons.history_rounded,         0, accentColor),
                  _tabBtn('Đếm ngược', Icons.hourglass_top_rounded,    1, accentColor),
                  _tabBtn('Giờ cụ thể', Icons.schedule_rounded,        2, accentColor),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: KeyedSubtree(
              key: ValueKey(_tab),
              child: _tab == 0 ? _buildHistoryTab()
                   : _tab == 1 ? _buildCountdownTab(accentColor, accentDim)
                   :             _buildTargetTimeTab(accentColor, accentDim),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Tab Lịch sử (giống iOS Clock) ──
  Widget _buildHistoryTab() {
    final ac = AC.of(context);
    if (widget.schedules.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: ac.border,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              Icon(Icons.timer_off_rounded, color: ac.iconFaint, size: 36),
              const SizedBox(height: 10),
              Text('Chưa có hẹn giờ nào', style: TextStyle(color: ac.textSecondary, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Bấm + hoặc chọn tab "Đếm ngược" / "Giờ cụ thể" để thêm',
                  style: TextStyle(color: ac.textDim, fontSize: 11), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: ac.cardElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ac.border),
        ),
        child: Column(
          children: widget.schedules.asMap().entries.map((e) {
            final i = e.key;
            final s = e.value;
            return Column(
              children: [
                Dismissible(
                  key: Key(s.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: Colors.redAccent.withOpacity(0.15),
                    child: const Icon(Icons.delete_rounded, color: Colors.redAccent),
                  ),
                  onDismissed: (_) {
                    widget.onDelete(s.id);
                    setState(() {});
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.timeLabel,
                                  style: TextStyle(
                                      color: s.enabled ? ac.textPrimary : ac.textSecondary,
                                      fontSize: 36, fontWeight: FontWeight.w300,
                                      letterSpacing: -1)),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(
                                    s.turnOn ? Icons.power_rounded : Icons.power_off_rounded,
                                    color: s.enabled
                                        ? (s.turnOn ? ac.accentLight : Colors.blueGrey.shade300)
                                        : ac.textDim,
                                    size: 13,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    s.turnOn ? 'Hẹn bật' : 'Hẹn tắt',
                                    style: TextStyle(
                                        color: s.enabled ? ac.textSecondary : ac.textDim,
                                        fontSize: 12),
                                  ),
                                  if (s.enabled) ...[
                                    const SizedBox(width: 6),
                                    Text('· ${_formatRemaining(s.remaining)}',
                                        style: TextStyle(
                                            color: s.turnOn ? ac.accentLight : Colors.blueGrey.shade300,
                                            fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: s.enabled,
                          onChanged: (val) {
                            widget.onToggle(s.id, val);
                            setState(() => s.enabled = val);
                          },
                          activeColor: ac.accentLight,
                          activeTrackColor: ac.accentDim,
                          inactiveThumbColor: ac.iconMuted,
                          inactiveTrackColor: ac.border,
                        ),
                      ],
                    ),
                  ),
                ),
                if (i < widget.schedules.length - 1)
                  Divider(height: 1, color: ac.divider, indent: 18),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Tab Đếm ngược ──
  Widget _buildCountdownTab(Color accent, Color dim) {
    final ac = AC.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ac.border,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _modeBtn('Hẹn tắt', Icons.power_off_rounded, !_turnOn,
                    Colors.blueGrey.shade300, () => setState(() => _turnOn = false)),
                _modeBtn('Hẹn bật', Icons.power_rounded, _turnOn,
                    ac.accentLight, () => setState(() => _turnOn = true)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: ac.border,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ac.divider),
            ),
            child: Row(
              children: [
                Expanded(child: _spinnerCol('Giờ', _cdHour, 23,
                    (v) => setState(() => _cdHour = v), accent)),
                Text(':', style: TextStyle(color: accent, fontSize: 36, fontWeight: FontWeight.bold)),
                Expanded(child: _spinnerCol('Phút', _cdMin, 59,
                    (v) => setState(() => _cdMin = v), accent)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _confirmBtn(
            label: '${_turnOn ? 'Bật' : 'Tắt'} sau ${_cdHour}h ${_cdMin.toString().padLeft(2,'0')}m',
            enabled: _cdHour > 0 || _cdMin > 0,
            accent: accent, dim: dim,
            onTap: () {
              final now = DateTime.now();
              final target = now.add(Duration(hours: _cdHour, minutes: _cdMin));
              widget.onAdd(target.hour, target.minute, _turnOn);
            },
          ),
        ],
      ),
    );
  }

  // ── Tab Giờ cụ thể ──
  Widget _buildTargetTimeTab(Color accent, Color dim) {
    final ac = AC.of(context);
    final dur = _durationUntil(_targetHour, _targetMin);
    final durText = dur.inHours > 0
        ? 'sau ${dur.inHours}h ${dur.inMinutes.remainder(60)}m'
        : 'sau ${dur.inMinutes}m';
    final isNextDay = dur.inHours >= 22;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: ac.border,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                _modeBtn('Hẹn tắt', Icons.power_off_rounded, !_turnOn,
                    Colors.blueGrey.shade300, () => setState(() => _turnOn = false)),
                _modeBtn('Hẹn bật', Icons.power_rounded, _turnOn,
                    ac.accentLight, () => setState(() => _turnOn = true)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: ac.border,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: ac.divider),
            ),
            child: Row(
              children: [
                Expanded(child: _wheelCol('Giờ', _hourCtrl, 24,
                    (v) => setState(() => _targetHour = v), accent)),
                Text(':', style: TextStyle(color: accent, fontSize: 40, fontWeight: FontWeight.bold)),
                Expanded(child: _wheelCol('Phút', _minCtrl, 60,
                    (v) => setState(() => _targetMin = v), accent)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline_rounded, color: accent.withOpacity(0.6), size: 14),
              const SizedBox(width: 6),
              Text(
                isNextDay
                  ? 'Hẹn lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')} ngày mai ($durText)'
                  : 'Hẹn lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')} hôm nay ($durText)',
                style: TextStyle(color: accent.withOpacity(0.8), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _confirmBtn(
            label: '${_turnOn ? 'Bật' : 'Tắt'} lúc ${_targetHour.toString().padLeft(2,'0')}:${_targetMin.toString().padLeft(2,'0')}',
            enabled: true,
            accent: accent, dim: dim,
            onTap: () => widget.onAdd(_targetHour, _targetMin, _turnOn),
          ),
        ],
      ),
    );
  }

  Widget _spinnerCol(String label, int value, int max, ValueChanged<int> onChange, Color accent) {
    final ac = AC.of(context);
    return Column(
      children: [
        Text(label, style: TextStyle(color: ac.textSecondary, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _numBtn(Icons.remove_rounded, () { if (value > 0) onChange(value - 1); }),
            const SizedBox(width: 14),
            SizedBox(
              width: 48,
              child: Text(value.toString().padLeft(2,'0'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: accent, fontSize: 34, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 14),
            _numBtn(Icons.add_rounded, () { if (value < max) onChange(value + 1); }),
          ],
        ),
      ],
    );
  }

  Widget _wheelCol(String label, FixedExtentScrollController ctrl, int count, ValueChanged<int> onChange, Color accent) {
    final ac = AC.of(context);
    return Column(
      children: [
        Text(label, style: TextStyle(color: ac.textSecondary, fontSize: 11, letterSpacing: 1)),
        const SizedBox(height: 4),
        SizedBox(
          height: 150,
          child: ListWheelScrollView.useDelegate(
            controller: ctrl,
            itemExtent: 50,
            physics: const FixedExtentScrollPhysics(),
            perspective: 0.003,
            overAndUnderCenterOpacity: 0.3,
            onSelectedItemChanged: onChange,
            childDelegate: ListWheelChildBuilderDelegate(
              childCount: count,
              builder: (ctx, i) => Center(
                child: Text(i.toString().padLeft(2, '0'),
                    style: TextStyle(color: accent, fontSize: 32, fontWeight: FontWeight.bold)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeBtn(String label, IconData icon, bool active, Color color, VoidCallback onTap) {
    final ac = AC.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? color.withOpacity(0.5) : Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: active ? color : ac.iconMuted, size: 16),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: active ? color : ac.iconMuted,
                fontWeight: FontWeight.bold, fontSize: 13,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tabBtn(String label, IconData icon, int idx, Color accent) {
    final ac = AC.of(context);
    final active = _tab == idx;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = idx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? accent.withOpacity(0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: active ? accent : ac.iconMuted, size: 16),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                color: active ? accent : ac.iconMuted,
                fontSize: 10, fontWeight: FontWeight.bold,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _confirmBtn({
    required String label,
    required bool enabled,
    required Color accent,
    required Color dim,
    required VoidCallback onTap,
  }) {
    final ac = AC.of(context);
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onTap : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: accent.withOpacity(0.2),
          foregroundColor: accent,
          disabledBackgroundColor: ac.border,
          disabledForegroundColor: ac.iconMuted,
          padding: const EdgeInsets.symmetric(vertical: 15),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: enabled ? accent.withOpacity(0.4) : Colors.transparent),
          ),
        ),
        child: Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _numBtn(IconData icon, VoidCallback onTap) {
    final ac = AC.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          color: ac.border,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: ac.textSecondary, size: 18),
      ),
    );
  }
}
