part of '../onboarding_screen.dart';

extension _EssentialsStep on _OnboardingScreenState {
  Widget _essentialsBody() {
    final tray = app.myBelongings;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: SizedBox(
            height: 470,
            child: ObPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('카메라로 확인할 물건', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Ob.text)),
                  const SizedBox(height: 18),
                  if (tray.isEmpty)
                    Expanded(
                      child: Center(
                        child: ObButton('소지품 등록하러 가기', primary: false, width: 320, onTap: _back),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [for (final b in tray) _Row(icon: Icons.photo_camera_outlined, name: b.name, on: true)],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 28),
        Expanded(
          flex: 4,
          child: SizedBox(
            height: 470,
            child: ObPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('직접 확인할 항목', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Ob.text)),
                  const SizedBox(height: 18),
                  Expanded(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        for (final n in _manualCandidates)
                          _Row(
                            icon: Icons.check_box_outlined,
                            name: n,
                            on: _essentials.contains(n),
                            green: true,
                            onTap: () => _setState(() => _essentials.contains(n) ? _essentials.remove(n) : _essentials.add(n)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
