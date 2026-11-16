import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 粗描边 + 实色偏移阴影的容器。
class ChunkyBox extends StatelessWidget {
  const ChunkyBox({
    super.key,
    required this.child,
    this.color = AppColors.paper,
    this.radius = AppDims.radius,
    this.shadow = AppDims.shadow,
    this.padding,
    this.borderColor = AppColors.ink,
  });

  final Widget child;
  final Color color;
  final double radius;
  final double shadow;
  final EdgeInsetsGeometry? padding;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: chunkyDecoration(
        color: color,
        radius: radius,
        shadow: shadow,
        borderColor: borderColor,
      ),
      child: child,
    );
  }
}

BoxDecoration chunkyDecoration({
  Color color = AppColors.paper,
  double radius = AppDims.radius,
  double shadow = AppDims.shadow,
  Color borderColor = AppColors.ink,
}) {
  return BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(radius),
    border: Border.all(color: borderColor, width: AppDims.border),
    boxShadow: shadow > 0
        ? [BoxShadow(color: borderColor, offset: Offset(0, shadow))]
        : null,
  );
}

/// 可按压的粗描边组件：按下时整体下沉、阴影收起，模拟实体按键。
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.color = AppColors.paper,
    this.radius = AppDims.radius,
    this.shadow = AppDims.shadow,
    this.padding,
    this.enabled = true,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color color;
  final double radius;
  final double shadow;
  final EdgeInsetsGeometry? padding;
  final bool enabled;
  final String? semanticLabel;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  bool get _active =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final offset = _down ? widget.shadow : 0.0;
    return Semantics(
      button: true,
      enabled: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _active ? (_) => _set(true) : null,
        onTapUp: _active ? (_) => _set(false) : null,
        onTapCancel: _active ? () => _set(false) : null,
        onTap: _active ? widget.onTap : null,
        onLongPress: _active ? widget.onLongPress : null,
        child: Padding(
          // 预留阴影空间，避免下沉时布局跳动
          padding: EdgeInsets.only(bottom: widget.shadow),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 70),
            curve: Curves.easeOut,
            transform: Matrix4.translationValues(0, offset, 0),
            padding: widget.padding,
            decoration: chunkyDecoration(
              color: widget.enabled
                  ? widget.color
                  : Color.lerp(widget.color, AppColors.creamDeep, 0.6)!,
              radius: widget.radius,
              shadow: _down || !widget.enabled ? 0 : widget.shadow,
              borderColor: widget.enabled ? AppColors.ink : AppColors.inkFaint,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// 方形图标按钮
class ChunkyIconButton extends StatelessWidget {
  const ChunkyIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.color = AppColors.paper,
    this.size = 44,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final double size;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Pressable(
      onTap: onTap,
      color: color,
      radius: AppDims.radiusSm,
      shadow: 3,
      semanticLabel: tooltip,
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, color: AppColors.ink, size: size * 0.5),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// 文字按钮
class ChunkyButton extends StatelessWidget {
  const ChunkyButton({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color = AppColors.lemon,
    this.expand = false,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color color;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      color: color,
      radius: 16,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: AppColors.ink),
            const SizedBox(width: 8),
          ],
          Text(label, style: AppText.subtitle),
        ],
      ),
    );
  }
}

/// 小标签
class TagChip extends StatelessWidget {
  const TagChip({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.ink, width: 1.8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

/// 抬头数据块，如“用时 01:23”
class StatPill extends StatelessWidget {
  const StatPill({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.paper,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return ChunkyBox(
      color: color,
      radius: 14,
      shadow: 3,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      // 空间不足时（窄屏/大字体）整体等比缩小，而不是换行或溢出
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppColors.ink),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  style: AppText.caption.copyWith(fontSize: 10),
                ),
                Text(
                  value,
                  maxLines: 1,
                  style: AppText.number.copyWith(fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 一行等宽的格子（如难度选择、各难度纪录）。
///
/// 不超过 [maxVisible] 个时平分整行；更多时可左右滑动，
/// 每屏露出约 [maxVisible] 个半，提示右边还有更多。
class PeekRow extends StatelessWidget {
  const PeekRow({
    super.key,
    required this.children,
    this.gap = 4,
    this.padding = EdgeInsets.zero,
    this.maxVisible = 4,
  });

  final List<Widget> children;
  final double gap;
  final EdgeInsets padding;
  final int maxVisible;

  @override
  Widget build(BuildContext context) {
    final scrolls = children.length > maxVisible;
    return LayoutBuilder(
      builder: (context, constraints) {
        final visible = scrolls ? maxVisible + 0.5 : children.length.toDouble();
        final width =
            (constraints.maxWidth -
                padding.horizontal -
                gap * (visible.ceil() - 1)) /
            visible;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: scrolls
              ? const BouncingScrollPhysics()
              : const NeverScrollableScrollPhysics(),
          padding: padding,
          child: Row(
            children: [
              for (final (i, child) in children.indexed) ...[
                if (i > 0) SizedBox(width: gap),
                SizedBox(width: width, child: child),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// 游戏顶部的数据条：各数据块等宽平分一行。
class StatBar extends StatelessWidget {
  const StatBar({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, child) in children.indexed) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ],
    );
  }
}
