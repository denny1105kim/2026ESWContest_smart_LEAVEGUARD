import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/config/app_clock.dart';
import '../../core/theme/wallpad_tokens.dart';
import '../../shared/time_text.dart';
import 'view_data.dart';

export 'view_data.dart';

part 'return_home_screen.dart';
part 'widgets/dashboard.dart';
part 'widgets/dash_top.dart';
part 'widgets/dash_upper.dart';
part 'widgets/dash_lower.dart';
part 'widgets/dialogs.dart';
part 'widgets/side.dart';

/// 외출 체크 화면. 로직 없이 ViewData 만 그린다
class ChecklistScreen extends StatelessWidget {
  const ChecklistScreen({
    super.key,
    required this.members,
    required this.selectedId,
    required this.userName,
    required this.situation,
    this.family = true,
    required this.familyTodos,
    required this.appliances,
    required this.weather,
    this.airLabel,
    required this.items,
    required this.tray,
    required this.calendar,
    required this.barMode,
    this.departedLabel,
    this.skipOpen = false,
    this.group,
    this.pick,
    this.askEndGroup = false,
    this.onStartGroup,
    this.onTogglePick,
    this.onConfirmPick,
    this.onClosePrompt,
    this.onEndGroup,
    this.onAskEndGroup,
    this.onTapGroupThing,
    this.memoPopup = const [],
    this.onMemoSeen,
    required this.onSelectMember,
    required this.onSettings,
    required this.onSituationTap,
    required this.onToggleFamilyTodo,
    this.onTapAppliance,
    this.onLongPressAppliance,
    required this.onToggleItem,
    this.onTakeTray,
    required this.onConnectCalendar,
    required this.onRegisterBelongings,
    required this.onConfirmBelonging,
    required this.onPeekTray,
    required this.onDepart,
    required this.onSkip,
    required this.onSkipConfirm,
    required this.onSkipCancel,
    required this.onLastOutTurnOffAll,
    required this.onLastOutLeave,
  });

  final List<FamilyMemberViewData> members;
  final String selectedId;
  final String userName;
  final String situation;

  /// 혼자면 가족 탭 대신 상황 칩을 보인다
  final bool family;
  final List<FamilyTodoViewData> familyTodos;
  final List<ApplianceViewData> appliances;
  final WeatherViewData weather;
  final String? airLabel;

  final List<ChecklistItemViewData> items;
  final List<TrayItemViewData> tray;
  final CalendarViewData calendar;

  final BarMode barMode;
  final String? departedLabel;

  /// 남은 게 있는데 [출발하기]를 눌렀다
  final bool skipOpen;

  /// 혼자면 null
  final GroupViewData? group;
  final GroupPickViewData? pick;
  final bool askEndGroup;

  /// null 이면 [함께 외출] 버튼을 숨긴다
  final VoidCallback? onStartGroup;
  final ValueChanged<String>? onTogglePick;
  final VoidCallback? onConfirmPick;
  final VoidCallback? onClosePrompt;
  final VoidCallback? onEndGroup;
  final VoidCallback? onAskEndGroup;
  final ValueChanged<String>? onTapGroupThing;

  /// 어젯밤 남긴 메모. 비어 있지 않으면 팝업으로 보인다
  final List<String> memoPopup;
  final VoidCallback? onMemoSeen;

  final ValueChanged<String> onSelectMember;
  final VoidCallback onSettings;
  final VoidCallback onSituationTap;
  final ValueChanged<String> onToggleFamilyTodo;
  final ValueChanged<String>? onTapAppliance;
  final ValueChanged<String>? onLongPressAppliance;
  final ValueChanged<String> onToggleItem;

  /// null 이면 트레이 영상을 연다
  final ValueChanged<String>? onTakeTray;
  final VoidCallback onConnectCalendar;
  final VoidCallback onRegisterBelongings;
  final ValueChanged<String> onConfirmBelonging;
  final VoidCallback onPeekTray;
  final VoidCallback onDepart;
  final VoidCallback onSkip;
  final VoidCallback onSkipConfirm;
  final VoidCallback onSkipCancel;
  final VoidCallback onLastOutTurnOffAll;
  final VoidCallback onLastOutLeave;

  List<String> get _remaining => [
        ...items.where((i) => !i.isDone).map((i) => i.title),
        ...tray.where((t) => t.state == TrayState.onTray).map((t) => t.name),
      ];

  int get _total => items.length + tray.where((t) => t.state != TrayState.unknown).length;

  // 다 챙기면 경고가 저절로 풀린다
  bool get _warn => skipOpen && (group == null ? _remaining.isNotEmpty : group!.done < group!.total);

  @override
  Widget build(BuildContext context) {
    final warn = _warn;
    final g = group;
    final (things, extra) = g == null ? _things(warn) : _groupThings(g);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          _Dashboard(
            topRow: _TopRow(
              members: members,
              selectedId: selectedId,
              family: family,
              onSelectMember: onSelectMember,
              onSettings: onSettings,
              situation: situation,
              onSituationTap: onSituationTap,
              groupIds: g?.memberIds,
              onEndGroup: onAskEndGroup,
            ),
            hero: _Hero(greeting: _Hero.greetingNow(AppClock.now()), lines: g == null ? [_headline, _summary] : _groupLines(g)),
            upper: _UpperCard(
              calendarTitle: '오늘 일정',
              calendar: calendar,
              emptyText: '일정 없음',
              onConnect: onConnectCalendar,
              family: family,
              todos: familyTodos,
              onToggleTodo: onToggleFamilyTodo,
              weatherTitle: '날씨',
              weather: weather,
              airLabel: airLabel,
            ),
            lower: _LowerCard(
              title: '소지품 List',
              count: g == null ? '${_total - _remaining.length} / $_total 챙김' : '${g.done} / ${g.total} 챙김',
              things: things,
              extra: extra,
              appliances: appliances,
              onTap: onTapAppliance,
              onLongPress: onLongPressAppliance,
            ),
            side: g == null ? _side(warn) : _groupSide(g, warn),
          ),
          if (pick case final p?)
            _Dialog(
              child: _GroupPick(pick: p, onToggle: onTogglePick, onConfirm: onConfirmPick, onCancel: onClosePrompt),
            ),
          if (askEndGroup)
            _Dialog(
              child: _Ask(
                title: '함께 외출을 그만할까요?',
                detail: '$userName님 화면으로 돌아가요',
                keep: '계속하기',
                stop: '그만하기',
                onKeep: onClosePrompt,
                onStop: onEndGroup,
              ),
            ),
          if (memoPopup.isNotEmpty) Positioned.fill(child: _MemoPopup(lines: memoPopup, onConfirm: onMemoSeen ?? () {})),
        ],
      ),
    );
  }

  // 공용 물건은 늘, 개인 물건은 누가 아직 안 챙겼을 때만 보인다
  (List<_Thing>, int) _groupThings(GroupViewData g) {
    final shown = [for (final t in g.things) if (t.common || !t.done) t];
    const slots = 8;
    return (
      [
        for (final t in shown.take(slots))
          _Thing(
            name: t.name,
            sub: t.common ? (t.done ? '챙김' : t.reason) : '',
            subColor: t.common && t.done ? _D.green : _D.faint,
            subNames: t.common ? null : t.waiting,
            icon: t.icon,
            dim: t.done,
            onTap: onTapGroupThing == null ? null : () => onTapGroupThing!(t.name),
          ),
      ],
      max(0, shown.length - slots),
    );
  }

  List<String> _groupLines(GroupViewData g) {
    final c = weather.condition;
    final first = c.contains('눈')
        ? '$userName님, 눈 소식이 있어요.'
        : weather.rainChance >= 50 || c.contains('비')
            ? '$userName님, 비 소식이 있어요.'
            : c.isEmpty
                ? '$userName님, 안녕하세요.'
                : '$userName님, 오늘은 $c이에요.';
    final commons = [for (final t in g.things) if (t.common && !t.done) t.name];
    final second = barMode == BarMode.departed || commons.isEmpty ? '모두 잘 다녀오세요.' : '나가기 전에 ${commons.join(' · ')} 꼭 챙기세요.';
    return [first, second];
  }

  Widget _groupSide(GroupViewData g, bool warn) {
    final on = [for (final a in appliances) if (a.isOn) a];
    final left = g.total - g.done;
    switch (barMode) {
      case BarMode.lastOut || BarMode.departed:
        return _side(warn);
      case BarMode.progress || BarMode.ready when warn:
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head('함께 출발'),
              const Spacer(),
              const Align(alignment: Alignment.centerLeft, child: Icon(Icons.warning_amber_rounded, size: 52, color: Colors.white)),
              const SizedBox(height: 14),
              Text('안 챙긴 것 $left개', style: _D.t(28, w: FontWeight.w600)),
              const SizedBox(height: 8),
              for (final (name, color, things) in g.leftByPerson)
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: name, style: _D.t(17, w: FontWeight.w600, c: _D.nameColor(color))),
                    TextSpan(text: ' · ${things.join(' · ')}', style: _D.t(17, c: const Color(0xBFFFFFFF))),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              const Spacer(flex: 2),
              _SoftButton(label: '돌아가기', onPressed: onSkipCancel),
              const SizedBox(height: 12),
              _WhiteButton(label: '그냥 출발', height: 64, onPressed: onSkipConfirm),
            ],
          ),
        );
      case BarMode.progress || BarMode.ready:
        final pct = g.total == 0 ? 100 : (g.done * 100 / g.total).round();
        final note = left == 0 && on.isEmpty ? '준비 완료' : [if (left > 0) '물건 $left', if (on.isNotEmpty) '가전 ${on.length}'].join(' · ');
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head('함께 출발'),
              const Spacer(),
              _Percent(pct),
              const SizedBox(height: 18),
              _Bar(pct / 100),
              const SizedBox(height: 18),
              Text(note, style: _D.t(17, c: _D.faint), maxLines: 2),
              const Spacer(flex: 2),
              _WhiteButton(label: '함께 출발하기', icon: Icons.door_front_door_outlined, onPressed: left == 0 ? onDepart : onSkip),
            ],
          ),
        );
    }
  }

  // 날씨 때문에 뜨는 공용 물건은 챙겨도 칸이 남는다
  static bool _common(ChecklistItemViewData i) => const [ChecklistItemKind.weather, ChecklistItemKind.air, ChecklistItemKind.uv].contains(i.kind);

  (List<_Thing>, int) _things(bool warn) {
    final all = <_Thing>[
      for (final i in items) if (_common(i)) _itemThing(i, warn),
      for (final t in tray) if (t.state != TrayState.taken && t.state != TrayState.acknowledged) _trayThing(t, warn),
      for (final i in items) if (!_common(i) && !i.isDone) _itemThing(i, warn),
    ];
    const slots = 7;
    final shown = all.take(slots).toList();
    return (
      [
        ...shown,
        _Thing(name: '물건 등록', sub: '', icon: Icons.add_rounded, dim: true, onTap: onRegisterBelongings),
      ],
      all.length - shown.length,
    );
  }

  _Thing _itemThing(ChecklistItemViewData i, bool warn) {
    final alert = warn && !i.isDone;
    return _Thing(
      name: i.title,
      sub: i.isDone ? '챙김' : i.reason,
      subColor: i.isDone ? _D.green : (alert ? _D.orange : _D.faint),
      icon: i.icon ?? Icons.checklist_rounded,
      dim: i.isDone,
      onTap: () => onToggleItem(i.id),
    );
  }

  _Thing _trayThing(TrayItemViewData t, bool warn) => switch (t.state) {
        TrayState.onTray => _Thing(
            name: t.name,
            sub: '',
            icon: t.icon,
            onTap: onTakeTray == null ? onPeekTray : () => onTakeTray!(t.id),
          ),
        TrayState.takenByOther => _Thing(name: t.name, sub: t.detail ?? '가족이 가져감', subColor: _D.orange, icon: t.icon, onTap: () => onConfirmBelonging(t.id)),
        TrayState.notReturned => _Thing(name: t.name, sub: t.detail ?? '없음', subColor: _D.orange, icon: t.icon, onTap: () => onConfirmBelonging(t.id)),
        TrayState.taken || TrayState.acknowledged || TrayState.unknown => _Thing(name: t.name, sub: t.state == TrayState.unknown ? '미확인' : '챙김', icon: t.icon, dim: true, onTap: onPeekTray),
      };

  String get _headline {
    final n = _remaining.length;
    if (barMode == BarMode.departed) return '$userName님 · 출발 ${departedLabel ?? ''}';
    if (_total == 0) return '$userName님';
    if (n == 0) return '$userName님 · 준비 완료';
    return '$userName님 · 챙길 것 $n개';
  }

  String get _summary => barMode == BarMode.departed ? '' : _remaining.join(' · ');

  Widget _side(bool warn) {
    final remaining = _remaining;
    final on = [for (final a in appliances) if (a.isOn) a];
    switch (barMode) {
      case BarMode.lastOut:
        return _SideNotice(
          title: '출발',
          icon: Icons.power_rounded,
          color: _D.red,
          headline: '켜진 가전',
          detail: on.map((a) => a.name).join(' · '),
          buttons: [
            _SoftButton(label: '그냥 출발', onPressed: onLastOutLeave),
            _SoftButton(label: '모두 끄고 출발', color: WallpadTokens.warning, onPressed: onLastOutTurnOffAll),
          ],
        );
      case BarMode.departed:
        final others = members.any((m) => m.state != MemberState.departed);
        return _SideNotice(
          title: '출발',
          icon: Icons.directions_walk_rounded,
          color: _D.soft,
          big: departedLabel ?? '',
          headline: '출발',
          detail: others ? '' : '모두 외출',
        );
      case BarMode.progress || BarMode.ready when warn:
        return _SideNotice(
          title: '출발',
          icon: Icons.warning_amber_rounded,
          color: _D.orange,
          headline: '안 챙긴 것 ${remaining.length}개',
          detail: remaining.join(' · '),
          buttons: [
            _SoftButton(label: '돌아가기', onPressed: onSkipCancel),
            _SoftButton(label: '그냥 출발', color: WallpadTokens.warning, onPressed: onSkipConfirm),
          ],
        );
      case BarMode.progress || BarMode.ready:
        final done = _total - remaining.length;
        final pct = _total == 0 ? 100 : (done * 100 / _total).round();
        final note = remaining.isEmpty && on.isEmpty
            ? (_total == 0 ? '챙길 것 없음' : '준비 완료')
            : [if (remaining.isNotEmpty) '물건 ${remaining.length}', if (on.isNotEmpty) '가전 ${on.length}'].join(' · ');
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _Head('출발'),
              const Spacer(),
              _Percent(pct),
              const SizedBox(height: 18),
              _Bar(pct / 100),
              const SizedBox(height: 18),
              Text(note, style: _D.t(17, c: _D.faint), maxLines: 2),
              const Spacer(flex: 2),
              if (onStartGroup case final start?)
                Row(
                  children: [
                    SizedBox(width: 150, child: _SoftButton(label: '함께 외출', onPressed: start)),
                    const SizedBox(width: 12),
                    Expanded(child: _WhiteButton(label: '출발하기', icon: Icons.door_front_door_outlined, onPressed: remaining.isEmpty ? onDepart : onSkip)),
                  ],
                )
              else
                _WhiteButton(label: '출발하기', icon: Icons.door_front_door_outlined, onPressed: remaining.isEmpty ? onDepart : onSkip),
            ],
          ),
        );
    }
  }
}
