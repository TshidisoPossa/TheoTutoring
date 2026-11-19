import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The animated TheoTutoring introduction shown when the app opens. It stays
/// on screen after the animation until the user taps Continue, then replaces
/// itself, once, with [next]: the app's normal entry (AuthGate), which
/// decides between the user's dashboard and the Log In / Register screen.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// Builds the screen to continue to.
  final WidgetBuilder next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  static const Color brandBlue = Color(0xFF246BFE);
  static const Color lightBlue = Color(0xFF9BC5FF);
  static const Color darkGreen = Color(0xFF12382D);
  static const Color descriptionColor = Color(0xFF435A73);

  late final AnimationController _controller;
  bool _hasNavigated = false;

  late final Animation<double> _bookAnimation;
  late final Animation<double> _logoAnimation;
  late final Animation<double> _taglineAnimation;
  late final Animation<double> _descriptionAnimation;
  late final Animation<double> _buttonAnimation;
  late final Animation<double> _fieldAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6200),
    );

    _fieldAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.58, curve: Curves.easeInOutCubic),
    );

    _bookAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.02, 0.23, curve: Curves.easeOutBack),
    );

    _logoAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.25, 0.42, curve: Curves.easeOut),
    );

    _taglineAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.52, 0.66, curve: Curves.easeOut),
    );

    _descriptionAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.60, 0.78, curve: Curves.easeOut),
    );

    _buttonAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.69, 0.82, curve: Curves.easeOutBack),
    );

    _controller.forward();
  }

  // Only on Continue; repeated taps navigate once.
  void _continueToLogin() {
    if (!mounted || _hasNavigated) return;

    _hasNavigated = true;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: widget.next),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final width = constraints.maxWidth;

            return Stack(
              children: [
                // Animated blue background with a curved lower edge.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _fieldAnimation,
                    builder: (context, child) {
                      return ClipPath(
                        clipper: SplashWaveClipper(
                          progress: _fieldAnimation.value,
                        ),
                        child: Container(color: brandBlue),
                      );
                    },
                  ),
                ),

                // Decorative orbital rings.
                Positioned(
                  top: height * 0.105,
                  left: width * 0.12,
                  right: width * 0.12,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _controller.value * 2 * math.pi,
                        child: Container(
                          height: math.min(width * 0.76, height * 0.32),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.24),
                              width: 1.2,
                            ),
                            borderRadius: BorderRadius.circular(200),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: height * 0.15,
                  left: width * 0.20,
                  right: width * 0.20,
                  child: AnimatedBuilder(
                    animation: _controller,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: -_controller.value * 2 * math.pi * 0.72,
                        child: Container(
                          height: math.min(width * 0.60, height * 0.27),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.18),
                              width: 1.1,
                            ),
                            borderRadius: BorderRadius.circular(200),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Small decorative dots.
                Positioned(
                  top: height * 0.18,
                  left: width * 0.17,
                  child: _decorativeDot(9),
                ),
                Positioned(
                  top: height * 0.29,
                  right: width * 0.16,
                  child: _decorativeDot(12),
                ),
                Positioned(
                  top: height * 0.39,
                  left: width * 0.24,
                  child: _decorativeDot(6),
                ),
                Positioned(
                  top: height * 0.22,
                  right: width * 0.28,
                  child: _decorativeDot(5),
                ),

                // Main content.
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      children: [
                        SizedBox(height: height * 0.105),

                        // Animated open-book illustration.
                        FadeTransition(
                          opacity: _bookAnimation,
                          child: ScaleTransition(
                            scale: Tween<double>(
                              begin: 0.45,
                              end: 1,
                            ).animate(_bookAnimation),
                            child: SizedBox(
                              width: math.min(width * 0.56, 230),
                              height: math.min(height * 0.23, 175),
                              child: const CustomPaint(
                                painter: OpenBookPainter(),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: height * 0.035),

                        // Brand name.
                        FadeTransition(
                          opacity: _logoAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.25),
                              end: Offset.zero,
                            ).animate(_logoAnimation),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                'TheoTutoring',
                                style: TextStyle(
                                  fontSize: width < 360 ? 30 : 36,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.4,
                                  color: darkGreen,
                                ),
                              ),
                            ),
                          ),
                        ),

// Animated underline.
AnimatedBuilder(
  animation: _logoAnimation,
  builder: (context, child) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: 90 * _logoAnimation.value,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white, // visible on the blue background
        borderRadius: BorderRadius.circular(10),
      ),
    );
  },
),
                        const SizedBox(height: 12),

                        FadeTransition(
                          opacity: _taglineAnimation,
                          child: Text(
                            'UNLOCKING YOUR POTENTIAL',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: width < 360 ? 10 : 12,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2.1,
                              color: Colors.white, // on the blue background
                            ),
                          ),
                        ),

                        const Spacer(),

                        // Description and Continue button.
                        FadeTransition(
                          opacity: _descriptionAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.18),
                              end: Offset.zero,
                            ).animate(_descriptionAnimation),
                            child: const Text(
                              'TheoTutoring brings university students '
                              'and tutors together to share knowledge, '
                              'build confidence, and achieve more.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: descriptionColor,
                                fontSize: 15,
                                height: 1.65,
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: height * 0.035),

                        FadeTransition(
                          opacity: _buttonAnimation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.3),
                              end: Offset.zero,
                            ).animate(_buttonAnimation),
                            child: SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _continueToLogin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: brandBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 3,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Continue',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: height * 0.045),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _decorativeDot(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: lightBlue,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// Creates the animated curved edge of the blue background.
class SplashWaveClipper extends CustomClipper<Path> {
  final double progress;

  const SplashWaveClipper({required this.progress});

  @override
  Path getClip(Size size) {
    final path = Path();
    final bottom = size.height * 0.59 * progress;

    path.moveTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, bottom * 0.88);

    path.cubicTo(
      size.width * 0.78,
      bottom * 1.10,
      size.width * 0.35,
      bottom * 0.90,
      0,
      bottom,
    );

    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant SplashWaveClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}

/// Draws an open book using Flutter's canvas.
class OpenBookPainter extends CustomPainter {
  const OpenBookPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.12)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9);

    final pagePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = const Color(0xFF9BC5FF)
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final coverPaint = Paint()
      ..color = const Color(0xFF164FD6)
      ..style = PaintingStyle.fill;

    final leftPage = Path()
      ..moveTo(center, size.height * 0.25)
      ..cubicTo(
        size.width * 0.36,
        size.height * 0.08,
        size.width * 0.13,
        size.height * 0.12,
        size.width * 0.08,
        size.height * 0.20,
      )
      ..lineTo(size.width * 0.08, size.height * 0.77)
      ..cubicTo(
        size.width * 0.28,
        size.height * 0.70,
        size.width * 0.40,
        size.height * 0.76,
        center,
        size.height * 0.88,
      )
      ..close();

    final rightPage = Path()
      ..moveTo(center, size.height * 0.25)
      ..cubicTo(
        size.width * 0.64,
        size.height * 0.08,
        size.width * 0.87,
        size.height * 0.12,
        size.width * 0.92,
        size.height * 0.20,
      )
      ..lineTo(size.width * 0.92, size.height * 0.77)
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.70,
        size.width * 0.60,
        size.height * 0.76,
        center,
        size.height * 0.88,
      )
      ..close();

    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(center, size.height * 0.88),
        width: size.width * 0.88,
        height: size.height * 0.12,
      ),
      shadowPaint,
    );

    // Blue book cover behind the pages.
    final cover = Path()
      ..moveTo(center, size.height * 0.30)
      ..lineTo(size.width * 0.04, size.height * 0.17)
      ..lineTo(size.width * 0.04, size.height * 0.82)
      ..lineTo(center, size.height * 0.94)
      ..lineTo(size.width * 0.96, size.height * 0.82)
      ..lineTo(size.width * 0.96, size.height * 0.17)
      ..close();

    canvas.drawPath(cover, coverPaint);
    canvas.drawPath(leftPage, pagePaint);
    canvas.drawPath(rightPage, pagePaint);

    // Subtle page edges.
    canvas.drawLine(
      Offset(size.width * 0.10, size.height * 0.75),
      Offset(center - 2, size.height * 0.85),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.90, size.height * 0.75),
      Offset(center + 2, size.height * 0.85),
      linePaint,
    );

    // Lines of text on the left page.
    for (int i = 0; i < 4; i++) {
      final y = size.height * (0.34 + i * 0.09);
      canvas.drawLine(
        Offset(size.width * 0.17, y),
        Offset(size.width * 0.39, y + size.height * 0.035),
        linePaint,
      );
    }

    // Lines of text on the right page.
    for (int i = 0; i < 4; i++) {
      final y = size.height * (0.34 + i * 0.09);
      canvas.drawLine(
        Offset(size.width * 0.61, y + size.height * 0.035),
        Offset(size.width * 0.83, y),
        linePaint,
      );
    }

    // Centre fold.
    canvas.drawLine(
      Offset(center, size.height * 0.27),
      Offset(center, size.height * 0.87),
      Paint()
        ..color = const Color(0xFFB8D3FF)
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant OpenBookPainter oldDelegate) => false;
}
