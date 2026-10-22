import 'package:flutter/widgets.dart';
import 'package:material_ui/material_ui.dart' show Theme;

import 'package:PiliPlus/common/widgets/glass/kyant_glass_tabs.dart';
import 'package:PiliPlus/models/glass_tuning.dart';
import 'package:PiliPlus/utils/storage_pref.dart';

/// One bottom-bar destination rendered by the glass bar.
///
/// The host already builds its own icon widgets (badges, avatars, custom
/// glyphs), so the icon is passed as a builder rather than an [IconData].
class GlassBarTab {
  const GlassBarTab({required this.label, required this.iconBuilder});

  final String label;
  final Widget Function(BuildContext context, bool lit, Color color) iconBuilder;
}

/// Liquid-glass replacement for the floating navigation bar.
///
/// Kept as a thin adapter: the app keeps owning tab semantics, selection and
/// preferences, this widget only draws them through the glass.
class KyantGlassBar extends StatelessWidget {
  const KyantGlassBar({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onSelected,
    this.width = 300,
    this.height = 64,
  });

  final List<GlassBarTab> tabs;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return ValueListenableBuilder<int>(
      valueListenable: glassTuningRevision,
      builder: (context, _, _) => LiquidGlassTabs(
        tabs: [
          for (var i = 0; i < tabs.length; i++)
            GlassTab(
              label: tabs[i].label,
              iconBuilder: (context, lit, color) =>
                  tabs[i].iconBuilder(context, lit, color),
            ),
        ],
        selected: selectedIndex,
        onChanged: onSelected,
        style: Pref.glassTuning.toStyle(dark: dark),
        accent: theme.colorScheme.primary,
        foreground: theme.colorScheme.onSurfaceVariant,
        width: width,
        height: height,
      ),
    );
  }
}
