import 'package:flutter/widgets.dart';

// 체크 화면용 값. checklist_page.dart 에서 AppState 를 이것으로 바꿔 넘긴다

/// home · out 은 귀가 화면에서만 쓴다
enum MemberState { notStarted, pending, ready, departed, returned, home, out }

class FamilyMemberViewData {
  const FamilyMemberViewData({
    required this.id,
    required this.name,
    required this.color,
    required this.state,
    required this.remaining,
    this.departedLabel,
    this.returnedLabel,
  });

  final String id;
  final String name;
  final Color color;
  final MemberState state;

  final int remaining;
  final String? departedLabel;
  final String? returnedLabel;
}

/// leftOut: 귀가 때 두고 왔다고 한 소지품, note: 직접 적은 메모
enum ChecklistItemKind { weather, air, uv, essential, leftOut, note }

class ChecklistItemViewData {
  const ChecklistItemViewData({
    required this.id,
    required this.title,
    required this.reason,
    required this.isDone,
    required this.kind,
    this.icon,
  });

  final String id;
  final String title;
  final String reason;
  final bool isDone;
  final ChecklistItemKind kind;
  final IconData? icon;
}

// 트레이가 현관에서 안 보여 사람이 직접 누른다
class ReturnCheckItemViewData {
  const ReturnCheckItemViewData({required this.id, required this.name, required this.icon, required this.checked});

  final String id;
  final String name;
  final IconData icon;
  final bool checked;
}

/// 창이 닫혀 있으면 null
class ReturnCheckViewData {
  const ReturnCheckViewData({required this.items, required this.askLeftOut});

  final List<ReturnCheckItemViewData> items;
  final bool askLeftOut;

  List<String> get missing => [for (final i in items) if (!i.checked) i.name];
}

/// unknown(카메라 끊김)은 진행률에 넣지 않는다
enum TrayState { taken, onTray, takenByOther, notReturned, acknowledged, unknown }

class TrayItemViewData {
  const TrayItemViewData({
    required this.id,
    required this.name,
    required this.icon,
    required this.state,
    this.detail,
    this.backDetail,
    this.heldByOther = false,
    this.takenToday = false,
    this.daysAway = 0,
  });

  final String id;
  final String name;
  final IconData icon;
  final TrayState state;

  /// null 이면 상태 기본 문구
  final String? detail;
  final String? backDetail;

  /// 공용 물건을 다른 사람이 가지고 있다
  final bool heldByOther;
  final bool takenToday;
  final int daysAway;
}

class CalendarEventViewData {
  const CalendarEventViewData({required this.timeLabel, required this.title});

  final String timeLabel;
  final String title;
}

class CalendarViewData {
  const CalendarViewData({required this.isLinked, required this.loadFailed, required this.events, this.needsReauth = false});

  final bool isLinked;
  final bool loadFailed;
  final bool needsReauth;
  final List<CalendarEventViewData> events;
}

class FamilyTodoViewData {
  const FamilyTodoViewData({required this.id, required this.name, required this.timeLabel, required this.isDone, this.doneBy});

  final String id;
  final String name;
  final String timeLabel;
  final bool isDone;
  final String? doneBy;
}

class ApplianceViewData {
  const ApplianceViewData({
    required this.id,
    required this.name,
    required this.room,
    required this.currentAmp,
    required this.icon,
    required this.isOn,
    bool? plugOn,
    this.isBusy = false,
    this.errorMessage,
    this.status,
    this.alert = false,
    this.thinq = false,
  }) : _plugOn = plugOn;

  final String id;
  final String name;
  final String room;
  final double currentAmp;
  final IconData icon;

  /// 전류 기준 사용 중. 외출 경고는 이것만 센다
  final bool isOn;

  /// 플러그 릴레이 상태. 안 주면 [isOn]
  bool get plugOn => _plugOn ?? isOn;
  final bool? _plugOn;
  final bool isBusy;
  final String? errorMessage;

  /// 전류 대신 보일 상태 글 (ThinQ)
  final String? status;
  final bool alert;

  /// false 면 Shelly 플러그
  final bool thinq;
}

class WeatherHourViewData {
  const WeatherHourViewData({required this.label, required this.temperature, required this.rainChance, required this.icon});

  final String label;
  final int temperature;
  final int rainChance;
  final IconData icon;
}

class WeatherViewData {
  const WeatherViewData({
    required this.location,
    required this.temperature,
    required this.high,
    required this.low,
    required this.condition,
    required this.rainChance,
    this.icon,
    this.source,
    this.notice,
    this.hours = const [],
  });

  /// 비어 있으면 날씨 타일을 누를 수 없다
  final List<WeatherHourViewData> hours;

  final String location;
  final double temperature;
  final double high;
  final double low;
  final String condition;
  final int rainChance;
  final IconData? icon;

  /// 공공누리 출처 표시라 빼면 안 된다
  final String? source;

  /// 숫자 대신 보일 안내 (불러오는 중·실패 등)
  final String? notice;
}

/// lastOut: 마지막으로 나가는데 켜진 가전이 있다
enum BarMode { progress, ready, lastOut, departed }

/// 같은 이름의 물건은 한 칸에 모은다
class GroupThingViewData {
  const GroupThingViewData({required this.name, required this.icon, required this.common, required this.done, this.reason = '', this.waiting = const []});

  final String name;
  final IconData icon;

  /// 날씨 때문에 모두에게 뜨는 물건
  final bool common;
  final bool done;
  final String reason;

  /// 아직 안 챙긴 사람 (이름, 색)
  final List<(String, Color)> waiting;
}

class GroupViewData {
  const GroupViewData({required this.memberIds, required this.things, required this.total, required this.done, required this.leftByPerson});

  /// 맨 앞이 조작하는 사람
  final List<String> memberIds;
  final List<GroupThingViewData> things;

  /// 공용 물건은 하나, 개인 물건은 사람마다 하나로 센다
  final int total, done;

  /// (이름, 색, 남은 물건들)
  final List<(String, Color, List<String>)> leftByPerson;
}

class GroupPickViewData {
  const GroupPickViewData({required this.meName, required this.meColor, required this.candidates, required this.picked});

  final String meName;
  final Color meColor;

  /// (id, 이름, 색)
  final List<(String, String, Color)> candidates;
  final Set<String> picked;
}
