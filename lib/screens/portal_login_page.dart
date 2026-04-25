import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum PortalType { caregiver, patient }

class PortalLoginPage extends StatefulWidget {
  const PortalLoginPage({
    super.key,
    required this.portalType,
  });

  final PortalType portalType;

  @override
  State<PortalLoginPage> createState() => _PortalLoginPageState();
}

class _PortalLoginPageState extends State<PortalLoginPage>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _title => widget.portalType == PortalType.caregiver
      ? 'Caregiver Login'
      : 'Patient Login';

  String get _subtitle => widget.portalType == PortalType.caregiver
      ? 'Get missed-dose alerts and support tools.'
      : 'Pill Tracker with reminders you can’t ignore.';

  Color get _accent => widget.portalType == PortalType.caregiver
      ? AppColors.deepBlue
      : AppColors.deepYellow;

  Color get _soft => widget.portalType == PortalType.caregiver
      ? AppColors.pastelBlue
      : AppColors.pastelYellow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _soft.withOpacity(0.35),
              Colors.white,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
                const SizedBox(height: 12),
                FadeTransition(
                  opacity: _opacity,
                  child: SlideTransition(
                    position: _slide,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _title,
                          style: theme.textTheme.displaySmall?.copyWith(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.darkText,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _subtitle,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: AppColors.mediumText,
                            fontWeight: FontWeight.w500,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _FeatureChips(accent: _accent),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: FadeTransition(
                    opacity: _opacity,
                    child: SlideTransition(
                      position: _slide,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _accent.withOpacity(0.18),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _accent.withOpacity(0.10),
                              blurRadius: 28,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              decoration: InputDecoration(
                                labelText: 'Email',
                                prefixIcon: const Icon(Icons.email_outlined),
                                filled: true,
                                fillColor: _soft.withOpacity(0.18),
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _passwordController,
                              obscureText: true,
                              textInputAction: TextInputAction.done,
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(Icons.lock_outline_rounded),
                                filled: true,
                                fillColor: _soft.withOpacity(0.18),
                              ),
                            ),
                            const SizedBox(height: 18),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: _accent,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Login flow coming next (step 2).',
                                    ),
                                    backgroundColor: _accent,
                                  ),
                                );
                              },
                              child: const Text(
                                'Continue',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Account creation coming next (step 3).',
                                    ),
                                    backgroundColor: _accent,
                                  ),
                                );
                              },
                              child: Text(
                                'Create an account',
                                style: TextStyle(
                                  color: _accent,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              widget.portalType == PortalType.patient
                                  ? 'Tip: Reminders will require confirmation before they can be dismissed.'
                                  : 'Tip: You’ll get notified if a dose is missed or overdue.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColors.mediumText,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureChips extends StatelessWidget {
  const _FeatureChips({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    Widget chip(String text, IconData icon) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.75),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: accent.withOpacity(0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: accent),
            const SizedBox(width: 8),
            Text(
              text,
              style: const TextStyle(
                color: AppColors.darkText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        chip('Smart reminders', Icons.schedule_rounded),
        chip('Missed-dose alerts', Icons.notification_important_rounded),
        chip('Multi-med (up to 10)', Icons.medication_liquid_rounded),
      ],
    );
  }
}

