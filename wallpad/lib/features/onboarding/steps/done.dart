part of '../onboarding_screen.dart';

extension _DoneView on _OnboardingScreenState {
  Widget _doneView() {
    final u = _user;
    final name = u?.name ?? _name;
    final tray = app.myBelongings.map((b) => b.name).toList();
    final pattern = switch (_mode) {
      'fixed' => '${_days == weekdayBits ? '평일' : '정해진 요일'} ${minutesText(_leave)} $_leaveWord',
      'none' => '재택근무',
      _ => '나중에 설정',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 760,
          color: Ob.navy,
          padding: const EdgeInsets.fromLTRB(84, 0, 60, 90),
          child: Stack(
            children: [
              Align(
                alignment: const Alignment(0, -0.35),
                child: Container(
                  width: 520,
                  height: 520,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0x14FFFFFF), shape: BoxShape.circle),
                  child: Container(
                    width: 380,
                    height: 380,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(color: Color(0x1FFFFFFF), shape: BoxShape.circle),
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: const BoxDecoration(color: Ob.green, shape: BoxShape.circle),
                      child: const Icon(Icons.check_rounded, size: 130, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const Align(
                alignment: Alignment.bottomLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('READY TO GO', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Ob.muted, letterSpacing: 1)),
                    SizedBox(height: 12),
                    Text('가볍게, 안심하고\n외출하세요.', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w300, color: Colors.white, height: 1.35)),
                  ],
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(110, 0, 90, 0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('설정이 모두 끝났어요!', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Ob.green)),
                const SizedBox(height: 18),
                Text('$name님,\n이제 LeaveGuard가 함께해요.', style: const TextStyle(fontSize: 58, fontWeight: FontWeight.w800, color: Ob.text, height: 1.3, letterSpacing: -1)),
                const SizedBox(height: 56),
                Row(
                  children: [
                    Expanded(child: _Summary(icon: Icons.schedule_rounded, title: '나의 생활 패턴', value: pattern)),
                    const SizedBox(width: 20),
                    Expanded(child: _Summary(icon: Icons.photo_camera_outlined, title: '등록 소지품', value: tray.isEmpty ? '없음' : tray.join(' · '))),
                    const SizedBox(width: 20),
                    Expanded(child: _Summary(icon: Icons.calendar_month_outlined, title: '캘린더 연결', value: u?.calendarLinked == true ? '연결 완료' : '나중에')),
                  ],
                ),
                const SizedBox(height: 90),
                Row(
                  children: [
                    InkWell(
                      onTap: _restart,
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 16),
                        child: Text('+  다른 가족도 등록하기', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, color: Ob.accent)),
                      ),
                    ),
                    const Spacer(),
                    ObButton('LeaveGuard 시작하기  →', width: 360, onTap: u == null ? null : () => app.finishOnboarding(u)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
