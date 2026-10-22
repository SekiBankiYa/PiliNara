// Parameterised fork of `packages/kyant_glass/lib/src/liquid_tabs.dart`
// (Apache-2.0, Copyright 2025 Kyant / Copyright 2026 xiaomanjun233).
//
// Why a fork: four of the values that make LiquidBottomTabs look wrong are
// hard-coded inside it and are not constructor parameters —
//   1. `dispersion: 1` on both shell and moving lens (:227 / :410 upstream),
//   2. lens optics multiplied by press progress `p`, so at rest they are zero,
//   3. press growth constants (_sx/_sy 78/56, width + 8*p, scale 1 + 16/w*p),
//   4. the lens tint is a black wash while the shell tint is white.
// Everything below that is not one of those four is kept byte-for-byte in
// behaviour, so a preset that looks right here can be lifted into the app.
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:kyant_glass/kyant_glass.dart';
// The app is built on material_ui; flutter's own `Theme.of` returns the fallback
// Roboto theme for it, so the label font has to come from the app's ThemeData.
import 'package:material_ui/material_ui.dart' as mui show Theme;

class GlassTab {
  const GlassTab({required this.label, this.icon, this.iconBuilder});
  final String label;
  final IconData? icon;

  /// Overrides [icon]: the host app already builds its own icon widgets.
  final Widget Function(BuildContext context, bool lit, Color color)? iconBuilder;
}

/// All four problem areas are values here instead of literals.
class GlassTabsStyle {
  const GlassTabsStyle({
    required this.name,
    this.shellBlur = 2,
    this.shellRefractionHeight = 10,
    this.shellRefractionAmount = 40,
    this.shellHighlight = .07,
    this.dispersion = 1,
    this.shellTint = const Color(0x80FFFFFF),
    this.lensRefractionHeight = 10,
    this.lensRefractionAmount = 40,
    this.lensHighlight = .07,
    this.restLens = 0,
    this.lensTint = const Color(0xFFFFFFFF),
    this.lensTintRestAlpha = .10,
    this.lensTintPressAlpha = .03,
    // iOS segmented control grows the capsule by a few percent on press, not by
    // a third: at 78/56 the pill visibly puffed up the moment a finger landed.
    this.pressStretch = 1.08,
    this.pressWidthGrow = 8,
    this.pressHeightGrow = 2,
    this.pressScaleGrow = 16,
    this.velocityStretch = .75,
    this.stretchStiffness = 250,
    this.releaseStiffness = 250,
    this.settleRepress = true,
    this.immediateRelease = false,
    this.debugShapeTiming = false,
  });

  final String name;

  // Shell optics.
  final double shellBlur,
      shellRefractionHeight,
      shellRefractionAmount,
      shellHighlight,
      dispersion;
  final Color shellTint;

  // Lens optics.
  final double lensRefractionHeight,
      lensRefractionAmount,
      lensHighlight,
      restLens;
  final Color lensTint;
  final double lensTintRestAlpha, lensTintPressAlpha;

  // Press / drag motion.
  final double pressStretch, pressWidthGrow, pressHeightGrow, pressScaleGrow;
  final double velocityStretch;

  /// Spring stiffness used while the finger is down (higher = snappier squash).
  final double stretchStiffness;

  /// Spring stiffness used when the squash relaxes back to rest. Upstream
  /// reused [stretchStiffness] here, which is why a released pill stayed
  /// stretched for a few hundred milliseconds.
  final double releaseStiffness;

  /// `true` reproduces upstream `_settle()`, which fires `_pressed()` even when
  /// no finger is down — so a tap re-squashes the pill *after* release.
  final bool settleRepress;

  /// `true` relaxes the squash as soon as the pointer lifts instead of waiting
  /// for the value spring to finish (upstream waited, adding ~250 ms of hold).
  final bool immediateRelease;

  /// Logs `SHAPE rest <n>ms` when the squash reaches rest.
  final bool debugShapeTiming;

  /// Fraction of full lens optics shown at rest. `restLens = 0` reproduces the
  /// upstream behaviour where a resting pill is a flat tint.
  double lensAt(double p) => restLens + (1 - restLens) * p;
}

class LiquidGlassTabs extends StatefulWidget {
  const LiquidGlassTabs({
    super.key,
    required this.tabs,
    required this.selected,
    required this.onChanged,
    required this.style,
    required this.accent,
    required this.foreground,
    this.width = 300,
    this.height = 64,
    this.fontSize = 12,
    this.contentSpacing = 2,
    this.backdrop,
  }) : assert(tabs.length >= 2),
       assert(selected >= 0 && selected < tabs.length);

  final List<GlassTab> tabs;
  final int selected;
  final ValueChanged<int> onChanged;
  final GlassTabsStyle style;
  final Color accent, foreground;
  final double width, height, fontSize, contentSpacing;
  final KyantBackdrop? backdrop;

  @override
  State<LiquidGlassTabs> createState() => _LiquidGlassTabsState();
}

class _LiquidGlassTabsState extends State<LiquidGlassTabs>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  late final _value = AnimationController.unbounded(
    vsync: this,
    value: widget.selected.toDouble(),
  );
  late final _press = AnimationController.unbounded(vsync: this);
  late final _sx = AnimationController.unbounded(vsync: this, value: 1);
  late final _sy = AnimationController.unbounded(vsync: this, value: 1);
  late final _shift = AnimationController.unbounded(vsync: this);
  late final _motion = Listenable.merge([_value, _press, _sx, _sy, _shift]);
  double _target = 0;

  /// Set once a gesture actually dispatched a new selection, so a pointer that
  /// is released without a recognised tap/drag can restore the pill instead of
  /// leaving it parked on a tab that was never selected.
  bool _committed = false;
  int? _pointer;
  int _generation = 0;
  bool _dragging = false;
  late final Ticker _dragTicker = createTicker(_dragTick);
  Duration? _lastDragTick;
  double _dragVelocity = 0;
  bool get _reduce => MediaQuery.disableAnimationsOf(context);
  double get _tabWidth => (widget.width - 8) / widget.tabs.length;
  GlassTabsStyle get s => widget.style;

  @override
  void initState() {
    super.initState();
    _target = widget.selected.toDouble();
    WidgetsBinding.instance.addObserver(this);
  }

  Future<void> _spring(
    AnimationController animation,
    double target,
    double stiffness,
    double ratio, {
    double? velocity,
  }) async {
    if (_reduce) {
      animation.value = target;
      return;
    }
    try {
      await animation
          .animateWith(
            SpringSimulation(
              SpringDescription.withDampingRatio(
                mass: 1,
                stiffness: stiffness,
                ratio: ratio,
              ),
              animation.value,
              target,
              velocity ?? animation.velocity,
              tolerance: const Tolerance(distance: .001, velocity: .01),
            ),
          )
          .orCancel;
    } on TickerCanceled {
      /* A newer pointer takes over with the current velocity. */
    }
  }

  Stopwatch? _shapeWatch;
  int _shapeGen = 0;
  bool _shapeLogged = false;

  /// Slides the pill to [index] without notifying, used while the finger is
  /// still down.
  ///
  /// The capsule is supposed to track the finger: pressing a tab used to only
  /// stretch the pill in place and it jumped to the pressed tab after the tap
  /// had been *released*, which felt laggy. Doing it on pointer-down makes the
  /// pill land under the finger immediately; the selection itself is still
  /// dispatched from `onTapUp`.
  void _preview(int index) {
    if (_dragging) return;
    final target = index.toDouble();
    if ((_target - target).abs() < .001 && !_value.isAnimating) return;
    _target = target;
    _spring(_value, target, 900, .9);
  }


  void _pressed() {
    _shapeGen++;
    _shapeLogged = false;
    if (s.debugShapeTiming) {
      (_shapeWatch ??= Stopwatch())
        ..reset()
        ..start();
    }
    _spring(_press, 1, 1000, 1);
    // Widen a little more than it grows tall, like a finger squashing a soft
    // capsule rather than scaling it uniformly.
    _spring(_sx, s.pressStretch, s.stretchStiffness, .8);
    _spring(_sy, 1 + (s.pressStretch - 1) * .4, s.stretchStiffness, .85);
  }

  void _dragTick(Duration elapsed) {
    if (!_dragging) return;
    final dt = _lastDragTick == null
        ? 1 / 60
        : ((elapsed - _lastDragTick!).inMicroseconds / 1000000).clamp(
            1 / 240,
            .04,
          );
    _lastDragTick = elapsed;
    // Track the finger one-to-one, the way an iOS segmented control does: the
    // capsule used to chase `_target` through a stiff spring, which read as lag
    // under the thumb. The release still carries the finger's velocity, so the
    // settle keeps its momentum.
    final next = _target;
    final velocity = (next - _value.value) / dt;
    _value.value = next;
    _dragVelocity = velocity.clamp(-4000.0, 4000.0);
  }

  void _release() {
    final gen = ++_shapeGen;
    _dragVelocity = 0;
    _spring(_press, 0, 1000, 1);
    _spring(_sx, 1, s.releaseStiffness, .85).then((_) {
      if (!mounted || gen != _shapeGen || _shapeLogged) return;
      _shapeLogged = true;
      final elapsed = _shapeWatch?.elapsedMilliseconds;
      if (s.debugShapeTiming && elapsed != null) {
        debugPrint(
          'SHAPE pressToRest ${elapsed}ms '
          '(stretch=${s.pressStretch} relK=${s.releaseStiffness})',
        );
      }
    });
    _spring(_sy, 1, s.releaseStiffness, .9);
    _spring(_shift, 0, 300, 1);
  }

  void _settle(int index, {bool notify = true}) {
    final generation = ++_generation;
    _target = index.toDouble();
    if (_pointer != null || s.settleRepress) _pressed();
    if (notify && index != widget.selected) {
      _committed = true;
      widget.onChanged(index);
    }
    _spring(_value, _target, 620, .82, velocity: _dragVelocity).then((_) {
      if (mounted && generation == _generation && _pointer == null) _release();
    });
  }

  @override
  void didUpdateWidget(LiquidGlassTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        oldWidget.selected != widget.selected &&
        _target != widget.selected) {
      _settle(widget.selected, notify: false);
    }
  }

  void _cancel() {
    _dragTicker.stop();
    _lastDragTick = null;
    _pointer = null;
    _dragging = false;
    _settle(widget.selected, notify: false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _dragTicker.dispose();
    for (final c in [_value, _press, _sx, _sy, _shift]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _buildShell(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(widget.height / 2),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: KyantGlass(
      backdrop: widget.backdrop,
      radius: widget.height / 2,
      blur: s.shellBlur,
      refractionHeight: s.shellRefractionHeight,
      refractionAmount: s.shellRefractionAmount,
      dispersion: s.dispersion,
      highlight: s.shellHighlight,
      tint: s.shellTint,
      child: const SizedBox.expand(),
    ),
  );

  /// Icons and labels, drawn once for the whole bar.
  ///
  /// [forceLit] `null` -> each tab lights up by its own proximity to the pill;
  /// `false` -> every tab paints the unpressed look; `true` -> every tab paints
  /// the pressed look. The bar paints the unpressed sheet and the pill clips the
  /// pressed sheet, so a tab caught under the capsule shows the lit variant and
  /// the rest of the bar stays unlit — never two icons at one spot.
  ///
  // No `Material` wrapper here on purpose: flutter's Material injects
  // `Theme.of(context).textTheme.bodyMedium` (the plain Roboto fallback, the app
  // uses material_ui) as the subtree's DefaultTextStyle, which is what kept the
  // bar labels on the default font.
  Widget _buildGlyphs(
    BuildContext context, {
    required double p,
    required double index,
    bool? forceLit,
  }) => Padding(
    padding: const EdgeInsets.all(4),
    child: Row(
      children: [
        for (var i = 0; i < widget.tabs.length; i++)
          Expanded(
            child: Semantics(
              selected: widget.selected == i,
              button: true,
              onTap: () => _settle(i),
              child: _tabGlyph(
                context,
                i,
                (forceLit ?? (index - i).abs() <= .5)
                    ? widget.accent
                    : widget.foreground,
                forceLit ?? (index - i).abs() <= .5,
                p,
                index,
              ),
            ),
          ),
      ],
    ),
  );

  Widget _tabGlyph(
    BuildContext context,
    int i,
    Color color,
    bool lit,
    double p,
    double index,
  ) {
    final proximity = (1 - (index - i).abs()).clamp(0.0, 1.0);
    // Pull the family/weight from the app theme instead of letting the label
    // fall back to the engine default (see the note in [_buildGlyphs]).
    final base = mui.Theme.of(context).textTheme.bodyMedium;
    final themeWeight = base?.fontWeight ?? FontWeight.w500;
    // Follow the global font family *and* weight; the bar used to hard-code
    // w500 + no family, which is why it never matched the rest of the app.
    final labelStyle = (base ?? const TextStyle()).copyWith(
      fontSize: widget.fontSize,
      height: 1.2,
      fontWeight: themeWeight,
      color: color,
    );
    // A small grow under the finger only; the pill itself does not magnify the
    // glyphs — the reference keeps icon and label at their normal size, and
    // scaling them is what made the two copies look like a double image.
    final pressScale = 1 + .2 * p * proximity;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.tabs[i].icon != null ||
              widget.tabs[i].iconBuilder != null) ...[
            Transform.scale(
              scale: pressScale,
              child: SizedBox.square(
                dimension: 24,
                child: Center(
                  child:
                      widget.tabs[i].iconBuilder != null
                          ? widget.tabs[i].iconBuilder!(context, lit, color)
                          : Icon(widget.tabs[i].icon, size: 24, color: color),
                ),
              ),
            ),
            SizedBox(height: widget.contentSpacing),
          ],
          Transform.scale(
            scale: pressScale,
            child: Text(
              widget.tabs[i].label,
              maxLines: 1,
              style: labelStyle,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) {
      // No `_pointer != null` early return: an UP that never reaches this
      // listener (a second synthetic touch, a lost event) used to leave
      // `_pointer` set forever, which silently disabled the press preview.
      _pointer = event.pointer;
      _generation++;
      _committed = false;
      _pressed();
      // Move the capsule under the finger right away instead of waiting for the
      // tap to be released (see [_preview]).
      final visual = ((event.localPosition.dx - 4) / _tabWidth).floor();
      final index = visual.clamp(0, widget.tabs.length - 1);
      final ltr = Directionality.of(context) == TextDirection.ltr;
      _preview(ltr ? index : widget.tabs.length - 1 - index);
    },
    onPointerUp: (event) {
      if (_pointer != null && _pointer != event.pointer) return;
      _pointer = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _pointer != null) return;
        // A long press (or a gesture the parent scroll won) never commits the
        // pressed tab, so put the pill back where the selection is.
        if (!_committed && _target.round() != widget.selected) {
          _settle(widget.selected, notify: false);
        }
        if (s.immediateRelease || !_value.isAnimating) _release();
      });
    },
    onPointerCancel: (event) {
      if (_pointer == event.pointer) _cancel();
    },
    child: GestureDetector(
      dragStartBehavior: DragStartBehavior.down,
      // Taps are resolved here instead of by per-tab GestureDetectors: nested
      // recognisers lost the arena to the outer drag on real devices (a finger
      // always moves a pixel or two), which left the pill where it was while
      // the page underneath had already switched.
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        final visual = ((details.localPosition.dx - 4) / _tabWidth).floor();
        final index = visual.clamp(0, widget.tabs.length - 1);
        final ltr = Directionality.of(context) == TextDirection.ltr;
        _settle(ltr ? index : widget.tabs.length - 1 - index);
      },
      onHorizontalDragStart: (_) {
        _dragVelocity = _value.velocity;
        _value.stop();
        _dragging = true;
        // Keep the target the press preview already moved to: resetting it to
        // the current (still animating) value here is what used to cancel the
        // "capsule follows the finger on press" motion as soon as the drag
        // recogniser won the arena — which it nearly always does, because a
        // finger moves a pixel or two.
        _target = _target.clamp(0.0, widget.tabs.length - 1.0);
        _lastDragTick = null;
        _dragTicker.start();
      },
      onHorizontalDragUpdate: (event) {
        final direction = Directionality.of(context) == TextDirection.ltr
            ? 1
            : -1;
        _target = (_target + direction * event.delta.dx / _tabWidth).clamp(
          0.0,
          widget.tabs.length - 1.0,
        );
        _shift.value += event.delta.dx;
      },
      onHorizontalDragEnd: (_) {
        _dragTicker.stop();
        _lastDragTick = null;
        _dragging = false;
        _settle(_target.round());
        if (s.immediateRelease) _release();
      },
      onHorizontalDragCancel: _cancel,
      child: AnimatedBuilder(
        animation: _motion,
        child: _buildShell(context),
        builder: (context, shell) {
          final p = _reduce ? 0.0 : _press.value.clamp(0.0, 1.0);
          final index = _value.value.clamp(0.0, widget.tabs.length - 1.0);
          final velocity = ((_dragging ? _dragVelocity : _value.velocity) / 10)
              .clamp(-.27, .27);
          final fraction = (_shift.value / widget.width).clamp(-1.0, 1.0);
          final shift =
              4 * fraction.sign * Curves.easeOut.transform(fraction.abs());
          final ltr = Directionality.of(context) == TextDirection.ltr;
          final visualIndex = ltr ? index : widget.tabs.length - 1 - index;
          final scale = 1 + s.pressScaleGrow / widget.width * p;
          // Back to the v20 capsule: one tab wide, as tall as the bar minus its
          // padding, sliding between tabs. A round lens made the bar read as a
          // magnifying glass travelling over the icons, and the glyphs inside it
          // had to be redrawn — which is what produced the double-icon look the
          // caller rejected.
          final pillH = widget.height - 8 + s.pressHeightGrow * p;
          final pillW = _tabWidth + s.pressWidthGrow * p;
          final pillLeft =
              4 + visualIndex * _tabWidth - s.pressWidthGrow / 2 * p;
          final lens = s.lensAt(p);
          final tintAlpha =
              s.lensTintRestAlpha * (1 - p) + s.lensTintPressAlpha * p;
          final pill = Rect.fromLTWH(
            pillLeft,
            (widget.height - pillH) / 2,
            pillW,
            pillH,
          );
          // The squash is folded into the rect itself instead of being applied
          // as a Transform around the glass body. A Transform only scaled the
          // body: the rim and the pressed sheet stayed at the unstretched size,
          // so at high "按下拉伸" the white border and the filled glyphs sat
          // outside the glass and the capsule looked unpressed. One rect here
          // drives body, rim and clip, so everything stretches together — and
          // the glyphs keep their own proportions because only the clip grows.
          final sx = _reduce
              ? 1.0
              : _sx.value / (1 - velocity * s.velocityStretch * .5);
          final sy = _reduce
              ? 1.0
              : _sy.value * (1 - velocity * s.velocityStretch / 6);
          final lensRect = Rect.fromCenter(
            center: pill.center,
            width: pillW * sx,
            height: pillH * sy,
          );
          final lensRadius = BorderRadius.circular(lensRect.height / 2);
          // The bar paints the unpressed state everywhere, the lens paints the
          // pressed state on top of the glass, and the two are allowed to
          // overlap — that stacked, blended look is what the reference shows.
          return Transform.translate(
            offset: Offset(shift, 0),
            child: Transform.scale(
              scale: scale,
              child: SizedBox(
                width: widget.width,
                height: widget.height,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: shell!),
                    // Base sheet: every tab keeps its *unpressed* look (outline
                    // icon, normal label). The pressed copy is painted by the
                    // lens on top, so the glass ends up showing both states
                    // stacked — the reference "two layers of glass" look.
                    Positioned.fill(
                      child: _buildGlyphs(
                        context,
                        p: p,
                        index: index,
                        forceLit: false,
                      ),
                    ),
                    Positioned.fromRect(
                      rect: lensRect,
                      child: IgnorePointer(
                        child: KyantGlass(
                          key: const ValueKey('kyant-dock-lens'),
                          radius: lensRect.height / 2,
                          blur: 0,
                          // A capsule this thin reads its edge refraction as a
                          // smear of whatever glyph sits near the rim, so the
                          // lens distorts noticeably less than the bar itself.
                          refractionHeight: s.lensRefractionHeight * lens * .7,
                          refractionAmount: s.lensRefractionAmount * lens * .7,
                          dispersion: s.dispersion * .8,
                          highlight: s.lensHighlight * lens,
                          tint: s.lensTint.withValues(alpha: tintAlpha),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                    // Pressed sheet, clipped to the stretched capsule: the tabs
                    // under the pill are drawn in accent colour with filled icons
                    // at their normal size, the rest of the bar keeps the
                    // unpressed sheet below. One icon per spot — the cup is
                    // filled in, not doubled.
                    Positioned.fromRect(
                      rect: lensRect,
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              ClipRRect(
                                borderRadius: lensRadius,
                                child: Stack(
                                  clipBehavior: Clip.none,
                                  children: [
                                    Positioned(
                                      left: -lensRect.left,
                                      top: -lensRect.top,
                                      width: widget.width,
                                      height: widget.height,
                                      child: SizedBox(
                                        width: widget.width,
                                        height: widget.height,
                                        child: _buildGlyphs(
                                          context,
                                          p: p,
                                          index: index,
                                          forceLit: true,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              // Light-catching edge: the glass body alone is too
                              // faint to read as a capsule on flat backgrounds.
                              Positioned.fill(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: lensRadius,
                                    border: Border.all(
                                      color: Colors.white.withValues(
                                        alpha: 0.42,
                                      ),
                                      width: 1.3,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// Kept so a caller can ask whether real refraction is available at all.
bool get liveRefractionSupported => ui.ImageFilter.isShaderFilterSupported;

