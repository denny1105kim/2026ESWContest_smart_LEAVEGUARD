part of '../onboarding_screen.dart';

extension _CalendarStep on _OnboardingScreenState {
  Widget _calendarBody() {
    final u = app.user;
    final linked = u?.calendarLinked == true;
    final url = app.calendarLinkUrl;
    final exp = app.calendarLinkExpires;
    final left = exp == null ? Duration.zero : exp.difference(DateTime.now());
    final expired = exp != null && left.isNegative;
    final error = app.calendarError;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 560,
          height: 520,
          child: ObPanel(
            child: Column(
              children: [
                Container(
                  height: 64,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(color: Ob.accentTint, borderRadius: BorderRadius.circular(14)),
                  child: const Row(
                    children: [
                      Icon(Icons.calendar_month_outlined, color: Ob.accent, size: 30),
                      SizedBox(width: 14),
                      Text('Google Calendar', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: Ob.text)),
                    ],
                  ),
                ),
                const Spacer(),
                if (linked)
                  const Icon(Icons.check_circle_rounded, size: 200, color: Ob.green)
                else if (url == null)
                  const SizedBox(height: 280, child: Center(child: CircularProgressIndicator(color: Ob.accent)))
                else
                  QrPanel(data: url, size: 280, expired: expired || error != null),
                const Spacer(),
                Text(linked ? '연결됐어요' : '스마트폰으로 QR코드를 스캔해 연결',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: linked ? Ob.green : Ob.text)),
                const SizedBox(height: 6),
                if (!linked && exp != null && !expired)
                  Text('${mmss(left)} 후 만료', style: const TextStyle(fontSize: 19, color: Ob.faint)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: SizedBox(
            height: 520,
            child: ObPanel(
              color: linked ? Ob.greenTint : (error != null || expired ? Ob.redTint : Ob.card),
              child: linked ? _calendarLinked() : (error != null || expired ? _calendarError(error ?? 'QR코드 시간이 지났어요') : _calendarWaiting()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _calendarWaiting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('연동하면 이렇게 보여요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Ob.text)),
        const SizedBox(height: 26),
        for (final (t, n) in const [('09:00', '회사 출근'), ('14:30', '병원 방문'), ('19:00', '저녁 약속')])
          Container(
            height: 76,
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(color: Ob.chip, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(t, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Ob.accent))),
                Text(n, style: Ob.label),
              ],
            ),
          ),
        const Spacer(),
        const Row(
          children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2.4, color: Ob.accent)),
            SizedBox(width: 12),
            Text('휴대폰에서 연결을 기다리는 중', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Ob.muted)),
          ],
        ),
      ],
    );
  }

  Widget _calendarLinked() {
    final events = app.myEvents;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Google 계정 연동 완료', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Ob.text)),
        const SizedBox(height: 26),
        const Text('오늘 일정', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Ob.muted)),
        const SizedBox(height: 14),
        if (events.isEmpty) const Text('오늘 일정이 없어요', style: Ob.label),
        for (final e in events.take(4))
          Container(
            height: 72,
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(color: Ob.chip, borderRadius: BorderRadius.circular(14)),
            child: Row(
              children: [
                SizedBox(width: 110, child: Text(e.time, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Ob.green))),
                Expanded(child: Text(e.title, style: Ob.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _calendarError(String message) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 64, color: Ob.red),
        const SizedBox(height: 20),
        const Text('연결을 확인할 수 없어요', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Ob.text)),
        const SizedBox(height: 10),
        Text(message, style: const TextStyle(fontSize: 21, color: Ob.muted, height: 1.4)),
        const Spacer(),
        ObButton('새 QR코드 발급', primary: false, width: 280, onTap: app.newCalendarQr),
      ],
    );
  }
}
