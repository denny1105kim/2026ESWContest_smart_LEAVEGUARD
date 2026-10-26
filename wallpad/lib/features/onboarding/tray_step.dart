import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../app/models.dart';
import '../belongings/learning.dart';
import '../belongings/observation.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../app/app_state.dart';
import '../../app/backend.dart';
import '../belongings/same_item_dialog.dart';
import 'ob_widgets.dart';

/// 트레이 영상의 박스를 눌러 지금 멤버의 소지품으로 등록한다
class TrayStep extends StatefulWidget {
  final List<String> suggestions;

  const TrayStep({super.key, required this.suggestions});

  @override
  State<TrayStep> createState() => _TrayStepState();
}

class _Pick {
  final int? frameId;
  final List<int> bbox;
  final String spaceId;
  final Float32List vector;
  Uint8List? crop;
  Belonging? other; // 다른 가족이 이미 등록한 같은 물건
  Future<List<Float32List>> turns = Future.value(const []);

  _Pick(this.frameId, this.bbox, this.spaceId, this.vector, {this.other});
}

class _TrayStepState extends State<TrayStep> {
  static const _viewW = 880.0, _viewH = 495.0;

  Timer? _poll;
  var _stable = false;
  var _healthSeq = -1;
  int? _settledSeq;
  _Pick? _pick;
  var _name = '';
  var _busy = false;
  String? _note;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) => _checkHealth());
    _checkHealth();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkHealth() async {
    final h = await trayNode.health();
    if (!mounted) return;
    final stable = h != null && h.state == 'stable';
    if (stable != _stable || (h?.sequence ?? -1) != _healthSeq) {
      setState(() {
        _stable = stable;
        _healthSeq = h?.sequence ?? -1;
      });
    }
  }

  // 손이 멈춘 뒤의 관측일 때만 박스를 그린다
  BelongingObservation? get _scene {
    final o = app.trayScene;
    if (!_stable) {
      _settledSeq = null;
      return null;
    }
    if (o != null && o.sequence == _healthSeq) _settledSeq = o.sequence;
    return _settledSeq != null && o != null && o.sequence >= _settledSeq! ? o : null;
  }

  Future<void> _choose(BelongingObservation o, ObservedCandidate c) async {
    final like = app.lookalikeOf(c.id);
    final pick = _Pick(o.frameId, c.bbox, o.spaceId, c.embedding!, other: like != null && !like.ownedBy(app.userId) ? like : null);
    setState(() {
      _pick = pick;
      _note = null;
      if (pick.other case final b?) _name = b.name;
    });
    if (o.frameId != null) {
      pick.turns = trayNode.turns(o.frameId!, c.bbox);
      pick.crop = await trayNode.crop(o.frameId!, c.bbox);
    }
    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final v = await showTextEntry(context, title: '소지품 이름', initial: _name, hint: '예: 지갑', confirmLabel: '확인');
    if (v != null && mounted) setState(() => _name = v.trim());
  }

  Future<void> _save() async {
    final p = _pick, me = app.userId;
    if (p == null || me == null || _name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final turns = await p.turns.timeout(const Duration(seconds: 6), onTimeout: () => const []);
      var same = app.myBelongings.where((b) => b.name.trim() == _name.trim()).firstOrNull;
      if (same != null && p.other == null) {
        if (!mounted) return;
        if (!await confirmSameItem(context, same, p.crop)) same = null;
      }
      if (p.other case final b?) {
        await app.shareBelonging(b.id, name: b.name, ownerIds: [...b.userIds, me], spaceId: p.spaceId, vector: p.vector);
      } else if (same != null) {
        await app.shareBelonging(same.id,
            name: same.name, ownerIds: {...same.userIds, me}.toList(), spaceId: p.spaceId, vector: p.vector, source: 'register', turns: turns);
      } else {
        await app.saveBelonging(name: _name, ownerIds: [me], spaceId: p.spaceId, vector: p.vector, thumbnail: p.crop, turns: turns);
      }
      if (!mounted) return;
      setState(() {
        _note = same != null && p.other == null ? '“$_name” 에 이 모습을 더했어요. 다음부터 이렇게 놓여도 알아봐요' : '“$_name” 등록했어요';
        _pick = null;
        _name = '';
      });
    } catch (_) {
      if (mounted) setState(() => _note = '저장하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    final mine = app.myBelongings;
    final registered = {for (final b in mine) b.name};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('추천', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Ob.muted)),
            const SizedBox(width: 18),
            for (final s in widget.suggestions)
              if (!registered.contains(s)) ...[
                ObChip(s, height: 56, selected: _name == s, onTap: () => setState(() => _name = s)),
                const SizedBox(width: 12),
              ],
            ObChip('직접 입력', height: 56, selected: false, onTap: _editName),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Container(color: const Color(0xFF2A2F44), width: _viewW, height: _viewH, child: _live()),
                ),
                const SizedBox(height: 10),
                InkWell(
                  onTap: _busy ? null : () => app.openTrayPeek(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(app.trayOffline ? '트레이 카메라 연결 끊김' : '박스가 없나요?  직접 그리기  →',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: app.trayOffline ? Ob.red : Ob.accent)),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 28),
            Expanded(child: SizedBox(height: _viewH, child: _panel(mine))),
          ],
        ),
      ],
    );
  }

  Widget _live() {
    final o = _scene;
    final k = o == null ? 1.0 : _viewW / o.imageWidth;
    return Stack(
      children: [
        Positioned.fill(child: MjpegView(url: trayNode.rawStream)),
        if (o != null)
          for (final c in drawableCandidates(o)) _box(o, c, k),
      ],
    );
  }

  Widget _box(BelongingObservation o, ObservedCandidate c, double k) {
    final like = app.lookalikeOf(c.id);
    final owned = like != null && like.ownedBy(app.userId) ? like : null;
    final other = like != null && owned == null ? like : null;
    final selected = _pick != null && sameBox(_pick!.bbox, c.bbox);
    final color = owned != null ? const Color(0xFF9CA3AF) : (selected ? Ob.green : (other != null ? const Color(0xFFF59E0B) : Ob.accent));
    final label = owned != null
        ? owned.name
        : other != null
            ? '${app.ownerNames(other)} · ${other.name}'
            : (selected ? '선택됨' : '눌러서 등록');
    return Positioned(
      left: c.bbox[0] * k,
      top: c.bbox[1] * k,
      width: c.bbox[2] * k,
      height: c.bbox[3] * k,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: owned != null || _busy ? null : () => _choose(o, c),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: color, width: selected ? 6 : 4), borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.topLeft,
          child: Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(label, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1),
          ),
        ),
      ),
    );
  }

  Future<void> _remove(Belonging b) async {
    final me = app.userId;
    final shared = b.userIds.any((u) => u != me);
    final ok = await confirmDelete(context,
        title: '‘${b.name}’을 지울까요?', message: shared ? '다른 가족은 계속 쓰고, 내 소지품에서만 빠져요' : '트레이에서 더 이상 확인하지 않아요');
    if (!ok || !mounted) return;
    if (shared) {
      await app.updateBelonging(b.id, name: b.name, ownerIds: [for (final u in b.userIds) if (u != me) u]);
    } else {
      app.deleteBelonging(b);
    }
    if (mounted) setState(() => _note = '“${b.name}” 지웠어요');
  }

  Widget _panel(List<Belonging> mine) {
    final p = _pick;
    final other = p?.other;
    return ObPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('선택한 물건', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Ob.text)),
          const SizedBox(height: 16),
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 96,
                  height: 96,
                  color: Ob.chip,
                  child: p?.crop == null
                      ? Icon(p == null ? Icons.touch_app_rounded : Icons.image_rounded, size: 36, color: Ob.faint)
                      : Image.memory(p!.crop!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: InkWell(
                  onTap: _busy || other != null ? null : _editName,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    height: 96,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Ob.accentTint,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _name.isEmpty ? Ob.line : Ob.accent, width: 2),
                    ),
                    child: Text(_name.isEmpty ? '이름' : _name,
                        style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: _name.isEmpty ? Ob.faint : Ob.text), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 72,
            child: Material(
              color: p != null && _name.isNotEmpty && !_busy ? Colors.white : Ob.chip,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: p != null && _name.isNotEmpty && !_busy ? _save : null,
                borderRadius: BorderRadius.circular(16),
                child: Center(
                  child: _busy
                      ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3, color: Ob.ink))
                      : Text(other != null ? '나도 쓰는 물건이에요' : '내 소지품으로 등록', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: p != null && _name.isNotEmpty ? Ob.ink : Ob.faint)),
                ),
              ),
            ),
          ),
          if (other != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: Text('${app.ownerNames(other)}님이 등록한 물건 같아요', style: Ob.small, maxLines: 1, overflow: TextOverflow.ellipsis)),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            p!.other = null;
                            _name = '';
                          }),
                  child: const Text('다른 물건이에요', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Ob.accent)),
                ),
              ],
            ),
          ],
          if (_note != null) ...[const SizedBox(height: 10), Text(_note!, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600, color: Ob.green))],
          const SizedBox(height: 18),
          Container(height: 2, color: Ob.line),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                for (final b in mine)
                  Container(
                    height: 60,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.only(left: 18, right: 4),
                    decoration: BoxDecoration(color: Ob.greenTint, borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        const ObCheck(size: 28, color: Ob.green),
                        const SizedBox(width: 14),
                        Expanded(child: Text(b.name, style: Ob.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const Text('등록됨', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Ob.green)),
                        IconButton(
                          onPressed: _busy ? null : () => _remove(b),
                          icon: const Icon(Icons.delete_outline_rounded, size: 28, color: Ob.faint),
                          tooltip: '지우기',
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
