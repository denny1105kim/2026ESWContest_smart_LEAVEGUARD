import '../../core/data/models.dart';
import '../../shared/time_text.dart';

/// 보는 사람 기준의 트레이 소지품 상태.
///   taken        마지막 귀가 뒤 트레이에 있다가 사라졌다
///   notReturned  마지막 귀가 뒤 한 번도 트레이에 없었다
///   acknowledged 위 둘이나 takenByOther 를 [알고 있어요] 로 확인했다
enum TrayStatus { onTray, taken, takenByOther, notReturned, acknowledged, unknown }

class TrayInfo {
  final TrayStatus status;
  final DateTime? at;
  final String? by; // member id

  const TrayInfo(this.status, {this.at, this.by});

  bool heldByOther(String? viewerId) => by != null && by != viewerId;
}

/// [segments] 는 seen_from 오름차순. [lastReturnAt] 이 없으면 [fallback] 전을 기준점으로 쓴다.
TrayInfo trayStatusOf({
  required List<Presence> segments,
  required bool acked,
  required DateTime? lastReturnAt,
  required bool cameraOnline,
  required DateTime now,
  required Duration fallback,
  required String viewerId,
  required bool shared,
}) {
  if (!cameraOnline) return const TrayInfo(TrayStatus.unknown);
  if (segments.any((s) => s.open)) return const TrayInfo(TrayStatus.onTray);
  final anchor = lastReturnAt ?? now.subtract(fallback);
  String? by(Presence? s) => s?.takenBy == null ? null : '${s!.takenBy}';
  final seenSinceReturn = segments.any((s) => (s.until ?? now).isAfter(anchor));
  if (seenSinceReturn) {
    final s = segments.last;
    final at = s.closedBy == 'left' ? s.until : null;
    final who = s.closedBy == 'left' ? by(s) : null;
    final other = who != null ? who != viewerId : shared && s.closedBy == 'left';
    if (!other) return TrayInfo(TrayStatus.taken, at: at, by: who);
    return TrayInfo(acked ? TrayStatus.acknowledged : TrayStatus.takenByOther, at: at, by: who);
  }
  // 트레이가 꺼지거나 앱이 다시 켜져 닫힌 구간도 마지막으로 본 시각이다
  final lastSeen = segments.isEmpty ? null : segments.last;
  return TrayInfo(acked ? TrayStatus.acknowledged : TrayStatus.notReturned, at: lastSeen?.until, by: lastSeen?.closedBy == 'left' ? by(lastSeen) : null);
}

/// "오늘 08:12" · "어제 07:52" · "10월 8일 07:52"
String whenLabel(DateTime t, DateTime now) {
  final hm = hhmm(t);
  final d = DateTime(now.year, now.month, now.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (d <= 0) return '오늘 $hm';
  if (d == 1) return '어제 $hm';
  return '${t.month}월 ${t.day}일 $hm';
}
