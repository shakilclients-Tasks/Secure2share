import 'package:flutter/material.dart';

import '../main.dart';
import '../models/country_profile.dart';
import '../models/secure_detail.dart';
import 'home_screen.dart';

class CountrySetupScreen extends StatefulWidget {
  const CountrySetupScreen({super.key});

  @override
  State<CountrySetupScreen> createState() => _CountrySetupScreenState();
}

class _CountrySetupScreenState extends State<CountrySetupScreen> {
  CountryProfile? _selectedCountry;
  Set<SecureDetailType> _selectedTypes = <SecureDetailType>{};
  String _query = '';
  bool _isSaving = false;

  void _selectCountry(CountryProfile country) {
    setState(() {
      _selectedCountry = country;
      _selectedTypes = country.recommendedTypes.toSet();
    });
  }

  void _toggleType(SecureDetailType type) {
    setState(() {
      if (_selectedTypes.contains(type)) {
        _selectedTypes.remove(type);
      } else {
        _selectedTypes.add(type);
      }
    });
  }

  Future<void> _save() async {
    final country = _selectedCountry;
    if (country == null || _selectedTypes.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    try {
      await Drive2ShareScope.of(context).userProfileStore.saveCountrySetup(
        countryCode: country.code,
        selectedTypes: _selectedTypes.toList(growable: false),
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const HomeScreen()),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save setup: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final country = _selectedCountry;
    return Scaffold(
      appBar: AppBar(
        title: Text(country == null ? 'Choose country' : 'Choose sections'),
        leading: country == null
            ? null
            : IconButton(
                tooltip: 'Back',
                onPressed: () => setState(() => _selectedCountry = null),
                icon: const Icon(Icons.arrow_back),
              ),
      ),
      bottomNavigationBar: country == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              child: FilledButton.icon(
                onPressed: _selectedTypes.isEmpty || _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isSaving ? 'Saving setup' : 'Continue'),
              ),
            ),
      body: SafeArea(
        child: country == null ? _buildCountryList() : _buildSectionList(),
      ),
    );
  }

  Widget _buildCountryList() {
    final countries = CountryProfiles.search(_query);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      children: <Widget>[
        Text(
          'Select your country',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Secure sections will be suggested based on the documents commonly used there.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        TextField(
          onChanged: (value) => setState(() => _query = value),
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_outlined),
            hintText: 'Search country',
          ),
        ),
        const SizedBox(height: 12),
        for (final country in countries)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(child: Text(country.code)),
              title: Text(country.name),
              subtitle: Text('${country.recommendedTypes.length} sections'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _selectCountry(country),
            ),
          ),
      ],
    );
  }

  Widget _buildSectionList() {
    final country = _selectedCountry!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 110),
      children: <Widget>[
        Text(
          country.name,
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Keep only the sections you want on your home screen.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const SizedBox(height: 18),
        for (final type in country.recommendedTypes)
          _SectionChoiceTile(
            type: type,
            isSelected: _selectedTypes.contains(type),
            onToggle: () => _toggleType(type),
          ),
      ],
    );
  }
}

class _SectionChoiceTile extends StatelessWidget {
  const _SectionChoiceTile({
    required this.type,
    required this.isSelected,
    required this.onToggle,
  });

  final SecureDetailType type;
  final bool isSelected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(child: Icon(_iconFor(type))),
        title: Text(type.title),
        trailing: OutlinedButton.icon(
          onPressed: onToggle,
          icon: Icon(isSelected ? Icons.remove_circle_outline : Icons.add),
          label: Text(isSelected ? 'Remove' : 'Add'),
        ),
        onTap: onToggle,
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
