part of '../checklist_screen.dart';

class _TopRow extends StatelessWidget {
  const _TopRow({
    required this.members,
    required this.selectedId,
    required this.family,
    required this.onSelectMember,
    required this.onSettings,
    this.situation,
    this.onSituationTap,
    this.groupIds,
    this.onEndGroup,
  });

  final List<FamilyMemberViewData> members;
  final String selectedId;
  final bool family;
  final ValueChanged<String> onSelectMember;
  final VoidCallback onSettings;
  final String? situation;
  final VoidCallback? onSituationTap;

  /// 함께 외출 중이 아니면 null
  final List<String>? groupIds;
  final VoidCallback? onEndGroup;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _DateClock(),
        const Spacer(),
        if (family)
          _MemberTabs(members: members, selectedId: selectedId, onSelect: onSelectMember, groupIds: groupIds, onEndGroup: onEndGroup)
        else if (situation != null && onSituationTap != null)
          _SituationPill(situation: situation!, onTap: onSituationTap!),
        const SizedBox(width: 20),
        Semantics(
          button: true,
          label: '설정',
          child: Material(
            color: WallpadTokens.surface,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(onTap: onSettings, child: const SizedBox.square(dimension: 60, child: Icon(Icons.settings_rounded, size: 30, color: Colors.white))),
          ),
        ),
      ],
    );
  }
}

class _DateClock extends StatefulWidget {
  const _DateClock();

  @override
  State<_DateClock> createState() => _DateClockState();
}

class _DateClockState extends State<_DateClock> {
  late DateTime _now = AppClock.now();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = AppClock.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: Text('${dateText(_now)}   ·   ${hhmm(_now)}', style: _D.t(23, w: FontWeight.w300, c: const Color(0xE6FFFFFF))),
    );
  }
}

/// 함께 외출 중이면 묶음과 나머지 사람을 나눠 그린다
class _MemberTabs extends StatelessWidget {
  const _MemberTabs({required this.members, required this.selectedId, required this.onSelect, this.groupIds, this.onEndGroup});

  final List<FamilyMemberViewData> members;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final List<String>? groupIds;
  final VoidCallback? onEndGroup;

  static String _status(FamilyMemberViewData m) => switch (m.state) {
        MemberState.notStarted => '시작 전',
        MemberState.pending => '${m.remaining}개 남음',
        MemberState.ready => '준비 완료',
        MemberState.departed => '출발 ${m.departedLabel ?? ''}',
        MemberState.returned => '귀가 ${m.returnedLabel ?? ''}',
        MemberState.home => '외출 전',
        MemberState.out => '외출 중',
      };

  @override
  Widget build(BuildContext context) {
    final ids = groupIds;
    if (ids == null) {
      return _box([for (final m in members) _tab(m, m.id == selectedId)]);
    }
    final inside = [for (final id in ids) ...members.where((m) => m.id == id)];
    final outside = [for (final m in members) if (!ids.contains(m.id)) m];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _box(
          [
            Padding(padding: const EdgeInsets.only(left: 12, right: 8), child: Text('함께', style: _D.t(15, w: FontWeight.w600, c: const Color(0xBFFFFFFF)))),
            for (final m in inside) _tab(m, m.id == selectedId, groupMode: true),
            if (onEndGroup != null) ...[
              const SizedBox(width: 4),
              Semantics(
                button: true,
                label: '함께 외출 그만하기',
                child: Material(
                  color: const Color(0x1FFFFFFF),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(onTap: onEndGroup, child: const SizedBox.square(dimension: 42, child: Icon(Icons.close_rounded, size: 22, color: Color(0xCCFFFFFF)))),
                ),
              ),
            ] else
              const SizedBox(width: 10),
          ],
          border: true,
        ),
        if (outside.isNotEmpty) ...[
          const SizedBox(width: 12),
          _box([
            for (final m in outside)
              Opacity(
                opacity: 0.6,
                child: m.state == MemberState.departed
                    ? _tab(m, false, groupMode: true)
                    : _tab(m, false, groupMode: true, trailing: Icons.add_rounded, onTap: () => onSelect(m.id)),
              ),
          ]),
        ],
      ],
    );
  }

  Widget _box(List<Widget> children, {bool border = false}) => Container(
        height: 60,
        padding: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: WallpadTokens.surface,
          borderRadius: BorderRadius.circular(30),
          border: border ? Border.all(color: const Color(0x8CFFFFFF), width: 2) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );

  // 다른 사람 탭은 PIN 을 거치므로 자물쇠를 붙인다
  Widget _tab(FamilyMemberViewData m, bool selected, {bool groupMode = false, IconData? trailing, VoidCallback? onTap}) {
    final icon = groupMode ? trailing : (selected ? null : Icons.lock_outline_rounded);
    final tap = groupMode ? onTap : (selected ? null : () => onSelect(m.id));
    final initial = m.name.trim().isEmpty ? '?' : m.name.trim().characters.first;
    final away = m.state == MemberState.departed || m.state == MemberState.out;
    return Semantics(
      button: true,
      selected: selected,
      label: '${m.name}, ${_status(m)}',
      child: Opacity(
        opacity: away && !selected ? 0.5 : 1,
        child: Material(
          color: selected ? Colors.white : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: tap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 18, 0),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: m.color),
                    child: Text(initial, style: _D.t(17, w: FontWeight.w700, h: 1)),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(m.name, style: _D.t(19, w: FontWeight.w600, c: selected ? WallpadTokens.ink : Colors.white, h: 1.1)),
                      Text(_status(m), style: _D.t(13, c: selected ? const Color(0x991C2541) : _D.faint, h: 1.2)),
                    ],
                  ),
                  if (icon != null) ...[const SizedBox(width: 8), Icon(icon, size: icon == Icons.add_rounded ? 22 : 16, color: _D.faint)],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SituationPill extends StatelessWidget {
  const _SituationPill({required this.situation, required this.onTap});

  final String situation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '오늘 상황 $situation, 눌러서 바꾸기',
      child: Material(
        color: WallpadTokens.surface,
        shape: const StadiumBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Container(
            height: 60,
            padding: const EdgeInsets.only(left: 22, right: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.work_outline_rounded, size: 22, color: _D.soft),
                const SizedBox(width: 10),
                Text(situation, style: _D.t(19, w: FontWeight.w600)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded, size: 22, color: _D.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.greeting, required this.lines});

  final String greeting;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        SizedBox(
          height: 290,
          width: double.infinity,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: Text(greeting, style: _D.t(152, w: FontWeight.w200, h: 0.92, ls: -3)),
          ),
        ),
        const Spacer(),
        for (final l in lines.where((l) => l.isNotEmpty).take(2))
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 4),
            child: Text(l, style: _D.t(24, w: FontWeight.w300, c: const Color(0xE6FFFFFF), h: 1.4), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  static String greetingNow(DateTime now) => switch (now.hour) {
        >= 5 && < 12 => 'Good\nMorning!',
        >= 12 && < 18 => 'Good\nAfternoon!',
        _ => 'Good\nEvening!',
      };
}
