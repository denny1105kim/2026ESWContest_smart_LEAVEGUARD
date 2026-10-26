part of '../app_state.dart';

/// 전력 노드(MQTT)가 먼저, 노드가 없거나 명령이 안 먹으면 Shelly 플러그를 HTTP 로 직접 다룬다
extension AppPower on AppState {
  void _startPower() {
    powerLink.changes.listen((_) => _onPower());
    powerLink.start().ignore();
    shellyDirect.changes.listen((_) => _onPower());
    shellyDirect.start();
  }

  bool plugOn(String id) {
    if (shellyDirect.fresh(id)) return shellyDirect.output[id] == true;
    return appliances.where((a) => a.id == id).firstOrNull?.isOn ?? false;
  }

  void _onPower() {
    if (simulatePlugs) return;
    var changed = false;
    for (final a in appliances) {
      final direct = shellyDirect.fresh(a.id);
      final relayOff = direct && shellyDirect.output[a.id] == false; // 릴레이가 꺼졌으면 전류가 흐를 수 없다
      final off = _turnedOffAt[a.id];
      if (off != null && (powerLink.state[a.id] != 'IN_USE' || DateTime.now().difference(off) > const Duration(seconds: 30))) {
        _turnedOffAt.remove(a.id);
      }
      final amps = powerLink.known(a.id) ? powerLink.amps[a.id] ?? 0 : (direct ? shellyDirect.amps[a.id] ?? 0 : 0.0);
      final inUse = powerLink.known(a.id) ? powerLink.inUse(a.id) : direct && amps >= PowerLink.onAmps;
      final on = inUse && !relayOff && !_turnedOffAt.containsKey(a.id);
      if (on != a.on || (amps - a.currentA).abs() >= 0.05) {
        a
          ..on = on
          ..currentA = amps;
        changed = true;
      }
    }
    if (changed) _changed();
  }

  Future<bool> turnOff(String id) async {
    if (turningOff.contains(id)) return false;
    turningOff.add(id);
    turnOffErrors.remove(id);
    _changed();
    if (onBoard && !simulatePlugs) {
      var ok = powerLink.nodeUp && await powerLink.set(id, on: false, timeout: applianceOffTimeout);
      if (!ok && shellyDirect.has(id)) ok = await shellyDirect.set(id, on: false);
      turningOff.remove(id);
      if (ok) {
        _turnedOffAt[id] = DateTime.now();
      } else {
        turnOffErrors[id] = powerLink.nodeUp || shellyDirect.fresh(id) ? '끄지 못했어요. 다시 시도해 주세요' : '플러그와 연결이 안 돼요. 다시 시도해 주세요';
      }
      _onPower();
      _changed();
      return ok;
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    turningOff.remove(id);
    if (failNextTurnOff) {
      failNextTurnOff = false;
      turnOffErrors[id] = '끄지 못했어요. 다시 시도해 주세요';
      _changed();
      return false;
    }
    appliances.firstWhere((a) => a.id == id)
      ..currentA = 0
      ..on = false;
    _changed();
    return true;
  }

  void toggleAppliance(String id) {
    final a = appliances.firstWhere((a) => a.id == id);
    turnOffErrors.remove(id);
    if (onBoard && !simulatePlugs) {
      if (!turningOn.add(id)) return;
      _turnedOffAt.remove(id);
      if (powerLink.nodeUp) {
        powerLink.set(id, on: true).ignore();
      } else if (shellyDirect.has(id)) {
        shellyDirect.set(id, on: true).then((_) => _onPower()).ignore();
      }
      _changed();
      _waitPlugOn(id).ignore();
      return;
    }
    a.currentA = a.isOn ? 0 : 0.6 + (a.id.hashCode % 5) / 10;
    a.on = a.currentA > 0.05;
    _changed();
  }

  // 전력 노드를 거치면 릴레이가 켜지기까지 몇 초 걸린다. 그동안 다시 누르지 못하게 켜는 중으로 둔다
  Future<void> _waitPlugOn(String id) async {
    for (var i = 0; i < 20 && !plugOn(id); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    turningOn.remove(id);
    _changed();
  }
}
