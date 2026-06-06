import 'package:flutter/material.dart';

import '../main.dart';
import '../widgets/app_logo.dart';
import 'country_setup_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';

class IntroScreen extends StatefulWidget {
  const IntroScreen({super.key});

  @override
  State<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends State<IntroScreen> {
  final PageController _controller = PageController();
  int _pageIndex = 0;
  bool _isFinishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _next() async {
    if (_pageIndex < _pages.length - 1) {
      await _controller.nextPage(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _isFinishing = true);
    final dependencies = Drive2ShareScope.of(context);
    await dependencies.userProfileStore.setIntroComplete();

    Widget nextScreen = const LoginScreen();
    if (dependencies.authService.isSignedIn) {
      final isSetupComplete = await dependencies.userProfileStore
          .isCountrySetupComplete();
      nextScreen = isSetupComplete
          ? const HomeScreen()
          : const CountrySetupScreen();
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute<void>(builder: (_) => nextScreen));
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _pageIndex == _pages.length - 1;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                itemBuilder: (context, index) =>
                    _IntroPage(data: _pages[index]),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Row(
                children: <Widget>[
                  Row(
                    children: List<Widget>.generate(
                      _pages.length,
                      (index) => AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: index == _pageIndex ? 22 : 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: index == _pageIndex
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _isFinishing ? null : _next,
                    icon: _isFinishing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isLast ? Icons.login_outlined : Icons.arrow_forward,
                          ),
                    label: Text(isLast ? 'Continue' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IntroPage extends StatelessWidget {
  const _IntroPage({required this.data});

  final _IntroPageData data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const AppLogo(size: 104),
          const SizedBox(height: 34),
          Text(
            data.title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          Text(
            data.description,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _IntroPageData {
  const _IntroPageData({required this.title, required this.description});

  final String title;
  final String description;
}

const List<_IntroPageData> _pages = <_IntroPageData>[
  _IntroPageData(
    title: 'Secure details for every country',
    description:
        'Choose your country and keep only the IDs, cards, permits, and documents that matter to you.',
  ),
  _IntroPageData(
    title: 'Save privately, share safely',
    description:
        'Your selected sections stay organized in the app, sync to your Google Sheets, and can be shared when needed.',
  ),
];
