import 'package:flutter/material.dart';
import 'app_theme.dart';

enum _ButtonKind { primary, secondary, ghost, danger }

class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  @override
  Widget build(BuildContext context) => _AppButton(
    kind: _ButtonKind.primary,
    label: label,
    onPressed: onPressed,
    icon: icon,
    loading: loading,
    expand: expand,
  );
}

class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  @override
  Widget build(BuildContext context) => _AppButton(
    kind: _ButtonKind.secondary,
    label: label,
    onPressed: onPressed,
    icon: icon,
    loading: loading,
    expand: expand,
  );
}

class GhostButton extends StatelessWidget {
  const GhostButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _AppButton(
    kind: _ButtonKind.ghost,
    label: label,
    onPressed: onPressed,
    icon: icon,
  );
}

class DangerButton extends StatelessWidget {
  const DangerButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => _AppButton(
    kind: _ButtonKind.danger,
    label: label,
    onPressed: onPressed,
    icon: icon,
  );
}

class _AppButton extends StatelessWidget {
  const _AppButton({
    required this.kind,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
    this.expand = false,
  });
  final _ButtonKind kind;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;
  final bool expand;
  @override
  Widget build(BuildContext context) {
    final foreground = kind == _ButtonKind.primary || kind == _ButtonKind.danger
        ? Colors.white
        : AppColors.textPrimary;
    final background = switch (kind) {
      _ButtonKind.primary => AppColors.primary,
      _ButtonKind.danger => AppColors.error,
      _ButtonKind.secondary => AppColors.elevated,
      _ButtonKind.ghost => Colors.transparent,
    };
    final overlay = switch (kind) {
      _ButtonKind.primary => AppColors.primaryHover,
      _ButtonKind.danger => const Color(0xFFDC2626),
      _ => AppColors.hover,
    };
    final button = SizedBox(
      height: 44,
      child: TextButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox.square(
                dimension: 17,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : (icon == null ? const SizedBox.shrink() : Icon(icon, size: 18)),
        label: Text(label),
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? AppColors.textMuted
                : foreground,
          ),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.disabled)
                ? AppColors.elevated.withValues(alpha: .55)
                : s.contains(WidgetState.pressed) ||
                      s.contains(WidgetState.hovered)
                ? overlay
                : background,
          ),
          side: WidgetStatePropertyAll(
            kind == _ButtonKind.secondary
                ? const BorderSide(color: AppColors.border)
                : BorderSide.none,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.button),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          animationDuration: const Duration(milliseconds: 160),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: color ?? AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadii.card),
      border: Border.all(color: AppColors.border),
    ),
    padding: padding,
    child: child,
  );
}

class MaxWidthContainer extends StatelessWidget {
  const MaxWidthContainer({
    super.key,
    required this.child,
    this.maxWidth = 1240,
    this.padding = const EdgeInsets.all(24),
  });
  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
  });
  final String title;
  final String subtitle;
  final String? eyebrow;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[
        Text(
          eyebrow!.toUpperCase(),
          style: const TextStyle(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
      ],
      Text(title, style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      Text(
        subtitle,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),
    ],
  );
}
