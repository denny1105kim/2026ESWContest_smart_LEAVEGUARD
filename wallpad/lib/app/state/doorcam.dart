part of '../app_state.dart';

/// 현관 카메라(ESP32-CAM): 3fps 에서 얼굴이 쌓이면 12fps 로 올려 누군지 확인하고 팝업을 띄운다
extension AppDoorCam on AppState {
  void _startDoorCam() {
    doorCamServer.frames.listen(_onDoorFrame);
    doorCamServer.start().ignore();
    doorCamLink.start().ignore();
    // 프레임이 안 오면 아무 일도 안 일어나니 끊김은 주기적으로 본다
    _doorWatch = Timer.periodic(const Duration(seconds: 5), (_) => _checkDoorOnline());
  }

  void _checkDoorOnline() {
    final at = _doorFrameAt;
    final online = at != null && DateTime.now().difference(at) < doorCamStale;
    if (online == doorOnline) return;
    doorOnline = online;
    if (!online && doorPhase != DoorPhase.idle) return _doorReset(tellCamera: false);
    _changed();
  }

  Future<void> _onDoorFrame(DoorFrame f) async {
    _doorFrameAt = f.at;
    doorFrame = f.jpeg;
    if (!doorOnline) {
      doorOnline = true;
      _changed();
    } else if (doorPhase != DoorPhase.idle) {
      _changed();
    }
    // vision 이 앞 장을 보는 중이면 이 장은 버린다. 답이 너무 안 오면 막힌 것으로 보고 세션을 새로 연다
    final busySince = _doorBusySince;
    if (busySince != null) {
      if (DateTime.now().difference(busySince) < doorVisionStuck) return;
      _doorSession = null;
    }
    _doorBusySince = DateTime.now();
    try {
      if (_doorSession == null) {
        await vision.start();
        _doorSession = vision.door(_onDoorVision, recognize: doorPhase != DoorPhase.idle);
      }
      await doorCamRecords.writeFrame(f.device, f.jpeg);
      _doorSession!.jpeg(doorCamRecords.framePath(f.device));
    } catch (_) {
      _doorBusySince = null;
    }
  }

  void _onDoorVision(VisionEvent e) {
    switch (e.type) {
      case 'seen':
        _doorBusySince = null;
        doorFaceBox = e.faceBox;
        doorRotation = e.faceRotation;
        _doorSeen(true);
      case 'none':
        _doorBusySince = null;
        doorFaceBox = null;
        _doorSeen(false);
      case 'bad':
        _doorBusySince = null;
      case 'face':
        _doorMatch(e);
      case 'error':
        _doorSession = null;
        _doorBusySince = null;
    }
  }

  void _doorSeen(bool face) {
    final now = DateTime.now();
    if (face) _doorLastFaceAt = now;
    if (doorPhase == DoorPhase.idle) {
      _doorWindow.add(face);
      if (_doorWindow.length > doorFaceWindow) _doorWindow.removeAt(0);
      final n = _doorWindow.where((v) => v).length;
      if (n != doorFaceFrames) {
        doorFaceFrames = n;
        _changed();
      }
      if (n >= doorFaceNeeded) _doorDetected();
      return;
    }
    final last = _doorLastFaceAt;
    if (doorPhase != DoorPhase.known && last != null && now.difference(last) >= doorGoneAfter) _doorReset(tellCamera: true);
  }

  void _doorDetected() {
    doorPhase = DoorPhase.confirming;
    _doorStartedAt = _doorLastFaceAt = DateTime.now();
    _doorHitsBy.clear();
    _doorFaces = 0;
    _doorMaxLive = 0;
    _doorMatchedAt = null;
    doorSpoofed = false;
    _doorWindow.clear();
    doorFaceFrames = 0;
    _doorSession?.recognize(true);
    doorCamLink.face('detected');
    _doorTimer?.cancel();
    _doorTimer = Timer(doorConfirmTimeout, () {
      if (doorPhase != DoorPhase.confirming) return;
      // 같은 사람으로는 맞았는데 실제 얼굴로 보인 장이 없었다 → 사진 · 화면
      doorSpoofed = _doorHitsBy.values.any((h) => h >= ScanConfig.confirmFrames);
      _doorUnknown();
    });
    _changed();
  }

  // 실제 사람도 위조 점수가 낮게 나오는 장이 많아 장마다 거르지 않고 세션 최고값으로 본다
  Future<void> _doorMatch(VisionEvent e) async {
    if (doorPhase != DoorPhase.confirming) return;
    _doorFaces++;
    _doorMaxLive = max(_doorMaxLive, e.liveness ?? 1);
    final member = await repo.findMemberByEmbedding(e.embedding, threshold: DoorCamConfig.threshold, margin: ScanConfig.margin);
    _doorLog(e, await repo.faceScores(e.embedding), member?.id);
    if (doorPhase != DoorPhase.confirming) return;
    if (member == null) {
      final started = _doorStartedAt;
      if (_doorHitsBy.isEmpty && _doorFaces >= doorUnknownAfterFaces && started != null && DateTime.now().difference(started) >= doorUnknownMinWait) {
        _doorUnknown();
      }
      return;
    }
    final hits = _doorHitsBy[member.id] = (_doorHitsBy[member.id] ?? 0) + 1;
    if (hits < ScanConfig.confirmFrames) return;
    if (_doorMaxLive >= doorLiveThreshold) return _doorKnown('${member.id}');
    final since = _doorMatchedAt ??= DateTime.now();
    if (DateTime.now().difference(since) >= doorSpoofAfter) {
      doorSpoofed = true;
      _doorUnknown();
    }
  }

  void _doorKnown(String id) {
    doorPhase = DoorPhase.known;
    doorUserId = id;
    doorCamLink.face('known');
    doorCamLink.openDoor(); // 도어락은 5초 뒤 스스로 잠근다
    _doorTimer?.cancel();
    final recent = _doorReturnedRecently(id);
    if (doorOffersReturn) return _doorCountdown(doorBusyOfferHold, () => _doorReset(tellCamera: false));
    _doorCountdown(doorKnownHold, () => !doorBusyScreen && !recent ? doorOpenScreen() : _doorReset(tellCamera: false));
  }

  void _doorUnknown() {
    doorPhase = DoorPhase.unknown;
    doorCamLink.face('unknown');
    _doorTimer?.cancel();
    final jpeg = doorFrame;
    if (jpeg != null) doorCamRecords.saveVisitor(jpeg);
    _doorCountdown(doorUnknownHold, () => _doorReset(tellCamera: false));
  }

  void _doorCountdown(int seconds, void Function() then) {
    doorSecondsLeft = seconds;
    _doorTick?.cancel();
    _doorTick = Timer.periodic(const Duration(seconds: 1), (t) {
      doorSecondsLeft--;
      if (doorSecondsLeft > 0) return _changed();
      t.cancel();
      then();
    });
    _changed();
  }

  void _doorReset({required bool tellCamera}) {
    _doorTimer?.cancel();
    _doorTick?.cancel();
    doorPhase = DoorPhase.idle;
    doorUserId = null;
    doorFaceBox = null;
    doorSecondsLeft = 0;
    doorOpened = false;
    doorSpoofed = false;
    _doorWindow.clear();
    doorFaceFrames = 0;
    _doorSession?.recognize(false);
    if (tellCamera) doorCamLink.face('idle');
    _changed();
  }

  // 기준값 조정용 로그 한 줄
  void _doorLog(VisionEvent e, Map<int, double> scores, int? matched) {
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = [for (final r in ranked.take(2)) '${r.key}:${r.value.toStringAsFixed(3)}'].join(' ');
    doorCamRecords.log('live=${e.liveness?.toStringAsFixed(2) ?? '-'} max=${_doorMaxLive.toStringAsFixed(2)} rot=$doorRotation yaw=${e.yaw.toStringAsFixed(0)} top=[$top] → ${matched ?? 'none'}');
  }

  // 누가 월패드를 쓰는 중이면 큰 팝업 대신 작은 창을 띄우고 로그인하지 않는다
  bool get doorBusyScreen => !screenOff && !const [Stage.idle, Stage.identifying, Stage.userSelect].contains(stage);

  void doorOpenReturn() {
    if (!doorOffersReturn) return;
    doorOpenScreen(force: true);
  }

  bool _doorReturnedRecently(String? id) {
    final last = returnedTodayAt(id);
    if (last == null) return false;
    final ago = clock().difference(last);
    // 화면 시각을 뒤로 옮겨 아직 오지 않은 귀가는 세지 않는다
    return !ago.isNegative && ago < doorReturnAgain;
  }

  // 온보딩 중에는 띄우지 않는다. 쓰던 등록을 접으면 임시 멤버가 남는다
  bool get doorOffersReturn =>
      doorPhase == DoorPhase.known && doorBusyScreen && !_doorReturnedRecently(doorUserId) && stage != Stage.onboarding && stage != Stage.welcome;

  void doorOpenScreen({bool force = false}) {
    final id = doorUserId;
    _doorReset(tellCamera: false);
    if (id == null || userOf(id) == null || (doorBusyScreen && !force)) return;
    _endSession();
    _greetTimer?.cancel();
    greetingUserId = null;
    auth = null;
    _enter(id);
    homecoming = true;
    _arriveHome(id);
    touched(); // 꺼져 있던 화면을 켠다
  }

  void doorDismiss() => _doorReset(tellCamera: true);

  void doorOpen() {
    if (doorPhase != DoorPhase.unknown || doorOpened) return;
    doorOpened = true;
    doorCamLink.openDoor();
    _doorCountdown(doorOpenedHold, () => _doorReset(tellCamera: false));
  }
}
