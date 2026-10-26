part of '../app_state.dart';

extension AppAuth on AppState {
  bool hasPin(String id) => _pins.containsKey(id);
  PinLock pinLockOf(String id) => _pinLocks.putIfAbsent(id, PinLock.new);

  void requestAuth(String id, AuthPurpose purpose, void Function() then) {
    auth = AuthRequest(id, purpose, then);
    _changed();
  }

  void cancelAuth() {
    final a = auth;
    auth = null;
    if (a?.purpose == AuthPurpose.create) return go(Stage.userSelect);
    _changed();
  }

  PinResult submitPin(String pin) {
    final a = auth;
    if (a == null) return PinResult.wrong;
    final lock = pinLockOf(a.userId);
    final now = DateTime.now();
    if (lock.remaining(now) != null) return PinResult.locked;
    final stored = _pins[a.userId];
    if (stored != null && Pin.verify(pin, stored)) {
      lock.succeeded();
      _authPassed();
      return PinResult.ok;
    }
    lock.failed(now);
    _changed();
    return lock.remaining(now) != null ? PinResult.locked : PinResult.wrong;
  }

  void faceVerified(String memberId) {
    final a = auth;
    if (a == null || a.userId != memberId) return;
    pinLockOf(memberId).succeeded();
    _authPassed();
  }

  Future<void> createPin(String pin) async {
    final a = auth;
    if (a == null) return;
    final hash = Pin.create(pin);
    final memberId = int.tryParse(a.userId);
    if (onBoard && memberId != null) await repo.savePin(memberId, hash);
    _pins[a.userId] = hash;
    _authPassed();
  }

  void _authPassed() {
    final a = auth!;
    auth = null;
    a.then();
    _changed();
  }

  void devPassAuth() {
    if (auth != null) _authPassed();
  }
}
