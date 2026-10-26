import 'package:flutter/material.dart';

import '../shared/widgets/design_canvas.dart';
import '../core/config/constants.dart';
import 'dev_panel.dart';
import '../features/auth/auth_overlay.dart';
import '../features/belongings/belonging_question.dart';
import '../features/belongings/tray_status_overlay.dart';
import '../features/checklist/checklist_page.dart';
import '../features/doorcam/door_cam_overlay.dart';
import '../features/auth/identifying_screen.dart';
import '../features/auth/idle_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/welcome_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/auth/user_select_screen.dart';
import 'app_state.dart';
import '../core/theme/tokens.dart';

class StageView extends StatefulWidget {
  const StageView({super.key});

  @override
  State<StageView> createState() => _StageViewState();
}

class _StageViewState extends State<StageView> {
  @override
  void initState() {
    super.initState();
    app.watchScreen(true);
  }

  @override
  void dispose() {
    app.watchScreen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final stage = app.stage;
        final Widget screen = switch (stage) {
          Stage.checklist => const DesignCanvas.fitWidth(child: ChecklistPage()),
          Stage.idle => const IdleScreen(),
          Stage.identifying => const DesignCanvas.legacy(child: IdentifyingScreen()),
          Stage.userSelect => const DesignCanvas.legacy(child: UserSelectScreen()),
          Stage.returning => const DesignCanvas.fitWidth(child: ReturnPage()),
          Stage.settings => const DesignCanvas.legacy(child: SettingsScreen()),
          Stage.welcome => const DesignCanvas(size: WallpadTokens.designSize, child: WelcomeScreen()),
          Stage.onboarding => const DesignCanvas(size: WallpadTokens.designSize, child: OnboardingScreen()),
        };
        final question = app.activeQuestion;
        // 키보드 · 확인 창 같은 라우트가 위에 떠 있으면 false
        final onTop = ModalRoute.of(context)?.isCurrent ?? true;
        return Listener(
          behavior: HitTestBehavior.translucent,
          // 빠르게 누르는 화면이나 창 · 트레이 판이 떠 있으면 두 번 톡톡으로 끄지 않는다
          onPointerDown: (e) => app.pointerDown(e.position,
              doubleTapOff: !const [Stage.onboarding, Stage.userSelect].contains(stage) && app.auth == null && !app.trayPeek && onTop),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedSwitcher(
                  duration: WallpadTokens.pageTransition,
                  child: KeyedSubtree(
                    key: ValueKey(stage),
                    child: WallpadBackground(night: stage == Stage.returning, child: screen),
                  ),
                ),
              ),
              if (app.auth case final request?)
                Positioned.fill(
                  child: ColoredBox(
                    color: const Color(0x8C101322),
                    child: DesignCanvas.legacy(child: AuthOverlay(key: ObjectKey(request), request: request)),
                  ),
                ),
              if (question != null && stage == Stage.checklist) BelongingQuestionOverlay(key: ValueKey(question.id), question: question),
              if (app.trayPeek && const [Stage.checklist, Stage.returning, Stage.settings, Stage.onboarding].contains(stage)) const TrayStatusOverlay(),
              if (app.screenOff)
                Positioned.fill(
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: app.touched, child: const ColoredBox(color: Colors.black)),
                ),
              const DoorCamOverlay(),
              if (showDevPanel) const DevPanel(),
            ],
          ),
        );
      },
    );
  }
}
