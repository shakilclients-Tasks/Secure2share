import 'package:flutter/material.dart';

import 'models/app_config.dart';
import 'screens/app_lock_screen.dart';
import 'screens/splash_screen.dart';
import 'services/app_config_service.dart';
import 'services/auth_service.dart';
import 'services/drive_service.dart';
import 'services/file_import_service.dart';
import 'services/google_sheets_service.dart';
import 'services/recent_file_store.dart';
import 'widgets/app_logo.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const Drive2ShareBootstrapApp());
}

Future<AppDependencies> _loadDependencies() async {
  final config = await AppConfigService.load();
  final recentFileStore = RecentFileStore();
  await recentFileStore.init();

  final authService = AuthService();
  await authService.initialize(
    clientId: config.google.clientId,
    serverClientId: config.google.serverClientId,
  );
  final googleSheetsService = GoogleSheetsService(
    config: config.googleSheets,
    authService: authService,
    recentFileStore: recentFileStore,
  );

  return AppDependencies(
    config: config,
    authService: authService,
    driveService: DriveService(authService),
    fileImportService: FileImportService(
      config: config,
      recentFileStore: recentFileStore,
    ),
    googleSheetsService: googleSheetsService,
    recentFileStore: recentFileStore,
  );
}

class Drive2ShareBootstrapApp extends StatefulWidget {
  const Drive2ShareBootstrapApp({super.key});

  @override
  State<Drive2ShareBootstrapApp> createState() =>
      _Drive2ShareBootstrapAppState();
}

class _Drive2ShareBootstrapAppState extends State<Drive2ShareBootstrapApp> {
  late Future<AppDependencies> _dependenciesFuture;

  @override
  void initState() {
    super.initState();
    _dependenciesFuture = _loadDependencies();
  }

  void _retry() {
    setState(() => _dependenciesFuture = _loadDependencies());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppDependencies>(
      future: _dependenciesFuture,
      builder: (context, snapshot) {
        final dependencies = snapshot.data;
        if (dependencies != null) {
          return Drive2ShareApp(dependencies: dependencies);
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: const AppConfig().appName,
          themeMode: ThemeMode.system,
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          home: _StartupScreen(error: snapshot.error, onRetry: _retry),
        );
      },
    );
  }
}

class _StartupScreen extends StatelessWidget {
  const _StartupScreen({this.error, required this.onRetry});

  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null;
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
                  const AppLogo(size: 96),
                  const SizedBox(height: 24),
                  Text(
                    const AppConfig().appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    hasError
                        ? 'App startup failed. Please try again.'
                        : const AppConfig().splash.subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  if (hasError) ...<Widget>[
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 18),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ] else
                    const CircularProgressIndicator(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class Drive2ShareApp extends StatelessWidget {
  const Drive2ShareApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return Drive2ShareScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: dependencies.config.appName,
        themeMode: ThemeMode.system,
        theme: _lightTheme(),
        darkTheme: _darkTheme(),
        home: const AppLockScreen(child: SplashScreen()),
      ),
    );
  }
}

ThemeData _lightTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF006D77),
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFFF7FAF9),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colorScheme.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.outlineVariant),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
  );
}

ThemeData _darkTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF65D5DE),
    brightness: Brightness.dark,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: const Color(0xFF071013),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: const Color(0xFF0E171A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFF26343A)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF0E171A),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF2F4047)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF0E171A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
  );
}

class AppDependencies {
  const AppDependencies({
    required this.config,
    required this.authService,
    required this.driveService,
    required this.fileImportService,
    required this.googleSheetsService,
    required this.recentFileStore,
  });

  final AppConfig config;
  final AuthService authService;
  final DriveService driveService;
  final FileImportService fileImportService;
  final GoogleSheetsService googleSheetsService;
  final RecentFileStore recentFileStore;
}

class Drive2ShareScope extends InheritedWidget {
  const Drive2ShareScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<Drive2ShareScope>();
    assert(scope != null, 'Drive2ShareScope was not found in the widget tree.');
    return scope!.dependencies;
  }

  @override
  bool updateShouldNotify(Drive2ShareScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
