import 'package:flutter/material.dart';

// ThinQ 가전 시뮬레이션. 실제 연동은 없고 앱을 다시 켜면 처음 목록으로 돌아간다

enum ThinqTone { running, done, idle, off }

class ThinqDevice {
  ThinqDevice({
    required this.id,
    required this.kind,
    required this.name,
    required this.model,
    required this.room,
    required this.tone,
    String? status,
    this.onMain = true,
    this.cleanAt,
    List<bool>? alerts,
  })  : status = status ?? ThinqSim.statusFor(kind, tone),
        alerts = alerts ?? [true, true, false];

  final String id, kind, name, model, room;
  ThinqTone tone;

  String status;
  bool onMain;

  /// "09:00", null 이면 자동 청소 끔
  String? cleanAt;

  /// 나갈 때 작동 중 · 끝나고 안 꺼냄 · 밤에 돌림
  final List<bool> alerts;

  bool get isRobot => kind == '로봇청소기';
  bool get isOn => tone == ThinqTone.running;
  String get initial => kind.characters.first;

  String get detail => [room, if (isRobot) cleanAt == null ? '자동 청소 꺼짐' : '매일 $cleanAt 자동 청소'].join(' · ');
}

class ThinqFound {
  const ThinqFound(this.name, this.model, this.room, {this.online = true, this.offlineDays = 0});

  final String name, model, room;
  final bool online;
  final int offlineDays;
}

class ThinqSim extends ChangeNotifier {
  ThinqSim._();

  static final instance = ThinqSim._();

  static const mainMax = 4;
  static const cleanTimes = ['07:00', '09:00', '13:00', '18:00'];

  static const kinds = ['세탁기', '건조기', '워시타워', '스타일러', '식기세척기', '로봇청소기', '에어컨', '공기청정기', '오븐', '냉장고'];
  static const otherKinds = '김치냉장고 · 정수기 · 제습기 · 가습기 · 쿡탑 · 후드 · 전자레인지 · 와인셀러 · 환기장치 …';

  final List<ThinqDevice> devices = [
    ThinqDevice(id: 'd1', kind: '세탁기', name: '트롬 오브제컬렉션', model: 'F21VDSK', room: '세탁실', tone: ThinqTone.running, status: '헹굼 중 · 23분 남음'),
    ThinqDevice(id: 'd2', kind: '건조기', name: '트롬', model: 'RH10VTA', room: '세탁실', tone: ThinqTone.done, status: '건조 끝 · 안 꺼냄'),
    ThinqDevice(id: 'd3', kind: '로봇청소기', name: '코드제로 R9', model: 'R975', room: '거실', tone: ThinqTone.idle, cleanAt: '09:00', alerts: [false, false, false]),
    ThinqDevice(id: 'd4', kind: '에어컨', name: '휘센 (거실)', model: 'FQ18', room: '거실', tone: ThinqTone.off, alerts: [true, false, false]),
  ];

  List<ThinqDevice> get mainDevices => devices.where((d) => d.onMain).take(mainMax).toList();

  static String statusFor(String kind, ThinqTone t) => switch (t) {
        ThinqTone.running => switch (kind) { '세탁기' || '워시타워' => '세탁 중', '건조기' => '건조 중', '로봇청소기' => '청소 중', _ => '작동 중' },
        ThinqTone.done => '끝남',
        ThinqTone.idle => kind == '로봇청소기' ? '충전 중' : '대기',
        ThinqTone.off => '꺼짐',
      };

  ThinqDevice? byId(String id) => devices.where((d) => d.id == id).firstOrNull;

  List<ThinqFound> foundFor(String kind) => [
        ThinqFound('트롬 오브제컬렉션 $kind', 'F21VDSK', '세탁실'),
        ThinqFound('트롬 워시타워 ($kind)', 'W16EX', '세탁실', online: false, offlineDays: 3),
      ];

  void add(String kind, ThinqFound f) {
    devices.add(ThinqDevice(
      id: 'd${DateTime.now().microsecondsSinceEpoch}',
      kind: kind,
      name: f.name.replaceAll(' $kind', ''),
      model: f.model,
      room: f.room,
      tone: ThinqTone.off,
      onMain: mainDevices.length < mainMax,
    ));
    notifyListeners();
  }

  void remove(String id) {
    devices.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  void togglePower(String id) {
    final d = byId(id);
    if (d == null) return;
    d.tone = d.tone == ThinqTone.done
        ? ThinqTone.off
        : d.isOn
            ? (d.isRobot ? ThinqTone.idle : ThinqTone.off)
            : ThinqTone.running;
    d.status = statusFor(d.kind, d.tone);
    notifyListeners();
  }

  void setCleanAt(String id, String? hhmm) {
    byId(id)?.cleanAt = hhmm;
    notifyListeners();
  }

  /// 이미 [mainMax] 개면 false
  bool setOnMain(String id, bool on) {
    final d = byId(id);
    if (d == null) return false;
    if (on && !d.onMain && mainDevices.length >= mainMax) return false;
    d.onMain = on;
    notifyListeners();
    return true;
  }

  void toggleAlert(String id, int i) {
    final d = byId(id);
    if (d == null) return;
    d.alerts[i] = !d.alerts[i];
    notifyListeners();
  }
}
