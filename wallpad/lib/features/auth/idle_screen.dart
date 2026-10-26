import 'package:flutter/material.dart';

import '../../app/app_state.dart';

/// 화면 꺼짐. 누르면 모션으로 친다
class IdleScreen extends StatelessWidget {
  const IdleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: app.motion,
      child: const ColoredBox(color: Colors.black, child: SizedBox.expand()),
    );
  }
}
