import 'package:flutter/material.dart';

import 'app_state.dart';
import '../core/theme/tokens.dart';
import 'stage_view.dart';

class LeaveGuardApp extends StatelessWidget {
  const LeaveGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = WallpadTheme.light();
    return AppScope(
      child: MaterialApp(
        title: 'LeaveGuard',
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          splashColor: Palette.accent.withValues(alpha: 0.08),
          highlightColor: Palette.accent.withValues(alpha: 0.04),
        ),
        home: const StageView(),
      ),
    );
  }
}
