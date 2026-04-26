import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _contentController;
  late AnimationController _floatController;
  late AnimationController _shimmerController;

  late Animation<Alignment> _logoAlignment;
  late Animation<double> _logoScale;
  late Animation<double> _contentOpacity;
  late Animation<Offset> _contentSlide;
  late Animation<double> _floatY;
  late Animation<double> _shimmer;

  // Per-card press state
  final List<bool> _cardPressed = [false, false];
  final List<AnimationController> _cardControllers = [];

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1100),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );

    // Gentle floating loop for the logo
    _floatController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    )..repeat(reverse: true);

    // Shimmer loop for gradient text
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    _logoAlignment = AlignmentTween(
      begin: Alignment.center,
      end: const Alignment(0, -0.62),
    ).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOutCubic),
    );

    _logoScale = Tween<double>(begin: 1.15, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOutCubic),
    );

    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeIn),
    );

    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );

    _floatY = Tween<double>(begin: -6.0, end: 6.0).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(_shimmerController);

    // Card press controllers
    for (int i = 0; i < 2; i++) {
      _cardControllers.add(
        AnimationController(
          duration: const Duration(milliseconds: 120),
          reverseDuration: const Duration(milliseconds: 300),
          vsync: this,
        ),
      );
    }

    Future.delayed(const Duration(milliseconds: 800), () {
      if (mounted) {
        _logoController.forward().then((_) {
          if (mounted) _contentController.forward();
        });
      }
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _contentController.dispose();
    _floatController.dispose();
    _shimmerController.dispose();
    for (final c in _cardControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _onCardTapDown(int index) {
    HapticFeedback.lightImpact();
    setState(() => _cardPressed[index] = true);
    _cardControllers[index].forward();
  }

  void _onCardTapUp(int index, VoidCallback onTap) {
    setState(() => _cardPressed[index] = false);
    _cardControllers[index].reverse().then((_) => onTap());
  }

  void _onCardTapCancel(int index) {
    setState(() => _cardPressed[index] = false);
    _cardControllers[index].reverse();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0.0, 0.35, 0.7, 1.0],
            colors: [
              Color(0xFFC2DEFF), // cool periwinkle blue
              Color(0xFFE8EFFE), // pale lavender mid
              Color(0xFFFFF3C4), // warm cream
              Color(0xFFFFE07A), // golden yellow
            ],
          ),
        ),
        child: Stack(
          children: [
            // Decorative blurred orbs for depth
            Positioned(
              top: -60,
              right: -60,
              child: _buildOrb(180, const Color(0xFF7DB8F7), 0.25),
            ),
            Positioned(
              bottom: 80,
              left: -40,
              child: _buildOrb(140, const Color(0xFFFFD166), 0.3),
            ),
            Positioned(
              top: size.height * 0.4,
              right: -30,
              child: _buildOrb(100, const Color(0xFFB8D8FF), 0.2),
            ),

            SafeArea(
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _logoController,
                  _contentController,
                  _floatController,
                  _shimmerController,
                ]),
                builder: (context, _) {
                  return Stack(
                    children: [
                      // Floating logo
                      Positioned.fill(
                        child: Align(
                          alignment: _logoAlignment.value,
                          child: Transform.translate(
                            offset: Offset(0, _floatY.value),
                            child: ScaleTransition(
                              scale: _logoScale,
                              child: _buildLogo(),
                            ),
                          ),
                        ),
                      ),

                      // Content
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: FadeTransition(
                          opacity: _contentOpacity,
                          child: SlideTransition(
                            position: _contentSlide,
                            child: _buildContent(context),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrb(double size, Color color, double opacity) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: opacity),
      ),
    );
  }

  Widget _buildLogo() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Logo icon with layered glow
        Stack(
          alignment: Alignment.center,
          children: [
            // Outer glow ring
            Container(
              width: 130,
              height: 130,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(36),
                gradient: RadialGradient(
                  colors: [
                    const Color(0xFF7DB8F7).withValues(alpha: 0.3),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            // Main icon container
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF9FCBF5),
                    Color(0xFFB8D8F8),
                    Color(0xFFEDD87A),
                  ],
                  stops: [0.0, 0.5, 1.0],
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7DB8F7).withValues(alpha: 0.4),
                    blurRadius: 30,
                    offset: const Offset(-4, -4),
                  ),
                  BoxShadow(
                    color: const Color(0xFFE5A800).withValues(alpha: 0.3),
                    blurRadius: 30,
                    offset: const Offset(4, 8),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Pill buddy
                  Container(
                    width: 70,
                    height: 44,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: Colors.white.withValues(alpha: 0.92),
                      border: Border.all(
                        color: const Color(0xFF1E2D4A).withValues(alpha: 0.12),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Capsule split
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            width: 35,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC2DEFF).withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            width: 35,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFE07A).withValues(alpha: 0.95),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        // Split seam
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 2,
                            height: 40,
                            color: const Color(0xFF1E2D4A).withValues(alpha: 0.08),
                          ),
                        ),
                        // Face
                        Align(
                          alignment: const Alignment(0, 0.2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2D4A).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E2D4A).withValues(alpha: 0.85),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Align(
                          alignment: const Alignment(0, 0.55),
                          child: Container(
                            width: 14,
                            height: 8,
                            decoration: BoxDecoration(
                              border: Border(
                                bottom: BorderSide(
                                  color: const Color(0xFF1E2D4A).withValues(alpha: 0.55),
                                  width: 2,
                                ),
                              ),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Heart badge
                  Positioned(
                    right: 18,
                    top: 22,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5A7A).withValues(alpha: 0.95),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5A7A).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.favorite_rounded,
                        size: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 52),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shimmer gradient "PillPal" title
          ShaderMask(
            shaderCallback: (bounds) {
              final shimmerVal = _shimmer.value;
              return LinearGradient(
                begin: Alignment(shimmerVal - 1, 0),
                end: Alignment(shimmerVal + 1, 0),
                colors: const [
                  Color(0xFF5B9BD5),
                  Color(0xFF7DB8F7),
                  Color(0xFFE5A800),
                  Color(0xFFF5C842),
                  Color(0xFFE5A800),
                  Color(0xFF7DB8F7),
                  Color(0xFF5B9BD5),
                ],
                stops: const [0.0, 0.15, 0.4, 0.5, 0.6, 0.85, 1.0],
              ).createShader(bounds);
            },
            child: const Text(
              'PillPal',
              style: TextStyle(
                fontSize: 44,
                fontWeight: FontWeight.w800,
                color: Colors.white, // masked by shader
                letterSpacing: 1.0,
              ),
            ),
          ),

          const SizedBox(height: 6),

          // Subtitle with slight letterSpacing elegance
          const Text(
            'Your medication companion',
            style: TextStyle(
              fontSize: 15,
              color: Color(0xFF8A94A6),
              fontWeight: FontWeight.w400,
              letterSpacing: 0.4,
            ),
          ),

          const SizedBox(height: 36),

          // Cards
          _buildAnimatedCard(
            index: 0,
            icon: Icons.favorite_rounded,
            iconGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFD166), Color(0xFFE5A800)],
            ),
            iconShadowColor: const Color(0xFFE5A800),
            label: 'I Take Medicine',
            sublabel: 'Track & confirm your doses',
            onTap: () {
              context.go('/login/elderly');
            },
          ),

          const SizedBox(height: 14),

          _buildAnimatedCard(
            index: 1,
            icon: Icons.people_rounded,
            iconGradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF7DB8F7), Color(0xFF4A90D9)],
            ),
            iconShadowColor: const Color(0xFF4A90D9),
            label: "I'm a Caregiver",
            sublabel: 'Monitor & get missed-dose alerts',
            onTap: () {
              context.go('/login/caregiver');
            },
          ),

          const SizedBox(height: 20),

          // Subtle footer tag
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 28,
                height: 1,
                color: const Color(0xFFB0BAC8),
              ),
              const SizedBox(width: 10),
              const Text(
                'Secure · Private · Caring',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFFB0BAC8),
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 28,
                height: 1,
                color: const Color(0xFFB0BAC8),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Tiny dev entry point (debug builds / internal use).
          TextButton(
            onPressed: () => context.go('/dev'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8A94A6),
              textStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('Dev'),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedCard({
    required int index,
    required IconData icon,
    required LinearGradient iconGradient,
    required Color iconShadowColor,
    required String label,
    required String sublabel,
    required VoidCallback onTap,
  }) {
    return AnimatedBuilder(
      animation: _cardControllers[index],
      builder: (context, child) {
        final pressVal = _cardControllers[index].value;
        final scale = 1.0 - (pressVal * 0.04);
        final shadowOpacity = 0.12 - (pressVal * 0.08);
        final shadowBlur = 24.0 - (pressVal * 16.0);
        final shadowOffset = 8.0 - (pressVal * 6.0);

        return Transform.scale(
          scale: scale,
          child: GestureDetector(
            onTapDown: (_) => _onCardTapDown(index),
            onTapUp: (_) => _onCardTapUp(index, onTap),
            onTapCancel: () => _onCardTapCancel(index),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: BoxDecoration(
                // Glassmorphism card
                color: Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.9),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: shadowOpacity),
                    blurRadius: shadowBlur,
                    offset: Offset(0, shadowOffset),
                  ),
                  BoxShadow(
                    color: iconShadowColor.withValues(alpha: 0.08 - pressVal * 0.06),
                    blurRadius: shadowBlur * 1.5,
                    offset: Offset(0, shadowOffset),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Gradient icon box
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: iconGradient,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: iconShadowColor.withValues(alpha: 0.4),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Icon(icon, color: Colors.white, size: 32),
                  ),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E2D4A),
                            letterSpacing: 0.1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          sublabel,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF8A94A6),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Arrow badge
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: iconShadowColor.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      Icons.arrow_forward_ios_rounded,
                      color: iconShadowColor,
                      size: 15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
