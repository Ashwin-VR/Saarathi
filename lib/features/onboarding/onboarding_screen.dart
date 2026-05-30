import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:accident_app/core/router/app_router.dart';

const _kOnboardingKey = 'onboarding_done_v1';
const _kDpdpaKey = 'dpdpa_consent_v1';

Future<bool> isOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  return (prefs.getBool(_kOnboardingKey) ?? false) &&
      (prefs.getBool(_kDpdpaKey) ?? false);
}

Future<void> markOnboardingDone() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingKey, true);
  await prefs.setBool(_kDpdpaKey, true);
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  // Page 0 is DPDPA consent, pages 1-3 are feature highlights
  static const _featurePages = [
    _OnboardingPage(
      icon: Icons.sos_rounded,
      color: Color(0xFFD32F2F),
      title: 'One-tap Emergency Dial',
      body:
          'Three emergency numbers are always visible at the top — Ambulance 108, '
          'Police 100, and Emergency 112. One tap dials instantly. '
          'No menus, no delay.',
    ),
    _OnboardingPage(
      icon: Icons.smart_toy_outlined,
      color: Color(0xFF1565C0),
      title: 'AI Emergency Assistant',
      body:
          'Ask the AI co-pilot about first aid, nearest hospitals, legal rights as a '
          'bystander, and how to describe your location. Works offline too — '
          'with pre-loaded quick answers.',
    ),
    _OnboardingPage(
      icon: Icons.location_on_outlined,
      color: Color(0xFF2E7D32),
      title: 'Always-on POI Map',
      body:
          'Hospitals, police stations, and pharmacies are shown on the map in real-time. '
          'Bundled offline data means the map works without internet. '
          'Your location updates automatically when GPS is restored.',
    ),
  ];

  bool get _isOnConsentPage => _page == 0;
  bool get _isOnLastFeaturePage => _page == _featurePages.length; // page index 3
  // Total pages: 1 consent + 3 feature = 4
  int get _totalPages => _featurePages.length + 1;

  void _next() {
    if (_page < _totalPages - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await markOnboardingDone();
    if (mounted) context.go(AppRoutes.home);
  }

  Future<void> _exit() async {
    // User declined DPDPA — exit app
    // On Android we can pop back (since MainActivity was the root)
    // On other platforms just go to a minimal error view.
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Privacy required'),
          content: const Text(
              'RoadSoS needs location access to show emergency services near you. '
              'Without consent, the app cannot function. '
              'Please close the app or re-open to agree.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Back'),
            ),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _totalPages - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Skip button (only on feature pages, not consent)
            if (!_isOnConsentPage)
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Skip'),
                ),
              )
            else
              const SizedBox(height: 40),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _totalPages,
                physics: _isOnConsentPage
                    ? const NeverScrollableScrollPhysics()
                    : null,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (_, i) {
                  if (i == 0) return const _ConsentPage();
                  return _featurePages[i - 1];
                },
              ),
            ),

            // Dot indicator
            if (!_isOnConsentPage)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_featurePages.length, (i) {
                    final active = _page == i + 1;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 20 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade400,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    );
                  }),
                ),
              )
            else
              const SizedBox(height: 16),

            // Action buttons
            if (_isOnConsentPage)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1565C0),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _next,
                        child: const Text(
                          'Agree and continue',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _exit,
                      child: const Text('Exit app',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    onPressed: _next,
                    child: Text(
                      isLast ? 'Get Started' : 'Next',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// DPDPA consent page
class _ConsentPage extends StatelessWidget {
  const _ConsentPage();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1565C0).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.privacy_tip_outlined,
              size: 52,
              color: Color(0xFF1565C0),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Before you start',
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            'Under the Digital Personal Data Protection Act 2023 (DPDPA), '
            'we must inform you what data we collect and why.',
            style: TextStyle(
              fontSize: 14,
              height: 1.6,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          _ConsentItem(
            icon: Icons.location_on_outlined,
            title: 'Location',
            desc: 'Used to show nearby hospitals, police stations, and pharmacies. '
                'Included in SOS alerts sent to your contacts.',
          ),
          _ConsentItem(
            icon: Icons.sms_outlined,
            title: 'SMS',
            desc: 'Sent to your emergency contacts when you trigger SOS. '
                'Never sent without your action or crash detection confirmation.',
          ),
          _ConsentItem(
            icon: Icons.phone_android_outlined,
            title: 'Health profile',
            desc: 'Optional Victim ID (blood group, conditions) is stored '
                'ONLY on this device. It is never uploaded.',
          ),
          const SizedBox(height: 16),
          Text(
            'You can delete all your data at any time from Settings → Privacy.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String desc;

  const _ConsentItem({
    required this.icon,
    required this.title,
    required this.desc,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: const Color(0xFF1565C0)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade400, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Feature highlight page
class _OnboardingPage extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  const _OnboardingPage({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 52, color: color),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            body,
            style: const TextStyle(fontSize: 15, height: 1.6),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
