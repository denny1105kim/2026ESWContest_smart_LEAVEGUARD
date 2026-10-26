import 'dart:typed_data';

class Member {
  final int id;
  final String name;

  const Member({required this.id, required this.name});

  factory Member.fromRow(Map<String, dynamic> row) {
    return Member(id: row['id'] as int, name: row['name'] as String);
  }
}

/// 요일 비트 (월 = 1 << 0 … 일 = 1 << 6): 월~금 · 매일
const weekdayBits = 0x1F, everyDayBits = 0x7F;

const essentialCandidates = ['휴대폰', '교통카드', '사원증', '학생증', '이어폰', '노트북', '약', '안경', '텀블러'];

/// 온보딩 생활 패턴. 답하지 않은 항목은 null
class MemberProfile {
  final String? weekdayPlace; // work · school · home · flexible · custom
  final String? scheduleMode; // fixed · calendar · manual · both · none
  final String? leaveTime, returnTime; // 'HH:MM'
  final int? days; // 요일 비트 (월=1 … 일=64)
  final int? remindBefore; // 출발 몇 분 전부터 체크리스트를 보여 줄지
  final String? transport; // car · transit · walk · varies
  final String? weekend; // rest · out · varies

  const MemberProfile({this.weekdayPlace, this.scheduleMode, this.leaveTime, this.returnTime, this.days, this.remindBefore, this.transport, this.weekend});

  factory MemberProfile.fromRow(Map<String, dynamic> r) => MemberProfile(
        weekdayPlace: r['weekday_place'] as String?,
        scheduleMode: r['schedule_mode'] as String?,
        leaveTime: r['leave_time'] as String?,
        returnTime: r['return_time'] as String?,
        days: r['days'] as int?,
        remindBefore: r['remind_before'] as int?,
        transport: r['transport'] as String?,
        weekend: r['weekend'] as String?,
      );

  bool goesOutOn(DateTime day) {
    final bits = days ?? weekdayBits;
    return bits & (1 << (day.weekday - 1)) != 0;
  }
}

class Situation {
  final int id;
  final String name;

  const Situation({required this.id, required this.name});

  factory Situation.fromRow(Map<String, dynamic> row) {
    return Situation(id: row['id'] as int, name: row['name'] as String);
  }
}

class OwnedBelonging {
  final int id;
  final List<int> memberIds; // 둘 이상이면 공용
  final String name;
  final String? spaceId; // 다른 특징 공간끼리는 비교하지 않는다
  final List<BelongingView> views;
  final Uint8List? thumbnail;
  final bool hardToDetect;

  /// 직접 그린 물건을 지켜볼 자리 [x, y, w, h] (트레이 사진 좌표)
  final List<int>? watchBox;

  const OwnedBelonging(this.id, this.memberIds, this.name, this.spaceId, this.views, {this.thumbnail, this.hardToDetect = false, this.watchBox});

  OwnedBelonging copyWith({List<int>? memberIds, String? name, String? spaceId, List<BelongingView>? views, List<int>? watchBox}) =>
      OwnedBelonging(id, memberIds ?? this.memberIds, name ?? this.name, spaceId ?? this.spaceId, views ?? this.views,
          thumbnail: thumbnail, hardToDetect: hardToDetect, watchBox: watchBox ?? this.watchBox);

  List<Float32List> get vectors => [for (final v in views) v.vector];
}

/// 물건이 트레이에 있던 구간. 보이는 중이면 until 이 null, closedBy = left · offline · restart
class Presence {
  final int id;
  final int belongingId;
  final DateTime from;
  final DateTime? until;
  final String? closedBy;
  final int? takenBy;

  const Presence(this.id, this.belongingId, this.from, this.until, this.closedBy, {this.takenBy});

  bool get open => until == null;

  Presence clampedTo(DateTime t) {
    final u = until;
    return Presence(id, belongingId, from.isAfter(t) ? t : from, u != null && u.isAfter(t) ? t : u, closedBy, takenBy: takenBy);
  }
}

class BelongingView {
  final int id;
  final Float32List vector;
  final String source;

  const BelongingView(this.id, this.vector, this.source);
}

class BelongingQuestion {
  final int id;
  final int belongingId;
  final String spaceId;
  final Float32List vector;
  final Uint8List? crop;
  final double score;
  final DateTime seenAt;

  const BelongingQuestion(this.id, this.belongingId, this.spaceId, this.vector, this.crop, this.score, this.seenAt);
}

class Item {
  final int id;
  final String label;
  final String displayName;

  const Item({
    required this.id,
    required this.label,
    required this.displayName,
  });

  factory Item.fromRow(Map<String, dynamic> row) {
    return Item(
      id: row['id'] as int,
      label: row['label'] as String,
      displayName: row['display_name'] as String,
    );
  }
}

class DayItem {
  final int memberId;
  final String day; // 'YYYY-MM-DD'
  final String kind;
  final String itemKey;
  final String? name;
  final DateTime at;

  const DayItem(this.memberId, this.day, this.kind, this.itemKey, this.name, this.at);
}
