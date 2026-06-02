# Drive2Share Flutter

Cross-platform Flutter version of Drive2Share for Android and iOS.

## Fix Google Sign-In setup

If Android shows `serverClientId must be provided on Android`, the Google OAuth
client ID is missing.

1. Open Google Cloud Console and select your project.
2. Enable **Google Drive API**.
3. In **OAuth consent screen > Data Access**, add this scope:

```text
https://www.googleapis.com/auth/drive
```

This full Drive scope is required because Drive2Share can browse folders,
import folder contents, create folders, and move folders to trash.
4. Go to **APIs & Services > Credentials**.
5. Create an **OAuth client ID** with application type **Android**.
   - Package name: `com.drive2share.app`
   - SHA-1: run this command from the Flutter project:

```powershell
cd android
.\gradlew.bat signingReport
```

6. Create another **OAuth client ID** with application type **Web application**.
7. Copy the **Web application** client ID.
8. Paste it into `assets/app_config.json`:

```json
"google": {
  "clientId": "",
  "serverClientId": "PASTE_WEB_CLIENT_ID_HERE.apps.googleusercontent.com"
}
```

9. Rebuild and reinstall:

```powershell
flutter clean
flutter pub get
flutter build apk --debug
```

## Google Drive folder setting

The Drive picker only shows files from one configured Drive folder. Change the
folder name in `assets/app_config.json`:

```json
"driveFolder": {
  "name": "Drive2Share",
  "parentId": "root"
}
```

When the user opens the Drive picker, the app searches for this folder. If it is
missing, the app asks before creating it. Because folder creation writes to
Drive, the app requests both Drive read-only and Drive file permissions.

## Firebase setup for the new file method

The app is now local-first: it opens without Google login, imports files from
the phone, stores imported copies in app storage, lets users edit text files,
and shares files to supported messenger apps.

Use Firebase like this:

- Cloud Storage: upload the actual files.
- Cloud Firestore: store file metadata such as name, MIME type, storage path,
  size, and updated time.

Setup steps:

1. Create a Firebase project.
2. Install Firebase CLI and sign in:

```powershell
npm install -g firebase-tools
firebase login
```

3. Install FlutterFire CLI:

```powershell
dart pub global activate flutterfire_cli
```

4. From this Flutter project folder, configure Firebase:

```powershell
cd C:\Users\shaki\OneDrive\Documents\Drive2share\drive2share_flutter
flutterfire configure
```

5. Add the Firebase packages:

```powershell
flutter pub add firebase_core cloud_firestore firebase_storage firebase_auth
```

6. Enable these Firebase products:

- Authentication: Anonymous or Email/Password is easiest. Google login is not
  required for this new local/Firebase method.
- Cloud Firestore
- Cloud Storage

7. Recommended Firestore document shape:

```json
{
  "name": "notes.txt",
  "mimeType": "text/plain",
  "storagePath": "users/{uid}/files/notes.txt",
  "sizeBytes": 1200,
  "updatedAt": "serverTimestamp"
}
```

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
