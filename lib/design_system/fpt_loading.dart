import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'fpt_logo.dart';

/// A high-tech futuristic loading widget with dual orbital cyber rings,
/// pulsating FPT logo core, ambient glow, and quantum shimmer indicator.
class FptTechLoading extends StatefulWidget {
  const FptTechLoading({
    super.key,
    this.title,
    this.subtitle = 'Synchronizing knowledge workspace...',
    this.size = 176.0,
  });

  final String? title;
  final String? subtitle;
  final double size;

  @override
  State<FptTechLoading> createState() => _FptTechLoadingState();
}

class _FptTechLoadingState extends State<FptTechLoading>
    with TickerProviderStateMixin {
  late final AnimationController _orbitController;
  late final AnimationController _pulseController;
  late final AnimationController _shimmerController;

  late final Animation<double> _pulseAnimation;

  int _currentStep = 0;
  Timer? _stepTimer;
  late final List<String> _steps;

  @override
  void initState() {
    super.initState();

    _steps = [
      widget.subtitle ?? 'Connecting to FPT FLM knowledge cloud...',
      'Deciphering syllabus architecture & learning nodes...',
      'Synthesizing Second Brain knowledge graph...',
      'Finalizing interactive workspace...',
    ];

    _stepTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) {
      if (mounted) {
        setState(() {
          _currentStep = (_currentStep + 1) % _steps.length;
        });
      }
    });

    // Smooth continuous orbital rotation (3.5s per cycle)
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat();

    // Subtle breathing pulse for the central logo core
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOutSine),
    );

    // Quantum linear shimmer bar
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _stepTimer?.cancel();
    _orbitController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Holographic Tech Orbital Core
            SizedBox(
              width: widget.size,
              height: widget.size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Animated Cyber Orbit Rings
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _orbitController,
                      _pulseController,
                    ]),
                    builder: (context, _) {
                      return CustomPaint(
                        size: Size(widget.size, widget.size),
                        painter: _CyberOrbitPainter(
                          orbitProgress: _orbitController.value,
                          pulseProgress: _pulseController.value,
                        ),
                      );
                    },
                  ),

                  // Center Logo Badge with Breathing Pulse
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: widget.size * 0.48,
                      height: widget.size * 0.48,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.surface,
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.18),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                          BoxShadow(
                            color: AppColors.blue.withValues(alpha: 0.10),
                            blurRadius: 36,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: FptLogoMark(height: widget.size * 0.20),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Title / Code Badge
            if (widget.title != null && widget.title!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                decoration: BoxDecoration(
                  color: AppColors.elevated,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.border,
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.title!,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Dynamic animated tech status steps
            SizedBox(
              height: 24,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.25),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  _steps[_currentStep],
                  key: ValueKey<int>(_currentStep),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // Quantum Shimmer Bar
            SizedBox(
              width: 180,
              height: 3.5,
              child: AnimatedBuilder(
                animation: _shimmerController,
                builder: (context, _) {
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Container(
                      color: AppColors.border.withValues(alpha: 0.6),
                      child: CustomPaint(
                        painter: _ShimmerBarPainter(
                          progress: _shimmerController.value,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Custom painter rendering dual rotating cyber orbits and quantum radar pulses.
class _CyberOrbitPainter extends CustomPainter {
  _CyberOrbitPainter({
    required this.orbitProgress,
    required this.pulseProgress,
  });

  final double orbitProgress;
  final double pulseProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 8;
    final innerRadius = outerRadius - 16;
    final forwardAngle = orbitProgress * 2 * math.pi;
    final reverseAngle = -orbitProgress * 2 * math.pi * 1.35;

    // 1. Expanding Quantum Radar Waves (Pulse ripple)
    final rippleRadius = outerRadius * (0.65 + pulseProgress * 0.38);
    final rippleAlpha = (1.0 - pulseProgress) * 0.25;
    if (rippleAlpha > 0) {
      final ripplePaint = Paint()
        ..color = AppColors.primary.withValues(alpha: rippleAlpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2;
      canvas.drawCircle(center, rippleRadius, ripplePaint);
    }

    // 2. Outer Static Thin Track
    final trackPaint = Paint()
      ..color = AppColors.border.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, outerRadius, trackPaint);

    // 3. Outer HUD Crosshair Ticks (0, 90, 180, 270 degrees)
    final tickPaint = Paint()
      ..color = AppColors.textMuted.withValues(alpha: 0.35)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final a = i * (math.pi / 2);
      final p1 = Offset(
        center.dx + (outerRadius - 4) * math.cos(a),
        center.dy + (outerRadius - 4) * math.sin(a),
      );
      final p2 = Offset(
        center.dx + (outerRadius + 4) * math.cos(a),
        center.dy + (outerRadius + 4) * math.sin(a),
      );
      canvas.drawLine(p1, p2, tickPaint);
    }

    // 4. Outer Rotating Glowing Gradient Arcs
    final outerArcRect = Rect.fromCircle(center: center, radius: outerRadius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(forwardAngle);
    canvas.translate(-center.dx, -center.dy);

    final sweepGradient1 = SweepGradient(
      startAngle: 0.0,
      endAngle: math.pi * 1.2,
      colors: [
        AppColors.primary.withValues(alpha: 0.0),
        AppColors.primary.withValues(alpha: 0.45),
        AppColors.primary,
      ],
      stops: const [0.0, 0.4, 1.0],
    );

    final arcPaint1 = Paint()
      ..shader = sweepGradient1.createShader(outerArcRect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(outerArcRect, 0.0, math.pi * 1.15, false, arcPaint1);

    // Luminous head node at the tip of the outer arc
    final headAngle = math.pi * 1.15;
    final headPos = Offset(
      center.dx + outerRadius * math.cos(headAngle),
      center.dy + outerRadius * math.sin(headAngle),
    );
    final glowPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(headPos, 4.5, glowPaint);
    final nodePaint = Paint()..color = AppColors.primary;
    canvas.drawCircle(headPos, 2.5, nodePaint);

    canvas.restore();

    // 5. Inner Counter-Rotating Cyber Orbit (Tech Blue / Emerald Green)
    final innerArcRect = Rect.fromCircle(center: center, radius: innerRadius);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(reverseAngle);
    canvas.translate(-center.dx, -center.dy);

    final innerTrackPaint = Paint()
      ..color = AppColors.blue.withValues(alpha: 0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    canvas.drawCircle(center, innerRadius, innerTrackPaint);

    // Segmented counter-rotating arcs
    final innerArcPaint = Paint()
      ..color = AppColors.blue.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Segment 1
    canvas.drawArc(innerArcRect, 0.0, math.pi * 0.65, false, innerArcPaint);
    // Segment 2 (opposite)
    final innerArcPaint2 = Paint()
      ..color = AppColors.success.withValues(alpha: 0.75)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(innerArcRect, math.pi, math.pi * 0.45, false, innerArcPaint2);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CyberOrbitPainter oldDelegate) {
    return oldDelegate.orbitProgress != orbitProgress ||
        oldDelegate.pulseProgress != pulseProgress;
  }
}

/// Painter for the gliding quantum shimmer bar.
class _ShimmerBarPainter extends CustomPainter {
  _ShimmerBarPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width * 0.38;
    final startX = (size.width + barWidth) * progress - barWidth;

    final rect = Rect.fromLTWH(startX, 0, barWidth, size.height);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [
          AppColors.primary.withValues(alpha: 0.0),
          AppColors.primary,
          AppColors.blue,
          AppColors.blue.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(rect);

    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(covariant _ShimmerBarPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

/// Full screen loading scaffold with top app bar and FptTechLoading body.
class FptLoadingScreen extends StatelessWidget {
  const FptLoadingScreen({
    super.key,
    this.title,
    this.subtitle,
    this.appBarTitle,
  });

  final String? title;
  final String? subtitle;
  final String? appBarTitle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(appBarTitle ?? title ?? 'FPT Knowledge'),
      ),
      body: FptTechLoading(
        title: title,
        subtitle: subtitle,
      ),
    );
  }
}
