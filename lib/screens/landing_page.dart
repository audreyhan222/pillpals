import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _cardsController;
  late Animation<double> _logoScale;
  late Animation<Offset> _logoPosition;
  late Animation<double> _cardsOpacity;

  @override
  void initState() {
    super.initState();

    // Logo animation controller
    _logoController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Cards animation controller
    _cardsController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    // Logo scale animation
    _logoScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );

    // Logo position animation (moves down from center)
    _logoPosition = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: const Offset(0, -0.15),
    ).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeInOutCubic),
    );

    // Cards fade-in animation
    _cardsOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _cardsController, curve: Curves.easeInOutCubic),
    );

    // Start animations sequentially
    _logoController.forward().then((_) {
      _cardsController.forward();
    });
  }

  @override
  void dispose() {
    _logoController.dispose();
    _cardsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.pastelBlue.withOpacity(0.3),
              AppColors.pastelYellow.withOpacity(0.3),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo section with animation
              Expanded(
                flex: 1,
                child: SlideTransition(
                  position: _logoPosition,
                  child: ScaleTransition(
                    scale: _logoScale,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                AppColors.deepYellow,
                                AppColors.softYellow,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.deepYellow.withOpacity(0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              '💊',
                              style: Theme.of(context)
                                  .textTheme
                                  .displayLarge
                                  ?.copyWith(fontSize: 60),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'PillPal',
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                color: AppColors.darkText,
                                fontWeight: FontWeight.bold,
                                fontSize: 32,
                                letterSpacing: 1.2,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Your Medication Companion',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                color: AppColors.mediumText,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              // Login options section with animation
              FadeTransition(
                opacity: _cardsOpacity,
                child: Padding(
                  padding:
                      const EdgeInsets.only(left: 24, right: 24, bottom: 40),
                  child: Column(
                    children: [
                      Text(
                        'How would you like to continue?',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: AppColors.darkText,
                              fontWeight: FontWeight.w600,
                              fontSize: 18,
                            ),
                      ),
                      const SizedBox(height: 24),
                      // Caregiver Portal Card
                      _buildPortalCard(
                        context,
                        icon: '👨‍⚕️',
                        title: 'Caregiver Portal',
                        subtitle: 'Monitor and manage care',
                        bgColor: AppColors.softBlue,
                        accentColor: AppColors.deepBlue,
                        onTap: () {
                          _navigateTo(context, 'caregiver');
                        },
                      ),
                      const SizedBox(height: 16),
                      // User/Elderly Portal Card
                      _buildPortalCard(
                        context,
                        icon: '👴',
                        title: 'Patient Portal',
                        subtitle: 'Track your medications',
                        bgColor: AppColors.softYellow,
                        accentColor: AppColors.deepYellow,
                        onTap: () {
                          _navigateTo(context, 'patient');
                        },
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

  Widget _buildPortalCard(
    BuildContext context, {
    required String icon,
    required String title,
    required String subtitle,
    required Color bgColor,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: accentColor.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: accentColor.withOpacity(0.15),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accentColor.withOpacity(0.15),
                ),
                child: Center(
                  child: Text(
                    icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: AppColors.darkText,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.mediumText,
                            fontSize: 14,
                          ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                color: accentColor.withOpacity(0.2),
                ),
                child: Icon(
                  Icons.arrow_forward_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String portal) {
    // Placeholder for navigation logic
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Navigating to $portal portal...'),
        backgroundColor: AppColors.deepBlue,
      ),
    );
  }
}
