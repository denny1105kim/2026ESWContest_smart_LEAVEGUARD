import 'dart:async';

import 'package:flutter/material.dart';

import '../../shared/widgets/logo.dart';
import '../../app/app_state.dart';
import 'ob_widgets.dart';
import '../../core/config/app_clock.dart';
import '../../shared/time_text.dart';

/// 멤버가 한 명도 없을 때의 첫 화면
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  late final Timer _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _clock.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = AppClock.now();
    return Material(
      color: Ob.bg,
      child: Row(
        children: [
          Container(
            width: 900,
            color: Ob.navy,
            padding: const EdgeInsets.fromLTRB(84, 0, 60, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(flex: 5),
                const LogoMark(height: 150, onDark: true),
                const SizedBox(height: 40),
                const Text('LeaveGuard', style: TextStyle(fontSize: 88, fontWeight: FontWeight.w300, color: Colors.white, letterSpacing: -1.5, height: 1.1)),
                const SizedBox(height: 14),
                Text('잊고 다니는 것 없게.', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.7))),
                const Spacer(flex: 4),
                Text('${hhmm(now)}  ·  ${dateText(now)}',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w500, color: Colors.white.withValues(alpha: 0.45))),
                const SizedBox(height: 64),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 100),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('안녕하세요', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w600, color: Ob.muted)),
                  const SizedBox(height: 14),
                  const Text('LeaveGuard를\n사용하실 건가요?', style: TextStyle(fontSize: 62, fontWeight: FontWeight.w800, color: Ob.text, height: 1.25, letterSpacing: -1.2)),
                  const SizedBox(height: 56),
                  ObButton('네, 시작할게요', width: 320, onTap: () => app.startOnboarding(Stage.welcome)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
