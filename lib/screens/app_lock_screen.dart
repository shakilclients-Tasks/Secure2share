import 'package:flutter/material.dart';

import '../services/app_lock_service.dart';
import '../widgets/app_logo.dart';

class AppLockScreen extends StatefulWidget {
  const AppLockScreen({super.key, required this.child});

  final Widget child;

  @override
  State<AppLockScreen> createState() => _AppLockScreenState();
}

class _AppLockScreenState extends State<AppLockScreen>
    with WidgetsBindingObserver {
  final AppLockService _appLockService = AppLockService();
  bool _isUnlocked = false;
  bool _isAuthenticating = false;
  bool _canContinueWithoutLock = false;
  bool _wasBackgrounded = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAuthenticating) return;

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _wasBackgrounded = true;
      if (_isUnlocked && mounted) {
        setState(() => _isUnlocked = false);
      }
      return;
    }

    if (state == AppLifecycleState.resumed &&
        _wasBackgrounded &&
        !_isAuthenticating) {
      _wasBackgrounded = false;
      _authenticate();
    }
  }

  Future<void> _authenticate() async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
      _message = null;
      _canContinueWithoutLock = false;
    });

    final result = await _appLockService.authenticate();
    if (!mounted) return;

    setState(() {
      _isUnlocked = result.isUnlocked;
      _message = result.message;
      _canContinueWithoutLock = result.canContinueWithoutLock;
      _isAuthenticating = false;
      _wasBackgrounded = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isUnlocked) return widget.child;

    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const AppLogo(size: 104),
                  const SizedBox(height: 26),
                  Text(
                    'Unlock Digital Wallet',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Use your phone fingerprint, PIN, password, or pattern.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (_message != null) ...<Widget>[
                    const SizedBox(height: 20),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isAuthenticating ? null : _authenticate,
                      icon: _isAuthenticating
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.lock_open_outlined),
                      label: Text(
                        _isAuthenticating ? 'Checking security' : 'Unlock',
                      ),
                    ),
                  ),
                  if (_canContinueWithoutLock) ...<Widget>[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _isAuthenticating
                          ? null
                          : () => setState(() => _isUnlocked = true),
                      child: const Text('Continue without phone lock'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
