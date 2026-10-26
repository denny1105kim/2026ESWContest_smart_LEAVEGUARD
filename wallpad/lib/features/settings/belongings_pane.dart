import 'package:flutter/material.dart';

import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/card.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../app/app_state.dart';
import '../../app/backend.dart';
import '../../app/models.dart';
import '../../core/theme/tokens.dart';
import 'settings_screen.dart';

class BelongingsPane extends StatelessWidget {
  const BelongingsPane({super.key});

  Future<void> _add(BuildContext context) async {
    if (onBoard) return app.openTrayPeek();
    // 보드가 아니면 트레이 카메라가 없어 이름만 받는다
    final name = await showTextEntry(context, title: '소지품 이름', hint: '예: 지갑', confirmLabel: '추가');
    if (name != null && name.trim().isNotEmpty) app.addBelonging(name.trim(), 1);
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    final items = app.myBelongings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PaneHeader(
          title: '소지품',
          action: AppButton('소지품 추가', icon: Icons.add_rounded, onPressed: () => _add(context)),
        ),
        const SizedBox(height: Space.l),
        const _ReturnCheckSwitch(),
        const SizedBox(height: Space.xl),
        Expanded(
          child: items.isEmpty
              ? const Align(alignment: Alignment.topLeft, child: EmptyNote(icon: Icons.inventory_2_outlined, text: '등록된 소지품이 없어요'))
              : GridView.count(
                  crossAxisCount: 3,
                  mainAxisSpacing: Space.l,
                  crossAxisSpacing: Space.l,
                  childAspectRatio: 1.08,
                  children: [for (final b in items) _BelongingTile(b)],
                ),
        ),
      ],
    );
  }
}

class _BelongingTile extends StatelessWidget {
  final Belonging belonging;

  const _BelongingTile(this.belonging);

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Container(
      decoration: BoxDecoration(color: Palette.surface, borderRadius: BorderRadius.circular(Radii.card), boxShadow: Shadows.card),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Palette.raised,
                    alignment: Alignment.center,
                    child: belonging.thumbnail == null
                        ? Icon(belonging.icon, size: 44, color: Palette.muted)
                        : Image.memory(belonging.thumbnail!, fit: BoxFit.cover, width: double.infinity, height: double.infinity),
                  ),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: RoundIconButton(
                    Icons.delete_outline_rounded,
                    size: 44,
                    color: Palette.pending,
                    background: Palette.raised,
                    onPressed: () async {
                      final ok = await confirmDelete(context, title: '‘${belonging.name}’을 삭제할까요?', message: '트레이에서 더 이상 확인하지 않아요');
                      if (ok) app.deleteBelonging(belonging);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(belonging.name, style: Txt.bodyStrong),
                Text(
                    [
                      if (belonging.shared) '공용 · ${app.ownerNames(belonging)}',
                      '사진 ${belonging.photos}장',
                      if (belonging.hardToDetect) '자동으로 잘 안 잡혀요',
                    ].join(' · '),
                    style: Txt.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 귀가 소지품 확인 켜기·끄기 (사람마다 따로)
class _ReturnCheckSwitch extends StatelessWidget {
  const _ReturnCheckSwitch();

  @override
  Widget build(BuildContext context) {
    final id = app.userId;
    if (id == null) return const SizedBox.shrink();
    final on = app.returnCheckOn(id);
    return Material(
      color: Palette.surface,
      borderRadius: BorderRadius.circular(Radii.button),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => app.setReturnCheck(id, !on),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.l, Space.l),
          child: Row(
            children: [
              const Icon(Icons.home_rounded, size: 28, color: Palette.accent),
              const SizedBox(width: Space.l),
              const Expanded(child: Text('귀가할 때 소지품 확인', style: Txt.bodyStrong)),
              Transform.scale(
                scale: 1.3,
                child: Switch(value: on, activeTrackColor: Palette.accent, onChanged: (v) => app.setReturnCheck(id, v)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
