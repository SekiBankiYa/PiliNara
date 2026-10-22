// Tunable parameters for the bottom bar's liquid glass.
//
// One [GlassTuning] instance == one complete look. It is persisted as a single
// JSON string under [SettingBoxKey.glassTuning] (rather than 19 separate keys)
// so a look can be copied, reset and shared as one blob.
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Color;

import 'package:PiliPlus/common/widgets/glass/kyant_glass_tabs.dart';

/// Bumped whenever the persisted tuning changes, so the bottom bar can repaint
/// without the whole page rebuilding.
final ValueNotifier<int> glassTuningRevision = ValueNotifier<int>(0);

/// Bumped when the bottom bar *variant* changes (plain floating bar ↔ liquid
/// glass), so the host can cross-fade live instead of asking for a restart.
final ValueNotifier<int> glassBarModeRevision = ValueNotifier<int>(0);

class GlassTuning {
  GlassTuning({
    this.blur = 10,
    this.tintAlpha = .20,
    this.dispersion = .10,
    this.shellRefH = 10,
    this.shellRefA = 22,
    this.shellHighlight = .12,
    this.restLens = .7,
    this.lensRefH = 12,
    this.lensRefA = 18,
    this.lensHighlight = .14,
    this.lensTintRest = .06,
    this.lensTintPress = .10,
    this.pressStretch = 1.03,
    this.pressWidthGrow = 0,
    this.pressHeightGrow = 0,
    this.pressScaleGrow = 3,
    this.velocityStretch = .4,
    this.stretchK = 500,
    this.releaseK = 420,
  });

  factory GlassTuning.fromJson(Map<String, dynamic> j) => GlassTuning(
    blur: _d(j['blur'], 10),
    tintAlpha: _d(j['tintAlpha'], .20),
    dispersion: _d(j['dispersion'], .10),
    shellRefH: _d(j['shellRefH'], 10),
    shellRefA: _d(j['shellRefA'], 22),
    shellHighlight: _d(j['shellHighlight'], .12),
    restLens: _d(j['restLens'], .7),
    lensRefH: _d(j['lensRefH'], 12),
    lensRefA: _d(j['lensRefA'], 18),
    lensHighlight: _d(j['lensHighlight'], .14),
    lensTintRest: _d(j['lensTintRest'], .05),
    lensTintPress: _d(j['lensTintPress'], .10),
    pressStretch: _d(j['pressStretch'], 1.03),
    pressWidthGrow: _d(j['pressWidthGrow'], 0),
    pressHeightGrow: _d(j['pressHeightGrow'], 0),
    pressScaleGrow: _d(j['pressScaleGrow'], 3),
    velocityStretch: _d(j['velocityStretch'], .4),
    stretchK: _d(j['stretchK'], 500),
    releaseK: _d(j['releaseK'], 420),
  );

  static double _d(Object? v, double fallback) =>
      v is num ? v.toDouble() : fallback;

  double blur,
      tintAlpha,
      dispersion,
      shellRefH,
      shellRefA,
      shellHighlight,
      restLens,
      lensRefH,
      lensRefA,
      lensHighlight,
      lensTintRest,
      lensTintPress,
      pressStretch,
      pressWidthGrow,
      pressHeightGrow,
      pressScaleGrow,
      velocityStretch,
      stretchK,
      releaseK;

  Map<String, dynamic> toJson() => {
    'blur': blur,
    'tintAlpha': tintAlpha,
    'dispersion': dispersion,
    'shellRefH': shellRefH,
    'shellRefA': shellRefA,
    'shellHighlight': shellHighlight,
    'restLens': restLens,
    'lensRefH': lensRefH,
    'lensRefA': lensRefA,
    'lensHighlight': lensHighlight,
    'lensTintRest': lensTintRest,
    'lensTintPress': lensTintPress,
    'pressStretch': pressStretch,
    'pressWidthGrow': pressWidthGrow,
    'pressHeightGrow': pressHeightGrow,
    'pressScaleGrow': pressScaleGrow,
    'velocityStretch': velocityStretch,
    'stretchK': stretchK,
    'releaseK': releaseK,
  };

  String encode() => jsonEncode(toJson());

  static GlassTuning? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return GlassTuning.fromJson(j);
    } catch (_) {}
    return null;
  }

  GlassTuning clone() => GlassTuning.fromJson(toJson());

  GlassTuning copyFrom(GlassTuning o) => this
    ..blur = o.blur
    ..tintAlpha = o.tintAlpha
    ..dispersion = o.dispersion
    ..shellRefH = o.shellRefH
    ..shellRefA = o.shellRefA
    ..shellHighlight = o.shellHighlight
    ..restLens = o.restLens
    ..lensRefH = o.lensRefH
    ..lensRefA = o.lensRefA
    ..lensHighlight = o.lensHighlight
    ..lensTintRest = o.lensTintRest
    ..lensTintPress = o.lensTintPress
    ..pressStretch = o.pressStretch
    ..pressWidthGrow = o.pressWidthGrow
    ..pressHeightGrow = o.pressHeightGrow
    ..pressScaleGrow = o.pressScaleGrow
    ..velocityStretch = o.velocityStretch
    ..stretchK = o.stretchK
    ..releaseK = o.releaseK;

  bool sameAs(GlassTuning o) => encode() == o.encode();

  /// [dark] swaps the wash to a dark film so the bar does not glow on AMOLED.
  GlassTabsStyle toStyle({String name = 'custom', bool dark = false}) =>
      GlassTabsStyle(
        name: name,
        shellBlur: blur,
        shellTint: dark
            ? Color.fromRGBO(0, 0, 0, tintAlpha)
            : Color.fromRGBO(255, 255, 255, tintAlpha),
        dispersion: dispersion,
        shellRefractionHeight: shellRefH,
        shellRefractionAmount: shellRefA,
        shellHighlight: shellHighlight,
        restLens: restLens,
        lensRefractionHeight: lensRefH,
        lensRefractionAmount: lensRefA,
        lensHighlight: lensHighlight,
        lensTintRestAlpha: lensTintRest,
        lensTintPressAlpha: lensTintPress,
        pressStretch: pressStretch,
        pressWidthGrow: pressWidthGrow,
        pressHeightGrow: pressHeightGrow,
        pressScaleGrow: pressScaleGrow,
        velocityStretch: velocityStretch,
        stretchStiffness: stretchK,
        releaseStiffness: releaseK,
        settleRepress: false,
        immediateRelease: true,
      );

  String get readout {
    String f(double v) =>
        v.toStringAsFixed(3).replaceFirst(RegExp(r'\.?0+$'), '');
    return 'blur ${f(blur)} | tint ${f(tintAlpha)} | disp ${f(dispersion)} | '
        'shellLens ${f(shellRefH)}/${f(shellRefA)} | hl ${f(shellHighlight)} | '
        'restLens ${f(restLens)} | lens ${f(lensRefH)}/${f(lensRefA)} | '
        'lensHl ${f(lensHighlight)} | lensTint ${f(lensTintRest)}/${f(lensTintPress)} | '
        'press ${f(pressStretch)}/+${f(pressWidthGrow)}/+${f(pressHeightGrow)}/'
        '+${f(pressScaleGrow)} | vel ${f(velocityStretch)} | '
        'k ${f(stretchK)}/${f(releaseK)}';
  }
}

class GlassPreset {
  const GlassPreset({
    required this.name,
    required this.note,
    required this.values,
  });
  final String name;
  final String note;
  final GlassTuning values;
}

/// A preset the user saved from the tuning page.
///
/// Unlike [kGlassPresets] these live in the setting box, so a look that took a
/// few minutes of slider dragging can be recalled (and shared) later.
class GlassCustomPreset {
  GlassCustomPreset({required this.name, required this.values});

  final String name;
  final GlassTuning values;

  Map<String, dynamic> toJson() => {'name': name, 'values': values.toJson()};

  static GlassCustomPreset? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'];
    final values = raw['values'];
    if (name is! String || values is! Map<String, dynamic>) return null;
    return GlassCustomPreset(
      name: name,
      values: GlassTuning.fromJson(values),
    );
  }

  static List<GlassCustomPreset> decodeAll(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final j = jsonDecode(raw);
      if (j is! List) return const [];
      return [
        for (final e in j)
          if (tryFromJson(e) case final p?) p,
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encodeAll(List<GlassCustomPreset> list) =>
      jsonEncode([for (final p in list) p.toJson()]);
}

final kGlassPresets = <GlassPreset>[
  GlassPreset(
    name: '清透',
    note: '背景字清晰可读，像一块透明亚克力',
    values: GlassTuning(blur: 2, tintAlpha: .50),
  ),
  GlassPreset(
    name: '平衡',
    note: '文字化开，颜色还能透出来',
    values: GlassTuning(blur: 10, tintAlpha: .20),
  ),
  GlassPreset(
    name: '磨砂',
    note: '重磨砂，最接近 KernelSU 那种观感',
    values: GlassTuning(blur: 22, tintAlpha: .20),
  ),
  GlassPreset(
    name: '素净',
    note: '不做透镜光学，只留一层平涂色',
    values: GlassTuning(blur: 14, tintAlpha: .26, restLens: 0, lensHighlight: .03),
  ),
  GlassPreset(
    name: '厚白',
    note: '厚白边 + 满折射，选中胶囊像一块凸起的厚玻璃',
    values: GlassTuning(
      blur: 3,
      tintAlpha: .38,
      dispersion: .25,
      shellRefH: 16,
      shellRefA: 30,
      shellHighlight: .24,
      restLens: .85,
      lensRefH: 14,
      lensRefA: 26,
      lensHighlight: .18,
      lensTintRest: .12,
      lensTintPress: .16,
      pressStretch: 1.02,
      pressWidthGrow: 6,
      pressHeightGrow: 4,
      pressScaleGrow: 4,
      velocityStretch: .35,
      stretchK: 620,
      releaseK: 470,
    ),
  ),
];
