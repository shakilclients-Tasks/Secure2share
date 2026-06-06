import 'package:local_auth/local_auth.dart';

class AppLockService {
  AppLockService({LocalAuthentication? auth})
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<AppLockResult> authenticate() async {
    try {
      final isSupported = await _auth.isDeviceSupported();
      if (!isSupported) {
        return const AppLockResult(
          isUnlocked: false,
          canContinueWithoutLock: true,
          message: 'No phone lock is active on this device.',
        );
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: 'Unlock Digital Wallet to view your secure details',
        biometricOnly: false,
        sensitiveTransaction: true,
        persistAcrossBackgrounding: true,
      );

      return AppLockResult(
        isUnlocked: didAuthenticate,
        canContinueWithoutLock: false,
        message: didAuthenticate ? null : 'Authentication was cancelled.',
      );
    } on LocalAuthException catch (error) {
      return AppLockResult(
        isUnlocked: false,
        canContinueWithoutLock: _canContinueWithoutLock(error.code),
        message: _messageFor(error),
      );
    } catch (error) {
      return AppLockResult(
        isUnlocked: false,
        canContinueWithoutLock: false,
        message: 'Unable to unlock Digital Wallet: $error',
      );
    }
  }

  bool _canContinueWithoutLock(LocalAuthExceptionCode code) {
    return code == LocalAuthExceptionCode.noBiometricHardware ||
        code == LocalAuthExceptionCode.noBiometricsEnrolled ||
        code == LocalAuthExceptionCode.noCredentialsSet;
  }

  String _messageFor(LocalAuthException error) {
    return switch (error.code) {
      LocalAuthExceptionCode.authInProgress =>
        'Authentication is already running.',
      LocalAuthExceptionCode.uiUnavailable =>
        'Device unlock screen is not available right now.',
      LocalAuthExceptionCode.noBiometricHardware =>
        'This device does not support biometric authentication.',
      LocalAuthExceptionCode.noBiometricsEnrolled =>
        'No fingerprint or face unlock is enrolled on this device.',
      LocalAuthExceptionCode.noCredentialsSet =>
        'Set a phone PIN, password, or pattern to protect Digital Wallet.',
      LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
        'Biometric hardware is temporarily unavailable.',
      LocalAuthExceptionCode.temporaryLockout =>
        'Authentication is temporarily locked. Try again shortly.',
      LocalAuthExceptionCode.biometricLockout =>
        'Biometric unlock is locked. Use your phone PIN, password, or pattern.',
      LocalAuthExceptionCode.userCanceled => 'Authentication was cancelled.',
      LocalAuthExceptionCode.timeout => 'Authentication timed out.',
      LocalAuthExceptionCode.systemCanceled =>
        'Authentication was cancelled by the system.',
      LocalAuthExceptionCode.userRequestedFallback =>
        'Use your phone PIN, password, or pattern to unlock.',
      LocalAuthExceptionCode.deviceError =>
        error.description ?? 'Device authentication failed.',
      LocalAuthExceptionCode.unknownError =>
        error.description ?? 'Unable to authenticate.',
    };
  }
}

class AppLockResult {
  const AppLockResult({
    required this.isUnlocked,
    required this.canContinueWithoutLock,
    this.message,
  });

  final bool isUnlocked;
  final bool canContinueWithoutLock;
  final String? message;
}
