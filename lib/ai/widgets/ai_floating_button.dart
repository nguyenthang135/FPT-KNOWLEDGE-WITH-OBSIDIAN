import 'package:flutter/material.dart';

import '../../design_system/app_theme.dart';

class AiFloatingButton extends StatefulWidget {
  const AiFloatingButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Hỏi Trợ lý AI',
    this.size = 58.0,
  });

  final VoidCallback onPressed;
  final String tooltip;
  final double size;

  @override
  State<AiFloatingButton> createState() => _AiFloatingButtonState();
}

class _AiFloatingButtonState extends State<AiFloatingButton>
    with SingleTickerProviderStateMixin {
  bool _hovered = false;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseScale;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat(reverse: true);

    _pulseScale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: AnimatedScale(
          scale: _hovered ? 1.10 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // Outer Ambient Glow Aura matching logo dual-colors
              AnimatedBuilder(
                animation: _pulseScale,
                builder: (context, _) {
                  return Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(
                            alpha: _hovered ? 0.45 : 0.28,
                          ),
                          blurRadius: _hovered ? 24 : 16,
                          spreadRadius: _hovered ? 3 : 1,
                          offset: const Offset(-2, 4),
                        ),
                        BoxShadow(
                          color: const Color(0xFF9333EA).withValues(
                            alpha: _hovered ? 0.40 : 0.22,
                          ),
                          blurRadius: _hovered ? 28 : 20,
                          spreadRadius: _hovered ? 3 : 1,
                          offset: const Offset(3, 4),
                        ),
                      ],
                    ),
                  );
                },
              ),

              // Main Circular Button Body
              Material(
                color: Colors.transparent,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: widget.onPressed,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.surface,
                      border: Border.all(
                        color: _hovered
                            ? const Color(0xFF3B82F6)
                            : const Color(0xFFE2E8F0),
                        width: 2.0,
                      ),
                    ),
                    padding: const EdgeInsets.all(9),
                    child: Image.asset(
                      'img/ai-assistant-logo.png',
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),

              // Active Glowing Green Online Status Dot
              Positioned(
                top: 1,
                right: 1,
                child: Container(
                  width: 13,
                  height: 13,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF22C55E),
                    border: Border.all(
                      color: AppColors.surface,
                      width: 2,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x6622C55E),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
