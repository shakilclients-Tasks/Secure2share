import 'dart:async';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;

const List<String> googleApiScopes = <String>[drive.DriveApi.driveFileScope];

class AuthService {
  GoogleSignInAccount? currentUser;
  GoogleSignInClientAuthorization? _authorization;
  String? _serverClientId;

  Future<void> initialize({String? clientId, String? serverClientId}) async {
    _serverClientId = _cleanOAuthClientId(serverClientId);
    final signIn = GoogleSignIn.instance;
    await signIn.initialize(
      clientId: _cleanOAuthClientId(clientId),
      serverClientId: _serverClientId,
    );

    signIn.authenticationEvents
        .listen((GoogleSignInAuthenticationEvent event) {
          switch (event) {
            case GoogleSignInAuthenticationEventSignIn():
              currentUser = event.user;
            case GoogleSignInAuthenticationEventSignOut():
              currentUser = null;
              _authorization = null;
          }
        })
        .onError((Object error) {
          debugPrint('Google sign-in event error: $error');
        });

    final lightweight = signIn.attemptLightweightAuthentication();
    if (lightweight != null) {
      currentUser = await lightweight;
      if (currentUser != null) {
        _authorization = await currentUser!.authorizationClient
            .authorizationForScopes(googleApiScopes);
      }
    }
  }

  bool get isSignedIn => currentUser != null;

  Future<GoogleSignInAccount> signIn() async {
    if (_serverClientId == null) {
      throw StateError(
        'Missing Google serverClientId. Add your Web OAuth client ID in assets/app_config.json.',
      );
    }

    try {
      await GoogleSignIn.instance.disconnect();
    } catch (_) {
      await GoogleSignIn.instance.signOut();
    }
    _authorization = null;
    final user = await GoogleSignIn.instance.authenticate(
      scopeHint: googleApiScopes,
    );
    currentUser = user;
    _authorization = await user.authorizationClient.authorizeScopes(
      googleApiScopes,
    );
    return user;
  }

  Future<void> signOut() async {
    await GoogleSignIn.instance.disconnect();
    currentUser = null;
    _authorization = null;
  }

  Future<auth.AuthClient> authClient() async {
    final user = currentUser;
    if (user == null) {
      throw StateError('Please sign in first.');
    }

    _authorization ??= await _authorize(user, prompt: true);
    final authorization = _authorization;
    if (authorization == null) {
      throw StateError('Google Sheets and Drive permission was not granted.');
    }

    return authorization.authClient(scopes: googleApiScopes);
  }

  Future<void> reauthorize() async {
    final user = currentUser;
    if (user == null) {
      await signIn();
      return;
    }

    final staleAuthorization = _authorization;
    if (staleAuthorization != null) {
      try {
        await user.authorizationClient.clearAuthorizationToken(
          accessToken: staleAuthorization.accessToken,
        );
      } catch (error) {
        debugPrint('Unable to clear stale Google token: $error');
      }
    }

    _authorization = await user.authorizationClient.authorizeScopes(
      googleApiScopes,
    );
  }

  static bool isInsufficientScope(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('insufficient_scope') ||
        text.contains('insufficient authentication scopes') ||
        text.contains('request had insufficient authentication scopes');
  }

  static String friendlyGoogleError(Object error, {required String service}) {
    if (isInsufficientScope(error)) {
      return '$service permission is missing. Reconnect Google and approve Drive access.';
    }

    final text = error.toString();
    if (text.contains('access_denied') || text.contains('Access denied')) {
      return '$service access was denied. Approve the permission and try again.';
    }
    return '$service operation failed.';
  }

  Future<GoogleSignInClientAuthorization?> _authorize(
    GoogleSignInAccount user, {
    required bool prompt,
  }) async {
    final existing = await user.authorizationClient.authorizationForScopes(
      googleApiScopes,
    );
    if (existing != null || !prompt) return existing;
    return user.authorizationClient.authorizeScopes(googleApiScopes);
  }

  String? _cleanOAuthClientId(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null ||
        trimmed.isEmpty ||
        trimmed.startsWith('YOUR_') ||
        trimmed.contains('PASTE_')) {
      return null;
    }
    return trimmed;
  }
}
