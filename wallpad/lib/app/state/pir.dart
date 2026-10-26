part of '../app_state.dart';

/// 출발 시간대에만 PIR 로 화면을 켠다. 사람이 있으면 HIGH 가 이어지니 감지되는 동안 1초마다 본다
extension AppPir on AppState {
  void _startPir() {
    pirSensor.motions.listen((_) => _onPirMotion());
    pirSensor.start().ignore();
    _pirTick ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (pirSensor.active) _onPirMotion();
    });
  }

  void _onPirMotion() {
    if (!inLeaveWindow(clock())) return;
    if (stage == Stage.idle) return motion();
    if (screenOff) touched();
  }

  bool inLeaveWindow(DateTime now) {
    for (final u in users) {
      final p = profiles[u.id];
      final m = parseMinutes(p?.leaveTime);
      if (p == null || m == null || !p.goesOutOn(now)) continue;
      final leave = DateTime(now.year, now.month, now.day, m ~/ 60, m % 60);
      final from = leave.subtract(Duration(minutes: p.remindBefore ?? 20));
      final until = leave.add(pirAfterLeave);
      if (!now.isBefore(from) && now.isBefore(until)) return true;
    }
    return false;
  }
}
