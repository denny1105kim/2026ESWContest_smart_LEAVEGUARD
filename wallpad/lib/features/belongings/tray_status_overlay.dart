import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'gallery_matcher.dart';
import 'item_catalog.dart';
import 'learning.dart';
import 'observation.dart';
import 'same_item_dialog.dart';
import '../../shared/widgets/avatar.dart';
import '../../shared/widgets/buttons.dart';
import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/design_canvas.dart';
import '../../shared/widgets/mjpeg_view.dart';
import '../../shared/widgets/on_screen_keyboard.dart';
import '../../app/app_state.dart';
import '../../app/models.dart';
import '../../app/backend.dart';
import '../../core/theme/tokens.dart';
import '../settings/settings_screen.dart' show FieldBox;

/// 트레이 영상 위 박스를 눌러 소지품을 등록·수정한다. 박스는 노드가 stable 일 때만 그린다.
class TrayStatusOverlay extends StatefulWidget {
  const TrayStatusOverlay({super.key});

  @override
  State<TrayStatusOverlay> createState() => _TrayStatusOverlayState();
}

class _Pick {
  final int? frameId;
  final List<int> bbox;
  final String? spaceId;
  final Float32List? vector;
  final bool redBox;
  final String? itemId; // 있으면 등록된 물건을 고친다
  Uint8List? crop;
  final bool learn; // 저장하면 이 모습을 그 물건 사진으로 더한다
  final bool side; // 뒷면 등록
  Future<List<Float32List>> turns = Future.value(const []);

  _Pick({required this.frameId, required this.bbox, this.spaceId, this.vector, this.redBox = false, this.itemId, this.learn = false, this.side = false});
}

class _TrayStatusOverlayState extends State<TrayStatusOverlay> {
  static const _viewW = 600.0, _viewH = 338.0;

  Timer? _poll;
  var _stable = false;
  var _healthSeq = -1;
  int? _settledSeq;

  _Pick? _pick;
  ItemCatalog? _catalog;
  var _missCount = 0;
  var _missCheckedSeq = -1;
  var _name = '';
  final _owners = <String>{};
  var _busy = false;
  String? _note;

  var _drawing = false;
  int? _drawFrame;
  Uint8List? _drawImage;
  Offset? _dragA, _dragB;
  Size _drawSource = const Size(1536, 864);
  Offset? _moveFrom;
  Rect? _moveRect;

  // 방금 등록한 물건. _awaitSide 면 다음에 고르는 박스가 그 뒷면이다
  String? _sideFor;
  var _awaitSide = false;

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
    _tryPreselect();
    _dropStalePick();
  }

  void _tryPreselect() {
    final want = app.trayPreselect;
    final o = _scene;
    if (want == null || _pick != null || o == null) return;
    for (final c in o.candidates) {
      if (sameBox(c.bbox, want)) {
        app.trayPreselect = null;
        _choose(o, c);
        return;
      }
    }
  }

  // 고른 박스가 관측 네 번 연속 안 보이면 푼다 (직접 그린 것은 제외)
  void _dropStalePick() {
    final p = _pick;
    final o = _scene;
    if (p == null || p.redBox || _busy || o == null || o.sequence == _missCheckedSeq) return;
    _missCheckedSeq = o.sequence;
    final present = drawableCandidates(o).any((c) => sameBox(c.bbox, p.bbox));
    if (present) {
      _missCount = 0;
      return;
    }
    if (++_missCount < 4) return;
    _missCount = 0;
    setState(() {
      _pick = null;
      _note = '고른 물건이 트레이에서 사라졌어요';
    });
  }

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
    final m = app.trayMatches[c.id];
    final side = _awaitSide ? app.belongingById(_sideFor ?? '') : null;
    final owned = side ?? app.lookalikeOf(c.id);
    final learn = side != null || (owned != null && m != null && bandOf(m) == Band.ask);
    final pick = _Pick(frameId: o.frameId, bbox: c.bbox, spaceId: o.spaceId, vector: c.embedding, itemId: owned?.id, learn: learn, side: side != null);
    _missCount = 0;
    setState(() {
      _pick = pick;
      _note = null;
      _name = owned?.name ?? '';
      _owners
        ..clear()
        ..addAll(owned?.userIds ?? const [])
        // 애매한 박스는 지금 사람이 등록하려는 것이라 나도 주인에 넣는다
        ..addAll([if ((owned == null || learn) && app.userId != null) app.userId!]);
    });
    if (o.frameId != null) pick.turns = trayNode.turns(o.frameId!, c.bbox);
    if (owned?.thumbnail != null && !learn) {
      pick.crop = owned!.thumbnail;
    } else if (o.frameId != null) {
      pick.crop = await trayNode.crop(o.frameId!, c.bbox);
    }
    if (mounted) setState(() {});
  }

  void _unpick() => setState(() {
        _pick = null;
        _note = null;
      });

  Future<void> _startDrawing() async {
    final o = app.trayScene;
    if (o?.frameId == null) return setState(() => _note = '트레이 카메라 사진이 아직 없어요. 잠시 뒤 다시 눌러 주세요');
    setState(() {
      _busy = true;
      _note = null;
    });
    final img = await trayNode.snapshot(o!.frameId!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (img == null) {
        _note = '사진을 받지 못했어요. 다시 눌러 주세요';
        return;
      }
      _drawing = true;
      _drawFrame = o.frameId;
      _drawImage = img;
      _drawSource = Size(o.imageWidth.toDouble(), o.imageHeight.toDouble());
      _dragA = _dragB = null;
      _pick = null;
    });
  }

  Rect? get _dragRect => _dragA == null || _dragB == null ? null : Rect.fromPoints(_dragA!, _dragB!);

  Offset _clamp(Offset p) => Offset(p.dx.clamp(0, _viewW), p.dy.clamp(0, _viewH));

  Future<void> _confirmDrawing() async {
    final r = _dragRect;
    if (r == null || r.width < 12 || r.height < 12) return setState(() => _note = '물건을 감싸게 네모를 끌어 그려 주세요');
    final k = _drawSource.width / _viewW;
    final box = [(r.left * k).round(), (r.top * k).round(), (r.width * k).round(), (r.height * k).round()];
    setState(() => _busy = true);
    final enc = await trayNode.encode(_drawFrame!, box, save: true);
    if (!mounted) return;
    if (enc == null) {
      return setState(() {
        _busy = false;
        _note = '특징을 뽑지 못했어요. 다시 그려 주세요';
      });
    }
    // 이미 등록된 물건 같으면 새로 만들지 않고 사진을 더한다
    final side = _awaitSide ? app.belongingById(_sideFor ?? '') : null;
    final like = side ?? app.lookalikeOfVector(enc.spaceId, enc.vector);
    final pick = _Pick(
        frameId: enc.frameId, bbox: enc.bbox, spaceId: enc.spaceId, vector: enc.vector, redBox: true, itemId: like?.id, learn: like != null, side: side != null);
    setState(() {
      _busy = false;
      _drawing = false;
      _pick = pick;
      _name = like?.name ?? '';
      _owners
        ..clear()
        ..addAll(like?.userIds ?? const [])
        ..addAll([if (app.userId != null && (like == null || side == null)) app.userId!]);
    });
    pick.turns = trayNode.turns(enc.frameId, enc.bbox);
    pick.crop = await trayNode.crop(enc.frameId, enc.bbox);
    if (mounted) setState(() {});
  }

  Future<void> _editName() async {
    final v = await showTextEntry(context, title: '소지품 이름', initial: _name, hint: '예: 지갑', confirmLabel: '확인');
    if (v != null && mounted) setState(() => _name = v.trim());
  }

  Future<void> _save() async {
    final p = _pick!;
    setState(() => _busy = true);
    try {
      final turns = await p.turns.timeout(const Duration(seconds: 6), onTimeout: () => const []);
      if (p.itemId != null && p.learn) {
        await app.shareBelonging(p.itemId!,
            name: _name, ownerIds: _owners.toList(), spaceId: p.spaceId, vector: p.vector, source: p.side ? 'register' : 'confirm', turns: turns);
        if (!mounted) return;
        setState(() {
          _pick = null;
          if (p.side) {
            _sideFor = null;
            _awaitSide = false;
          }
          _note = p.side ? '“$_name” 뒷면도 등록했어요. 어느 면이 위로 와도 알아봐요' : '“$_name” 저장했어요. 다음부터 바로 알아봐요';
        });
      } else if (p.itemId != null) {
        await app.updateBelonging(p.itemId!, name: _name, ownerIds: _owners.toList());
        if (!mounted) return;
        setState(() {
          _pick = null;
          _note = '“$_name” 바꿨어요';
        });
      } else if (await _confirmedSameName(_name, p.crop) case final b?) {
        // 같은 이름이 있으면 못 알아본 면인지 물어보고 그 물건에 더한다
        await app.shareBelonging(b.id,
            name: b.name, ownerIds: {...b.userIds, ..._owners}.toList(), spaceId: p.spaceId, vector: p.vector, source: 'register', turns: turns);
        if (!mounted) return;
        setState(() {
          _pick = null;
          _note = '“${b.name}” 에 이 모습을 더했어요. 다음부터 이렇게 놓여도 알아봐요';
        });
      } else {
        final id = await app.saveBelonging(
            name: _name,
            ownerIds: _owners.toList(),
            spaceId: p.spaceId!,
            vector: p.vector!,
            thumbnail: p.crop,
            redBox: p.redBox,
            watchBox: p.redBox ? p.bbox : null,
            turns: turns);
        if (!mounted) return;
        setState(() {
          _pick = null;
          _sideFor = id;
          _awaitSide = false;
          _note = '“$_name” 등록했어요. 다음부터 트레이에서 알아봐요';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _note = '저장하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // 내 물건 중 같은 이름이 있고 그 물건이 맞다고 하면 그 물건. 아니면 새로 만든다
  Future<Belonging?> _confirmedSameName(String name, Uint8List? crop) async {
    final n = name.trim();
    final b = n.isEmpty ? null : app.myBelongings.where((b) => b.name.trim() == n).firstOrNull;
    if (b == null || !mounted) return null;
    return await confirmSameItem(context, b, crop) ? b : null;
  }

  Future<void> _delete() async {
    final b = app.belongingById(_pick?.itemId ?? '');
    if (b == null) return;
    final ok = await confirmDelete(context, title: '‘${b.name}’을 지울까요?', message: '트레이에서 더 이상 확인하지 않아요');
    if (!ok || !mounted) return;
    app.deleteBelonging(b);
    setState(() {
      _pick = null;
      _note = '“${b.name}” 지웠어요';
    });
  }

  @override
  Widget build(BuildContext context) {
    watch(context);
    return Positioned.fill(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : app.closeTrayPeek,
        child: ColoredBox(
          color: const Color(0xFF101322).withValues(alpha: 0.55),
          child: DesignCanvas.legacy(
            child: Center(
              child: GestureDetector(
                onTap: () {}, // 판 안쪽 터치는 닫지 않는다
                child: Material(
                  color: Palette.dialog,
                  borderRadius: BorderRadius.circular(28),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.l),
                    child: SizedBox(
                      width: 940,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              if (_drawing) ...[
                                RoundIconButton(Icons.arrow_back_rounded, size: 44, onPressed: () => setState(() => _drawing = false)),
                                const SizedBox(width: Space.s),
                              ],
                              Text(_drawing ? '직접 그리기' : '트레이 상태', style: Txt.title),
                              const Spacer(),
                              if (app.trayOffline) const Text('카메라 연결 끊김', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Palette.pending)),
                              const SizedBox(width: Space.m),
                              RoundIconButton(Icons.close_rounded, size: 44, onPressed: _busy ? null : app.closeTrayPeek),
                            ],
                          ),
                          const SizedBox(height: Space.m),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(18),
                                    child: SizedBox(width: _viewW, height: _viewH, child: _drawing ? _drawView() : _liveView()),
                                  ),
                                  const SizedBox(height: Space.s),
                                  if (!_drawing) _liveFooter(),
                                ],
                              ),
                              const SizedBox(width: Space.l),
                              Expanded(child: SizedBox(height: _viewH + 56, child: _drawing ? _drawPanel() : _panel())),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _liveView() {
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
    final m = app.trayMatches[c.id];
    final owned = m?.decision == MatchDecision.matched ? app.belongingById(m!.itemId!) : null;
    final selected = _pick != null && !_pick!.redBox && sameBox(_pick!.bbox, c.bbox);
    final Color color;
    final String label;
    if (owned != null) {
      color = owned.ownedBy(app.userId) ? Palette.done : const Color(0xFF9CA3AF);
      label = '${app.ownerNames(owned)} · ${owned.name}';
    } else if (m != null && bandOf(m) == Band.ask) {
      color = Palette.warn;
      final b = app.belongingById(m.bestItemId!);
      label = b == null ? '?' : '${app.ownerNames(b)} · ${b.name}일까요?';
    } else {
      color = Palette.accent;
      label = selected ? '고름' : '새 물건';
    }
    return Positioned(
      left: c.bbox[0] * k,
      top: c.bbox[1] * k,
      width: c.bbox[2] * k,
      height: c.bbox[3] * k,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _busy ? null : () => _choose(o, c),
        child: Container(
          decoration: BoxDecoration(border: Border.all(color: color, width: selected ? 5 : 3), borderRadius: BorderRadius.circular(6)),
          alignment: Alignment.topLeft,
          child: Container(
            color: color,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white), maxLines: 1, overflow: TextOverflow.clip),
          ),
        ),
      ),
    );
  }

  Widget _liveFooter() {
    return SizedBox(
      width: _viewW,
      child: Row(
        children: [
          Expanded(child: Text(_note ?? '', style: Txt.sub, maxLines: 1, overflow: TextOverflow.ellipsis)),
          const SizedBox(width: Space.m),
          TextButton.icon(
            onPressed: _busy ? null : _startDrawing,
            style: TextButton.styleFrom(foregroundColor: Palette.muted, minimumSize: const Size(0, kTouch), padding: const EdgeInsets.symmetric(horizontal: Space.m)),
            icon: const Icon(Icons.crop_free_rounded, size: 22),
            label: const Text('직접 그리기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  // 모서리 근처는 크기, 안쪽은 옮기기, 그 밖은 새로 그리기
  void _panStart(Offset at) {
    final p = _clamp(at);
    final r = _dragRect;
    _moveFrom = null;
    if (r != null) {
      final corners = [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight];
      final opposite = [r.bottomRight, r.bottomLeft, r.topRight, r.topLeft];
      for (var i = 0; i < 4; i++) {
        if ((corners[i] - p).distance < 32) {
          return setState(() {
            _dragA = opposite[i];
            _dragB = p;
          });
        }
      }
      if (r.contains(p)) {
        _moveFrom = p;
        _moveRect = r;
        return;
      }
    }
    setState(() => _dragA = _dragB = p);
  }

  void _panUpdate(Offset at) {
    final p = _clamp(at);
    final from = _moveFrom, r = _moveRect;
    if (from == null || r == null) return setState(() => _dragB = p);
    final d = Offset((p - from).dx.clamp(-r.left, _viewW - r.right), (p - from).dy.clamp(-r.top, _viewH - r.bottom));
    setState(() {
      _dragA = r.topLeft + d;
      _dragB = r.bottomRight + d;
    });
  }

  Widget _drawView() {
    final r = _dragRect;
    return GestureDetector(
      onPanStart: (d) => _panStart(d.localPosition),
      onPanUpdate: (d) => _panUpdate(d.localPosition),
      child: Stack(
        children: [
          Positioned.fill(child: Image.memory(_drawImage!, fit: BoxFit.fill, gaplessPlayback: true)),
          if (r != null) ...[
            Positioned.fromRect(
              rect: r,
              child: Container(decoration: BoxDecoration(border: Border.all(color: Palette.pending, width: 3), color: Palette.pending.withValues(alpha: 0.12))),
            ),
            for (final c in [r.topLeft, r.topRight, r.bottomLeft, r.bottomRight])
              Positioned(
                left: c.dx - 9,
                top: c.dy - 9,
                child: IgnorePointer(
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: Palette.pending, width: 3)),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _drawPanel() {
    final r = _dragRect;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('그린 영역', style: Txt.section),
          const SizedBox(height: Space.s),
          Text(r == null ? '물건을 감싸게 끌어 주세요' : '${(r.width * _drawSource.width / _viewW).round()} × ${(r.height * _drawSource.width / _viewW).round()} px', style: Txt.sub),
          if (r != null) ...[
            const SizedBox(height: Space.xs),
            const Text('모서리를 끌면 크기, 안쪽을 끌면 위치를 고쳐요', style: Txt.caption),
          ],
          if (_awaitSide) ...[
            const SizedBox(height: Space.s),
            Text('뒷면 등록: ${app.belongingById(_sideFor ?? '')?.name ?? ''}', style: Txt.sub.copyWith(color: Palette.accent)),
          ],
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(child: AppButton.ghost('다시 그리기', expand: true, onPressed: _busy ? null : () => setState(() => _dragA = _dragB = null))),
              const SizedBox(width: Space.m),
              Expanded(child: AppButton.danger('확인', expand: true, loading: _busy, onPressed: _busy || r == null ? null : _confirmDrawing)),
            ],
          ),
          const SizedBox(height: Space.l),
          if (_note != null) Text(_note!, style: Txt.sub.copyWith(color: Palette.pending)),
        ],
      ),
    );
  }

  // 처음 보는 면은 점수가 낮아 못 알아봐서 뒷면 등록을 권한다
  Widget _sidePanel() {
    final b = app.belongingById(_sideFor!)!;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 84,
                  height: 64,
                  color: Palette.raised,
                  child: b.thumbnail == null ? Icon(b.icon, color: Palette.faint) : Image.memory(b.thumbnail!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(child: Text(_awaitSide ? '${b.name} 뒷면' : '${b.name} 뒷면도 등록할까요?', style: Txt.bodyStrong, maxLines: 2)),
            ],
          ),
          const SizedBox(height: Space.m),
          Text(
            _awaitSide ? '물건을 뒤집어 트레이에 두고, 잡힌 박스를 눌러 주세요.\n박스가 안 잡히면 [직접 그리기]' : '뒤집어서 한 장 더 등록하면 어느 면이 위로 와도 알아봐요',
            style: Txt.sub,
          ),
          const Spacer(),
          if (_note != null) ...[Text(_note!, style: Txt.sub, maxLines: 2), const SizedBox(height: Space.s)],
          Row(
            children: [
              Expanded(
                child: AppButton.ghost(_awaitSide ? '취소' : '건너뛰기', expand: true, onPressed: () => setState(() {
                      _sideFor = null;
                      _awaitSide = false;
                      _note = null;
                    })),
              ),
              if (!_awaitSide) ...[
                const SizedBox(width: Space.s),
                Expanded(
                  flex: 2,
                  child: AppButton('뒷면 등록', icon: Icons.flip_rounded, expand: true, onPressed: () => setState(() {
                        _awaitSide = true;
                        _note = null;
                      })),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemList() {
    final items = app.belongings;
    return _Card(
      child: items.isEmpty
          ? const Center(child: Icon(Icons.inventory_2_outlined, size: 40, color: Palette.faint))
          : ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: Space.s),
              itemBuilder: (context, i) {
                final b = items[i];
                final mine = b.ownedBy(app.userId);
                return Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 52,
                        height: 40,
                        color: Palette.raised,
                        child: b.thumbnail == null ? Icon(b.icon, size: 22, color: Palette.faint) : Image.memory(b.thumbnail!, fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: Space.m),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name, style: Txt.bodyStrong.copyWith(fontSize: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(app.ownerNames(b), style: Txt.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Container(width: 10, height: 10, decoration: BoxDecoration(shape: BoxShape.circle, color: mine ? Palette.done : const Color(0xFF9CA3AF))),
                  ],
                );
              },
            ),
    );
  }

  Widget _panel() {
    final p = _pick;
    if (p == null) return app.belongingById(_sideFor ?? '') != null ? _sidePanel() : _itemList();
    final editing = p.itemId != null;
    final tips = !editing && _name.isEmpty ? _suggestions(p) : const <ItemSuggestion>[];
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 84,
                  height: 64,
                  color: Palette.raised,
                  child: p.crop == null ? const Icon(Icons.image_rounded, color: Palette.faint) : Image.memory(p.crop!, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: Space.m),
              Expanded(child: Text(editing ? (p.learn ? '등록된 물건 같아요' : '등록된 물건') : '새 물건', style: Txt.bodyStrong, maxLines: 2)),
              RoundIconButton(Icons.close_rounded, size: 40, onPressed: _busy ? null : _unpick),
            ],
          ),
          const SizedBox(height: Space.m),
          FieldBox(value: _name, hint: '이름 (예: 지갑)', onTap: _busy ? () {} : _editName),
          if (p.learn) ...[
            const SizedBox(height: Space.s),
            Wrap(children: [
              _tipChip(
                  '다른 물건이에요',
                  false,
                  _busy
                      ? () {}
                      : () => setState(() {
                            _pick = _Pick(frameId: p.frameId, bbox: p.bbox, spaceId: p.spaceId, vector: p.vector)..crop = p.crop;
                            _name = '';
                            _owners
                              ..clear()
                              ..addAll([if (app.userId != null) app.userId!]);
                          })),
            ]),
          ],
          if (tips.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final (i, t) in tips.indexed) _tipChip(i == 0 ? '혹시 ${t.name}?' : t.name, i == 0, () => setState(() => _name = t.name)),
                _tipChip('직접 입력', false, _busy ? () {} : _editName),
              ],
            ),
          ],
          const SizedBox(height: Space.m),
          const Text('주인', style: Txt.section),
          const SizedBox(height: Space.s),
          Wrap(spacing: Space.s, runSpacing: Space.s, children: [for (final u in app.listedUsers) _ownerChip(u.id)]),
          const Spacer(),
          if (_note != null) ...[Text(_note!, style: Txt.sub, maxLines: 2), const SizedBox(height: Space.s)],
          Row(
            children: [
              if (editing && !p.learn) ...[
                Expanded(child: AppButton.ghost('지우기', icon: Icons.delete_outline_rounded, expand: true, onPressed: _busy ? null : _delete)),
                const SizedBox(width: Space.s),
              ],
              Expanded(
                flex: 2,
                child: AppButton(editing ? '저장' : '등록', expand: true, loading: _busy, onPressed: _busy || _name.isEmpty || _owners.isEmpty ? null : _save),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<ItemSuggestion> _suggestions(_Pick p) {
    final c = _catalog;
    if (c == null) {
      ItemCatalog.load().then((v) {
        if (mounted) setState(() => _catalog = v);
      });
      return const [];
    }
    return c.suggest(p.spaceId, p.vector);
  }

  Widget _tipChip(String label, bool primary, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: primary ? Colors.white : Palette.raised,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: primary ? Colors.white : Palette.line),
        ),
        child: Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: primary ? Palette.ink : Palette.text)),
      ),
    );
  }

  Widget _ownerChip(String id) {
    final u = app.userOf(id)!;
    final on = _owners.contains(id);
    return InkWell(
      borderRadius: BorderRadius.circular(Radii.pill),
      onTap: () => setState(() => on ? _owners.remove(id) : _owners.add(id)),
      child: Container(
        height: 44,
        padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
        decoration: BoxDecoration(
          color: on ? Palette.soft(Palette.accent) : Palette.raised,
          borderRadius: BorderRadius.circular(Radii.pill),
          border: Border.all(color: on ? Palette.accent : Palette.line, width: on ? 2 : 1.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Avatar(u, size: 32),
            const SizedBox(width: Space.xs),
            Text(u.name, style: Txt.bodyStrong.copyWith(fontSize: 16)),
            if (on) ...[const SizedBox(width: 2), const Icon(Icons.check_rounded, size: 18, color: Palette.accent)],
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;

  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.l),
      decoration: BoxDecoration(color: Palette.raised, borderRadius: BorderRadius.circular(20)),
      child: child,
    );
  }
}
