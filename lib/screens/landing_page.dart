import 'package:flutter/material.dart';
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

  // Logo animates from center to upper position
  late Animation<Alignment> _logoAlignment;
  late Animation<double> _logoScale;

  // Content fades + slides in
  late Animation<double> _contentOpacity;
  late Animation<Offset> _contentSlide;

  @override
  void initState() {
    super.initState();

    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _contentController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Logo starts centered, moves to top area
    _logoAlignment = AlignmentTween(
      begin: Alignment.center,
      end: Alignment.topCenter,
    ).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOutCubic),
    );

    _logoScale = Tween<double>(begin: 1.1, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOutCubic),
    );

    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeIn),
    );

    _contentSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _contentController, curve: Curves.easeOutCubic),
    );

    // Wait 1s with logo centered, then animate up, then fade in content
    Future.delayed(const Duration(milliseconds: 900), () {
      _logoController.forward().then((_) {
        _contentController.forward();
      });
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _contentController.dispose();
    super.dispose();
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
            stops: [0.0, 0.4, 1.0],
            colors: [
              Color(0xFFBDD8F5), // soft blue top-left
              Color(0xFFE8EEF8), // pale mid
              Color(0xFFFAEFA0), // warm yellow bottom-right
            ],
          ),
        ),
        child: SafeArea(
          child: AnimatedBuilder(
            animation: Listenable.merge([_logoController, _contentController]),
            builder: (context, child) {
              return Stack(
                children: [
                  // Logo — animates from center to upper portion
                  Positioned.fill(
                    child: Align(
                      alignment: _logoAlignment.value,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: _logoController.value * (size.height * 0.06),
                        ),
                        child: ScaleTransition(
                          scale: _logoScale,
                          child: _buildLogo(context),
                        ),
                      ),
                    ),
                  ),

                  // Content: subtitle + cards, fades in after logo moves up
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
      ),
    );
  }

  Widget _buildLogo(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rounded square with gradient
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF9FC8EE), // soft blue
                Color(0xFFE8D88A), // warm yellow
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withValues(alpha: 0.15),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.favorite,
            color: Colors.white,
            size: 52,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // PillPal two-tone title
          RichText(
            text: const TextSpan(
              children: [
                TextSpan(
                  text: 'Pill',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF5B9BD5),
                    letterSpacing: 0.5,
                  ),
                ),
                TextSpan(
                  text: 'Pal',
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE5A800),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your medication companion',
            style: TextStyle(
              fontSize: 16,
              color: Color(0xFF8A94A6),
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 40),

          // Patient card
          _buildPortalCard(
            context,
            icon: Icons.favorite,
            iconBgColor: const Color(0xFFF5B731),
            label: 'I Take Medicine',
            onTap: () {
              context.go('/login?role=elderly');
            },
          ),
          const SizedBox(height: 16),

          // Caregiver card
          _buildPortalCard(
            context,
            icon: Icons.group,
            iconBgColor: const Color(0xFF9FC8EE),
            label: "I'm a Caregiver",
            onTap: () {
              context.go('/login?role=caregiver');
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPortalCard(
    BuildContext context, {
    required IconData icon,
    required Color iconBgColor,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        splashColor: iconBgColor.withValues(alpha: 0.15),
        highlightColor: iconBgColor.withValues(alpha: 0.08),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.9),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: Colors.white.withValues(alpha: 0.8),
                blurRadius: 0,
                offset: const Offset(0, -1),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: iconBgColor.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2D4A),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
