import 'dart:convert';

import '../models/secure_detail.dart';
import 'recent_file_store.dart';

class UserProfileStore {
  const UserProfileStore(this._store);

  static const String _introCompleteKey = 'introComplete';
  static const String _countryCodeKey = 'selectedCountryCode';
  static const String _selectedTypesKey = 'selectedSecureTypes';

  final RecentFileStore _store;

  Future<bool> isIntroComplete() async {
    return await _store.getSetting(_introCompleteKey) == 'true';
  }

  Future<void> setIntroComplete() {
    return _store.setSetting(_introCompleteKey, 'true');
  }

  Future<String?> selectedCountryCode() async {
    final value = await _store.getSetting(_countryCodeKey);
    return value?.trim().isEmpty == true ? null : value;
  }

  Future<List<SecureDetailType>> selectedTypes() async {
    final jsonText = await _store.getSetting(_selectedTypesKey);
    if (jsonText == null || jsonText.trim().isEmpty) {
      return const <SecureDetailType>[];
    }

    final decoded = jsonDecode(jsonText);
    if (decoded is! List<dynamic>) return const <SecureDetailType>[];
    return decoded
        .whereType<String>()
        .map(SecureDetailType.fromValue)
        .where((type) => type != SecureDetailType.password)
        .toSet()
        .toList(growable: false);
  }

  Future<bool> isCountrySetupComplete() async {
    final countryCode = await selectedCountryCode();
    final types = await selectedTypes();
    return countryCode != null && countryCode.isNotEmpty && types.isNotEmpty;
  }

  Future<void> saveCountrySetup({
    required String countryCode,
    required List<SecureDetailType> selectedTypes,
  }) async {
    final filteredTypes = selectedTypes
        .where((type) => type != SecureDetailType.password)
        .map((type) => type.value)
        .toSet()
        .toList(growable: false);
    await _store.setSetting(_countryCodeKey, countryCode);
    await _store.setSetting(_selectedTypesKey, jsonEncode(filteredTypes));
  }
}
