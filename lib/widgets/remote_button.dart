import 'package:flutter/material.dart';

/// A reusable, chunky remote-control button with an icon and optional label.
///
/// Used throughout the remote screen for power, navigation, volume, etc.
/// Pass [onPressed] = null to render a disabled button.
class RemoteButton extends StatelessWidget {
  const RemoteButton({
    super.key,
    required this.icon,
    this.label,
    required this.onPressed,
    this.color,
    this.foregroundColor,
    this.tooltip,
  });

  /// The glyph shown in the button.
  final IconData icon;

  /// Optional text shown beneath the icon.
  final String? label;

  /// Tap handler. When null, the button is disabled.
  final VoidCallback? onPressed;

  /// Optional background color override.
  final Color? color;

  /// Optional icon/label color override.
  final Color? foregroundColor;

  /// Optional long-press tooltip (also aids accessibility).
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = color ?? theme.colorScheme.surfaceContainerHighest;
    final fg = foregroundColor ?? theme.colorScheme.onSurface;

    final button = Material(
      color: onPressed == null ? bg.withValues(alpha: 0.4) : bg,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: fg),
              if (label != null) ...[
                const SizedBox(height: 6),
                Text(
                  label!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelMedium?.copyWith(color: fg),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
