part of '../onboarding_screen.dart';

extension _LifePatternSteps on _OnboardingScreenState {
  Widget _cards(List<(String, IconData, String)> options, String? value, ValueChanged<String> onPick, {int perRow = 3, double height = 199}) {
    final rows = <List<(String, IconData, String)>>[];
    for (var i = 0; i < options.length; i += perRow) {
      rows.add(options.sublist(i, i + perRow > options.length ? options.length : i + perRow));
    }
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 23),
                Expanded(child: ObOptionCard(icon: row[i].$2, title: row[i].$3, selected: value == row[i].$1, height: height, onTap: () => onPick(row[i].$1))),
              ],
            ],
          ),
          const SizedBox(height: 24),
        ],
      ],
    );
  }

  Widget _leaveBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ObPanel(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: _TimeStepper(label: '집을 나서는 시간', minutes: _leave, onChanged: (v) => _setState(() => _leave = v))),
                  const SizedBox(width: 20),
                  Expanded(child: _TimeStepper(label: '돌아오는 시간', minutes: _return, onChanged: (v) => _setState(() => _return = v))),
                ],
              ),
              const SizedBox(height: 34),
              const Text('요일', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Ob.muted)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < 7; i++) ...[
                    if (i > 0) const SizedBox(width: 14),
                    _DayChip(weekdayNames[i], on: _days & (1 << i) != 0, onTap: () => _setState(() => _days ^= 1 << i)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
