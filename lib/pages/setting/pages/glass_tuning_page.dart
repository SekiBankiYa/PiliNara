import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'package:PiliPlus/common/widgets/glass/kyant_glass_tabs.dart';
import 'package:PiliPlus/models/glass_tuning.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// Detail page for the bottom bar's liquid glass: presets, live preview and
/// every knob the shader/springs expose.
class GlassTuningPage extends StatefulWidget {
  const GlassTuningPage({super.key});

  @override
  State<GlassTuningPage> createState() => _GlassTuningPageState();
}

class _GlassTuningPageState extends State<GlassTuningPage> {
  late GlassTuning _t = Pref.glassTuning.clone();
  int? _preset;
  int? _customPreset;
  Timer? _saveTimer;

  /// Live tab of the preview bar, so the pill can actually be dragged/tapped.
  int _previewTab = 0;

  @override
  void initState() {
    super.initState();
    _matchAll();
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }

  /// Slider drags fire dozens of times per second; only the last frame of a
  /// burst has to reach disk.
  void _commit({bool immediate = false}) {
    setState(_matchAll);
    _saveTimer?.cancel();
    if (immediate) {
      Pref.setGlassTuning(_t);
      return;
    }
    _saveTimer = Timer(const Duration(milliseconds: 200), () {
      Pref.setGlassTuning(_t);
    });
  }

  /// Highlights whichever preset (built-in or user-saved) the current values
  /// reproduce exactly.
  void _matchAll() {
    _preset = null;
    _customPreset = null;
    for (var i = 0; i < kGlassPresets.length; i++) {
      if (kGlassPresets[i].values.sameAs(_t)) {
        _preset = i;
        return;
      }
    }
    final custom = Pref.glassCustomPresets;
    for (var i = 0; i < custom.length; i++) {
      if (custom[i].values.sameAs(_t)) {
        _customPreset = i;
        return;
      }
    }
  }

  void _applyPreset(int i) {
    setState(() {
      _t = kGlassPresets[i].values.clone();
      _preset = i;
      _customPreset = null;
    });
    _commit(immediate: true);
  }

  void _applyCustom(int i) {
    final list = Pref.glassCustomPresets;
    if (i < 0 || i >= list.length) return;
    setState(() {
      _t = list[i].values.clone();
      _preset = null;
      _customPreset = i;
    });
    _commit(immediate: true);
  }

  /// Saves the current knobs as a reusable preset.
  Future<void> _saveCustom() async {
    final controller = TextEditingController(
      text: '我的模板 ${Pref.glassCustomPresets.length + 1}',
    );
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('保存为预设'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(hintText: '给这套参数起个名字'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || name == null) return;
    final trimmed = name.trim().isEmpty ? '未命名模板' : name.trim();
    final list = List.of(Pref.glassCustomPresets);
    final preset = GlassCustomPreset(name: trimmed, values: _t.clone());
    final existing = list.indexWhere((p) => p.name == trimmed);
    if (existing >= 0) {
      list[existing] = preset;
    } else {
      list.add(preset);
    }
    Pref.setGlassCustomPresets(list);
    setState(() {
      _preset = null;
      _customPreset = existing >= 0 ? existing : list.length - 1;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('已保存预设「$trimmed」')));
  }

  Future<void> _deleteCustom(int i) async {
    final list = List.of(Pref.glassCustomPresets);
    if (i < 0 || i >= list.length) return;
    final removed = list[i];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除预设'),
        content: Text('确定删除「${removed.name}」？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    list.removeAt(i);
    Pref.setGlassCustomPresets(list);
    setState(_matchAll);
  }

  void _reset() {
    setState(() {
      _t = kGlassPresets[1].values.clone();
      _preset = 1;
      _customPreset = null;
    });
    _commit(immediate: true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('液态玻璃设置'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: '复制参数',
            icon: const Icon(Icons.copy_all_outlined),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _t.readout));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('参数已复制')));
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _sectionTitle('预设模板'),
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount:
                  kGlassPresets.length + Pref.glassCustomPresets.length + 1,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                if (i < kGlassPresets.length) {
                  final p = kGlassPresets[i];
                  return _presetCard(
                    name: p.name,
                    note: p.note,
                    on: _preset == i,
                    onTap: () => _applyPreset(i),
                  );
                }
                final c = i - kGlassPresets.length;
                final custom = Pref.glassCustomPresets;
                if (c < custom.length) {
                  return _presetCard(
                    name: custom[c].name,
                    note: '自定义模板 · 长按删除',
                    on: _customPreset == c,
                    onTap: () => _applyCustom(c),
                    onLongPress: () => _deleteCustom(c),
                  );
                }
                return _presetCard(
                  name: '保存当前',
                  note: '把现在的参数存成一个模板',
                  on: false,
                  icon: Icons.add,
                  onTap: _saveCustom,
                );
              },
            ),
          ),
          _sectionTitle('实时预览'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 240,
                child: Stack(
                  children: [
                    const Positioned.fill(child: _PreviewBackdrop()),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 8,
                      child: Center(
                        // Same geometry as the real bar (3 tabs × 86dp, 64dp
                        // high) and the same filled/unfilled icon switch, so
                        // what the sliders show here is what the main page
                        // draws — it used to be a 260×58 bar with plain
                        // outlined icons, which made the preview look nothing
                        // like the home screen bar.
                        child: LiquidGlassTabs(
                          tabs: [
                            for (final (i, label) in const [
                              (0, '首页'),
                              (1, '动态'),
                              (2, '我的'),
                            ])
                              GlassTab(
                                label: label,
                                iconBuilder: (context, lit, color) => Icon(
                                  switch (i) {
                                    0 => lit
                                        ? Icons.home_rounded
                                        : Icons.home_outlined,
                                    1 => lit
                                        ? Icons.explore_rounded
                                        : Icons.explore_outlined,
                                    _ => lit
                                        ? Icons.person_rounded
                                        : Icons.person_outline_rounded,
                                  },
                                  size: 24,
                                  color: color,
                                ),
                              ),
                          ],
                          selected: _previewTab,
                          onChanged: (i) => setState(() => _previewTab = i),
                          style: _t.toStyle(dark: dark),
                          accent: cs.primary,
                          foreground: cs.onSurfaceVariant,
                          width: 258,
                          height: 64,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _sectionTitle('自定义设置'),
          _group('底栏', [
            _SliderRow(
              label: '背景模糊',
              value: _t.blur,
              min: 0,
              max: 30,
              onChanged: (v) => setState(() => _t.blur = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '白色底罩',
              value: _t.tintAlpha,
              min: 0,
              max: .5,
              onChanged: (v) => setState(() => _t.tintAlpha = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '边缘色散',
              value: _t.dispersion,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _t.dispersion = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '折射带宽',
              value: _t.shellRefH,
              min: 0,
              max: 24,
              onChanged: (v) => setState(() => _t.shellRefH = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '折射强度',
              value: _t.shellRefA,
              min: 0,
              max: 40,
              onChanged: (v) => setState(() => _t.shellRefA = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '边缘高光',
              value: _t.shellHighlight,
              min: 0,
              max: .4,
              onChanged: (v) => setState(() => _t.shellHighlight = v),
              onEnd: _commit,
            ),
          ]),
          _group('选中胶囊', [
            _SliderRow(
              label: '静止折射',
              value: _t.restLens,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _t.restLens = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '折射带宽',
              value: _t.lensRefH,
              min: 0,
              max: 16,
              onChanged: (v) => setState(() => _t.lensRefH = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '折射强度',
              value: _t.lensRefA,
              min: 0,
              max: 24,
              onChanged: (v) => setState(() => _t.lensRefA = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '高光',
              value: _t.lensHighlight,
              min: 0,
              max: .2,
              onChanged: (v) => setState(() => _t.lensHighlight = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '静止底色',
              value: _t.lensTintRest,
              min: 0,
              max: .2,
              onChanged: (v) => setState(() => _t.lensTintRest = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '按下底色',
              value: _t.lensTintPress,
              min: 0,
              max: .2,
              onChanged: (v) => setState(() => _t.lensTintPress = v),
              onEnd: _commit,
            ),
          ]),
          _group('按压动效', [
            _SliderRow(
              label: '按下拉伸',
              value: _t.pressStretch,
              min: 1,
              max: 1.2,
              onChanged: (v) => setState(() => _t.pressStretch = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '按下加宽',
              value: _t.pressWidthGrow,
              min: 0,
              max: 12,
              onChanged: (v) => setState(() => _t.pressWidthGrow = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '按下加高',
              value: _t.pressHeightGrow,
              min: 0,
              max: 10,
              onChanged: (v) => setState(() => _t.pressHeightGrow = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '按下放大',
              value: _t.pressScaleGrow,
              min: 0,
              max: 16,
              onChanged: (v) => setState(() => _t.pressScaleGrow = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '惯性拉伸',
              value: _t.velocityStretch,
              min: 0,
              max: 1,
              onChanged: (v) => setState(() => _t.velocityStretch = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '按下弹簧',
              value: _t.stretchK,
              min: 200,
              max: 900,
              decimals: 0,
              onChanged: (v) => setState(() => _t.stretchK = v),
              onEnd: _commit,
            ),
            _SliderRow(
              label: '回弹弹簧',
              value: _t.releaseK,
              min: 200,
              max: 900,
              decimals: 0,
              onChanged: (v) => setState(() => _t.releaseK = v),
              onEnd: _commit,
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              _t.readout,
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: OutlinedButton.icon(
              onPressed: _reset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('恢复默认'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
  );

  /// One template card in the preset strip. [icon] turns it into the
  /// "保存当前" affordance.
  Widget _presetCard({
    required String name,
    required String note,
    required bool on,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    IconData? icon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final fg = on ? cs.onPrimary : cs.onSurface;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        width: 150,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: on ? cs.primary : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(14),
          border: icon == null
              ? null
              : Border.all(color: cs.outlineVariant, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: fg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              note,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                color: fg.withValues(alpha: .75),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _group(String title, List<Widget> rows) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
    child: Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          ...rows,
        ],
      ),
    ),
  );
}

class _SliderRow extends StatefulWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    required this.onEnd,
    this.decimals = 2,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final VoidCallback onEnd;
  final int decimals;

  @override
  State<_SliderRow> createState() => _SliderRowState();
}

class _SliderRowState extends State<_SliderRow> {
  late final TextEditingController _c = TextEditingController(
    text: _fmt(widget.value),
  );
  final _focus = FocusNode();

  String _fmt(double v) =>
      v.toStringAsFixed(widget.decimals).replaceFirst(RegExp(r'\.?0+$'), '');

  @override
  void didUpdateWidget(covariant _SliderRow old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && _c.text != _fmt(widget.value)) {
      _c.text = _fmt(widget.value);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _submit(String raw) {
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed == null) {
      _c.text = _fmt(widget.value);
      return;
    }
    final v = parsed.clamp(widget.min, widget.max);
    widget.onChanged(v);
    _c.text = _fmt(v);
    widget.onEnd();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(widget.label, style: const TextStyle(fontSize: 13)),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                value: widget.value.clamp(widget.min, widget.max),
                min: widget.min,
                max: widget.max,
                onChanged: widget.onChanged,
                onChangeEnd: (_) => widget.onEnd(),
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: TextField(
              controller: _c,
              focusNode: _focus,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 8,
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: cs.outlineVariant),
                ),
              ),
              onSubmitted: _submit,
              onTapOutside: (_) {
                _focus.unfocus();
                _submit(_c.text);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A stand-in feed so the glass has something worth refracting.
///
/// Scrollable on purpose: dragging it under the bar is how the refraction gets
/// judged, so the content is taller than the 240dp preview window.
class _PreviewBackdrop extends StatelessWidget {
  const _PreviewBackdrop();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final caption = TextStyle(fontSize: 11, color: cs.onSurfaceVariant);
    Widget item(String title, {required Widget body}) => Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text('The quick brown fox jumps over the lazy dog.', style: caption),
          const SizedBox(height: 6),
          body,
        ],
      ),
    );

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            item(
              'ITEM 1 · 标题行 0123456789',
              body: Row(
                children: [
                  for (final c in const [
                    Color(0xFFD9453F),
                    Color(0xFFE2A33C),
                    Color(0xFF3E9E5B),
                    Color(0xFF3D6EDB),
                  ])
                    Container(
                      width: 42,
                      height: 26,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: c,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                ],
              ),
            ),
            item(
              'ITEM 2 · 标题行 0123456789',
              body: Container(
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF2B5B8F),
                      Color(0xFF6E3FA3),
                      Color(0xFFC7752C),
                    ],
                  ),
                ),
              ),
            ),
            item(
              'ITEM 3 · 标题行 0123456789',
              body: Row(
                children: [
                  for (var i = 0; i < 8; i++)
                    Container(
                      width: 14,
                      height: 34,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(
                        color: i.isEven
                            ? const Color(0xFF20242B)
                            : const Color(0xFFE8E2D8),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
