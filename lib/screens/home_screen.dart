import 'package:flutter/material.dart';

import '../main.dart';
import '../models/secure_detail.dart';
import '../services/auth_service.dart';
import '../services/theme_controller.dart';
import 'country_setup_screen.dart';
import 'recent_files_screen.dart';
import 'secure_detail_category_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Future<void> _openMyFiles() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RecentFilesScreen()));
  }

  Future<void> _openCategory(SecureDetailType type) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SecureDetailCategoryScreen(type: type),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dependencies = Drive2ShareScope.of(context);
    final config = dependencies.config.home;
    final greeting = _homeGreeting(dependencies);

    return Scaffold(
      drawer: const _HomeMenuDrawer(),
      appBar: AppBar(title: Text(dependencies.config.appName)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
          children: <Widget>[
            Text(
              greeting,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
            ),
            const SizedBox(height: 22),
            FutureBuilder<List<SecureDetailType>>(
              future: dependencies.userProfileStore.selectedTypes(),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final types = snapshot.data ?? const <SecureDetailType>[];
                if (types.isEmpty) {
                  return _SetupMissingPanel(
                    onSetup: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                        builder: (_) => const CountrySetupScreen(),
                      ),
                    ),
                  );
                }
                return _SecureCategoryPanel(
                  types: types,
                  onOpenCategory: _openCategory,
                );
              },
            ),
            const SizedBox(height: 18),
            _DashboardButton(
              icon: Icons.history_outlined,
              label: config.actions['recent']?.text ?? 'Recent',
              onPressed: _openMyFiles,
            ),
          ],
        ),
      ),
    );
  }

  String _homeGreeting(AppDependencies dependencies) {
    final user = dependencies.authService.currentUser;
    final displayName = user?.displayName?.trim();
    final email = user?.email.trim();
    final accountName = displayName != null && displayName.isNotEmpty
        ? displayName
        : email != null && email.isNotEmpty
        ? email
        : 'User';
    return 'Hi $accountName';
  }
}

class _HomeMenuDrawer extends StatelessWidget {
  const _HomeMenuDrawer();

  @override
  Widget build(BuildContext context) {
    final dependencies = Drive2ShareScope.of(context);

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: <Widget>[
            Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 22,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  foregroundColor: Theme.of(
                    context,
                  ).colorScheme.onPrimaryContainer,
                  child: const Icon(Icons.shield_outlined),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    dependencies.config.appName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _DrawerMenuTile(
              icon: Icons.health_and_safety_outlined,
              title: 'Secure health',
              onTap: () =>
                  _openMenuPage(context, const _SecureHealthMenuScreen()),
            ),
            _DrawerMenuTile(
              icon: Icons.account_circle_outlined,
              title: 'User status',
              onTap: () =>
                  _openMenuPage(context, const _UserStatusMenuScreen()),
            ),
            _DrawerMenuTile(
              icon: Icons.contrast_outlined,
              title: 'Theme',
              onTap: () => _openMenuPage(context, const _ThemeMenuScreen()),
            ),
            _DrawerMenuTile(
              icon: Icons.info_outline,
              title: 'App about',
              onTap: () => _openMenuPage(context, const _AboutMenuScreen()),
            ),
            _DrawerMenuTile(
              icon: Icons.support_agent_outlined,
              title: 'Support',
              onTap: () => _openMenuPage(context, const _SupportMenuScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _openMenuPage(BuildContext context, Widget page) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(MaterialPageRoute<void>(builder: (_) => page));
  }
}

class _DrawerMenuTile extends StatelessWidget {
  const _DrawerMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 6),
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _SecureHealthMenuScreen extends StatefulWidget {
  const _SecureHealthMenuScreen();

  @override
  State<_SecureHealthMenuScreen> createState() =>
      _SecureHealthMenuScreenState();
}

class _SecureHealthMenuScreenState extends State<_SecureHealthMenuScreen> {
  Future<List<SecureDetail>>? _detailsFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _detailsFuture ??= _loadDetails();
  }

  Future<List<SecureDetail>> _loadDetails() {
    return Drive2ShareScope.of(context).recentFileStore.listSecureDetails();
  }

  Future<void> _refresh() async {
    setState(() => _detailsFuture = _loadDetails());
    await _detailsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Secure health')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: <Widget>[
              FutureBuilder<List<SecureDetail>>(
                future: _detailsFuture,
                builder: (context, snapshot) {
                  return _SecurityHealthPanel(
                    details: snapshot.data ?? <SecureDetail>[],
                    isLoading: snapshot.connectionState != ConnectionState.done,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserStatusMenuScreen extends StatelessWidget {
  const _UserStatusMenuScreen();

  @override
  Widget build(BuildContext context) {
    final user = Drive2ShareScope.of(context).authService.currentUser;
    final name = user?.displayName?.trim();
    final email = user?.email.trim();
    final displayName = name != null && name.isNotEmpty
        ? name
        : email != null && email.isNotEmpty
        ? email
        : 'Not signed in';

    return Scaffold(
      appBar: AppBar(title: const Text('User status')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _MenuSection(
              icon: Icons.account_circle_outlined,
              title: 'User status',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    displayName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (email != null && email.isNotEmpty && email != displayName)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  const SizedBox(height: 10),
                  _StatusPill(
                    icon: user == null
                        ? Icons.error_outline
                        : Icons.verified_user_outlined,
                    label: user == null ? 'Google login needed' : 'Signed in',
                  ),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await Drive2ShareScope.of(
                          context,
                        ).authService.reauthorize();
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Google Sheets and Drive access connected.',
                            ),
                          ),
                        );
                      } catch (error) {
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              AuthService.friendlyGoogleError(
                                error,
                                service: 'Google',
                              ),
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.sync_lock_outlined),
                    label: const Text('Reconnect Google access'),
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

class _ThemeMenuScreen extends StatelessWidget {
  const _ThemeMenuScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Theme')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _ThemeMenuSection(
              controller: Drive2ShareScope.of(context).themeController,
            ),
          ],
        ),
      ),
    );
  }
}

class _AboutMenuScreen extends StatelessWidget {
  const _AboutMenuScreen();

  @override
  Widget build(BuildContext context) {
    final appName = Drive2ShareScope.of(context).config.appName;
    return Scaffold(
      appBar: AppBar(title: const Text('App about')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            _MenuSection(
              icon: Icons.info_outline,
              title: appName,
              child: const Text('Version 1.0.0+1'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMenuScreen extends StatelessWidget {
  const _SupportMenuScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Support')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: const <Widget>[
            _MenuSection(
              icon: Icons.support_agent_outlined,
              title: 'Support',
              child: Text('Login, Google Sheets sync, and sharing support.'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecurityHealthPanel extends StatelessWidget {
  const _SecurityHealthPanel({required this.details, required this.isLoading});

  final List<SecureDetail> details;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final total = details.length;
    final protectedFields = details.fold<int>(
      0,
      (sum, detail) => sum + detail.secretFieldCount,
    );
    final attentionCount = details
        .where((detail) => detail.needsAttention)
        .length;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.health_and_safety_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Secure health',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (isLoading)
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              _HealthPill(
                icon: Icons.folder_special_outlined,
                label: '$total saved',
              ),
              _HealthPill(
                icon: Icons.visibility_off_outlined,
                label: '$protectedFields protected',
              ),
              _HealthPill(
                icon: attentionCount == 0
                    ? Icons.verified_user_outlined
                    : Icons.notification_important_outlined,
                label: attentionCount == 0
                    ? 'No alerts'
                    : '$attentionCount alerts',
                isWarning: attentionCount > 0,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HealthPill extends StatelessWidget {
  const _HealthPill({
    required this.icon,
    required this.label,
    this.isWarning = false,
  });

  final IconData icon;
  final String label;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isWarning ? colorScheme.error : colorScheme.primary;
    final background = isWarning
        ? colorScheme.errorContainer.withValues(alpha: 0.44)
        : colorScheme.primaryContainer.withValues(alpha: 0.48);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  const _MenuSection({
    required this.icon,
    required this.title,
    required this.child,
  });

  final IconData icon;
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ThemeMenuSection extends StatelessWidget {
  const _ThemeMenuSection({required this.controller});

  final AppThemeController controller;

  @override
  Widget build(BuildContext context) {
    return _MenuSection(
      icon: Icons.contrast_outlined,
      title: 'Theme',
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          return SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            selected: <ThemeMode>{controller.themeMode},
            onSelectionChanged: (selection) {
              controller.setThemeMode(selection.single);
            },
            segments: const <ButtonSegment<ThemeMode>>[
              ButtonSegment<ThemeMode>(
                value: ThemeMode.system,
                icon: Icon(Icons.settings_suggest_outlined),
                label: Text('System'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.dark,
                icon: Icon(Icons.dark_mode_outlined),
                label: Text('Dark'),
              ),
              ButtonSegment<ThemeMode>(
                value: ThemeMode.light,
                icon: Icon(Icons.light_mode_outlined),
                label: Text('White'),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SetupMissingPanel extends StatelessWidget {
  const _SetupMissingPanel({required this.onSetup});

  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Choose your country setup',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text('Select country and secure sections to customize home.'),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onSetup,
            icon: const Icon(Icons.public_outlined),
            label: const Text('Start setup'),
          ),
        ],
      ),
    );
  }
}

class _SecureCategoryPanel extends StatelessWidget {
  const _SecureCategoryPanel({
    required this.types,
    required this.onOpenCategory,
  });

  final List<SecureDetailType> types;
  final ValueChanged<SecureDetailType> onOpenCategory;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Secure details',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 520 ? 4 : 3;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: types.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.86,
              ),
              itemBuilder: (context, index) {
                final type = types[index];
                return _SecureCategoryButton(
                  type: type,
                  onTap: () => onOpenCategory(type),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

class _SecureCategoryButton extends StatelessWidget {
  const _SecureCategoryButton({required this.type, required this.onTap});

  final SecureDetailType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: type.title,
      child: Material(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                CircleAvatar(
                  radius: 26,
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: colorScheme.onPrimaryContainer,
                  child: Icon(_iconFor(type)),
                ),
                const SizedBox(height: 10),
                Text(
                  type.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(SecureDetailType type) {
    return switch (type) {
      SecureDetailType.bank => Icons.account_balance_outlined,
      SecureDetailType.aadhaar => Icons.badge_outlined,
      SecureDetailType.pan => Icons.assignment_ind_outlined,
      SecureDetailType.passport => Icons.flight_takeoff_outlined,
      SecureDetailType.drivingLicense => Icons.directions_car_outlined,
      SecureDetailType.voterId => Icons.how_to_vote_outlined,
      SecureDetailType.upi => Icons.currency_rupee_outlined,
      SecureDetailType.login => Icons.key_outlined,
      SecureDetailType.password => Icons.password_outlined,
      SecureDetailType.nationalId => Icons.badge_outlined,
      SecureDetailType.taxId => Icons.receipt_long_outlined,
      SecureDetailType.socialSecurity => Icons.security_outlined,
      SecureDetailType.healthInsurance => Icons.medical_information_outlined,
      SecureDetailType.residencePermit => Icons.assignment_outlined,
      SecureDetailType.debitCard => Icons.account_balance_wallet_outlined,
      SecureDetailType.creditCard => Icons.credit_card_outlined,
      SecureDetailType.address => Icons.location_on_outlined,
    };
  }
}

class _DashboardButton extends StatelessWidget {
  const _DashboardButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
