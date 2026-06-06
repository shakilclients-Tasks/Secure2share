import 'secure_detail.dart';

class CountryProfile {
  const CountryProfile({
    required this.code,
    required this.name,
    required this.recommendedTypes,
  });

  final String code;
  final String name;
  final List<SecureDetailType> recommendedTypes;

  String get searchableText => '$name $code'.toLowerCase();
}

class CountryProfiles {
  static final List<CountryProfile> all = _countrySeeds
      .map(
        (seed) => CountryProfile(
          code: seed.code,
          name: seed.name,
          recommendedTypes: _typesFor(seed.code),
        ),
      )
      .toList(growable: false);

  static CountryProfile? byCode(String? code) {
    if (code == null || code.trim().isEmpty) return null;
    final normalized = code.toUpperCase();
    for (final country in all) {
      if (country.code == normalized) return country;
    }
    return null;
  }

  static List<CountryProfile> search(String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return all;
    return all
        .where((country) => country.searchableText.contains(normalized))
        .toList(growable: false);
  }

  static List<SecureDetailType> _typesFor(String code) {
    final types = <SecureDetailType>{
      SecureDetailType.bank,
      SecureDetailType.nationalId,
      SecureDetailType.passport,
      SecureDetailType.drivingLicense,
      SecureDetailType.address,
      SecureDetailType.debitCard,
      SecureDetailType.creditCard,
    };

    if (code == 'IN') {
      return const <SecureDetailType>[
        SecureDetailType.aadhaar,
        SecureDetailType.pan,
        SecureDetailType.voterId,
        SecureDetailType.upi,
        SecureDetailType.bank,
        SecureDetailType.passport,
        SecureDetailType.drivingLicense,
        SecureDetailType.address,
        SecureDetailType.debitCard,
        SecureDetailType.creditCard,
      ];
    }

    if (code == 'US') {
      types
        ..add(SecureDetailType.socialSecurity)
        ..add(SecureDetailType.taxId)
        ..add(SecureDetailType.healthInsurance);
      return types.toList(growable: false);
    }

    if (_socialSecurityCountries.contains(code)) {
      types
        ..add(SecureDetailType.socialSecurity)
        ..add(SecureDetailType.taxId)
        ..add(SecureDetailType.healthInsurance);
    }

    if (_taxCountries.contains(code)) {
      types.add(SecureDetailType.taxId);
    }

    if (_healthCountries.contains(code)) {
      types.add(SecureDetailType.healthInsurance);
    }

    if (_residencePermitCountries.contains(code)) {
      types.add(SecureDetailType.residencePermit);
    }

    return types.toList(growable: false);
  }

  static const Set<String> _socialSecurityCountries = <String>{
    'AU',
    'CA',
    'IE',
    'NZ',
    'SG',
    'GB',
  };

  static const Set<String> _taxCountries = <String>{
    'AR',
    'AT',
    'AU',
    'BE',
    'BR',
    'CA',
    'CH',
    'CL',
    'CN',
    'CO',
    'DE',
    'DK',
    'ES',
    'FI',
    'FR',
    'GB',
    'ID',
    'IE',
    'IT',
    'JP',
    'KR',
    'MX',
    'MY',
    'NL',
    'NO',
    'NZ',
    'PH',
    'PL',
    'PT',
    'SE',
    'SG',
    'TH',
    'TR',
    'ZA',
  };

  static const Set<String> _healthCountries = <String>{
    'AT',
    'AU',
    'BE',
    'CA',
    'CH',
    'DE',
    'DK',
    'ES',
    'FI',
    'FR',
    'GB',
    'IE',
    'IT',
    'JP',
    'KR',
    'NL',
    'NO',
    'NZ',
    'PT',
    'SE',
    'SG',
  };

  static const Set<String> _residencePermitCountries = <String>{
    'AE',
    'AT',
    'AU',
    'BE',
    'CA',
    'CH',
    'DE',
    'DK',
    'ES',
    'FI',
    'FR',
    'GB',
    'IE',
    'IT',
    'JP',
    'KR',
    'KW',
    'NL',
    'NO',
    'NZ',
    'QA',
    'SA',
    'SE',
    'SG',
    'US',
  };
}

class _CountrySeed {
  const _CountrySeed(this.code, this.name);

  final String code;
  final String name;
}

const List<_CountrySeed> _countrySeeds = <_CountrySeed>[
  _CountrySeed('AF', 'Afghanistan'),
  _CountrySeed('AL', 'Albania'),
  _CountrySeed('DZ', 'Algeria'),
  _CountrySeed('AD', 'Andorra'),
  _CountrySeed('AO', 'Angola'),
  _CountrySeed('AG', 'Antigua and Barbuda'),
  _CountrySeed('AR', 'Argentina'),
  _CountrySeed('AM', 'Armenia'),
  _CountrySeed('AU', 'Australia'),
  _CountrySeed('AT', 'Austria'),
  _CountrySeed('AZ', 'Azerbaijan'),
  _CountrySeed('BS', 'Bahamas'),
  _CountrySeed('BH', 'Bahrain'),
  _CountrySeed('BD', 'Bangladesh'),
  _CountrySeed('BB', 'Barbados'),
  _CountrySeed('BY', 'Belarus'),
  _CountrySeed('BE', 'Belgium'),
  _CountrySeed('BZ', 'Belize'),
  _CountrySeed('BJ', 'Benin'),
  _CountrySeed('BT', 'Bhutan'),
  _CountrySeed('BO', 'Bolivia'),
  _CountrySeed('BA', 'Bosnia and Herzegovina'),
  _CountrySeed('BW', 'Botswana'),
  _CountrySeed('BR', 'Brazil'),
  _CountrySeed('BN', 'Brunei'),
  _CountrySeed('BG', 'Bulgaria'),
  _CountrySeed('BF', 'Burkina Faso'),
  _CountrySeed('BI', 'Burundi'),
  _CountrySeed('CV', 'Cabo Verde'),
  _CountrySeed('KH', 'Cambodia'),
  _CountrySeed('CM', 'Cameroon'),
  _CountrySeed('CA', 'Canada'),
  _CountrySeed('CF', 'Central African Republic'),
  _CountrySeed('TD', 'Chad'),
  _CountrySeed('CL', 'Chile'),
  _CountrySeed('CN', 'China'),
  _CountrySeed('CO', 'Colombia'),
  _CountrySeed('KM', 'Comoros'),
  _CountrySeed('CG', 'Congo'),
  _CountrySeed('CD', 'Congo, Democratic Republic of the'),
  _CountrySeed('CR', 'Costa Rica'),
  _CountrySeed('CI', "Cote d'Ivoire"),
  _CountrySeed('HR', 'Croatia'),
  _CountrySeed('CU', 'Cuba'),
  _CountrySeed('CY', 'Cyprus'),
  _CountrySeed('CZ', 'Czechia'),
  _CountrySeed('DK', 'Denmark'),
  _CountrySeed('DJ', 'Djibouti'),
  _CountrySeed('DM', 'Dominica'),
  _CountrySeed('DO', 'Dominican Republic'),
  _CountrySeed('EC', 'Ecuador'),
  _CountrySeed('EG', 'Egypt'),
  _CountrySeed('SV', 'El Salvador'),
  _CountrySeed('GQ', 'Equatorial Guinea'),
  _CountrySeed('ER', 'Eritrea'),
  _CountrySeed('EE', 'Estonia'),
  _CountrySeed('SZ', 'Eswatini'),
  _CountrySeed('ET', 'Ethiopia'),
  _CountrySeed('FJ', 'Fiji'),
  _CountrySeed('FI', 'Finland'),
  _CountrySeed('FR', 'France'),
  _CountrySeed('GA', 'Gabon'),
  _CountrySeed('GM', 'Gambia'),
  _CountrySeed('GE', 'Georgia'),
  _CountrySeed('DE', 'Germany'),
  _CountrySeed('GH', 'Ghana'),
  _CountrySeed('GR', 'Greece'),
  _CountrySeed('GD', 'Grenada'),
  _CountrySeed('GT', 'Guatemala'),
  _CountrySeed('GN', 'Guinea'),
  _CountrySeed('GW', 'Guinea-Bissau'),
  _CountrySeed('GY', 'Guyana'),
  _CountrySeed('HT', 'Haiti'),
  _CountrySeed('HN', 'Honduras'),
  _CountrySeed('HU', 'Hungary'),
  _CountrySeed('IS', 'Iceland'),
  _CountrySeed('IN', 'India'),
  _CountrySeed('ID', 'Indonesia'),
  _CountrySeed('IR', 'Iran'),
  _CountrySeed('IQ', 'Iraq'),
  _CountrySeed('IE', 'Ireland'),
  _CountrySeed('IL', 'Israel'),
  _CountrySeed('IT', 'Italy'),
  _CountrySeed('JM', 'Jamaica'),
  _CountrySeed('JP', 'Japan'),
  _CountrySeed('JO', 'Jordan'),
  _CountrySeed('KZ', 'Kazakhstan'),
  _CountrySeed('KE', 'Kenya'),
  _CountrySeed('KI', 'Kiribati'),
  _CountrySeed('KP', 'North Korea'),
  _CountrySeed('KR', 'South Korea'),
  _CountrySeed('KW', 'Kuwait'),
  _CountrySeed('KG', 'Kyrgyzstan'),
  _CountrySeed('LA', 'Laos'),
  _CountrySeed('LV', 'Latvia'),
  _CountrySeed('LB', 'Lebanon'),
  _CountrySeed('LS', 'Lesotho'),
  _CountrySeed('LR', 'Liberia'),
  _CountrySeed('LY', 'Libya'),
  _CountrySeed('LI', 'Liechtenstein'),
  _CountrySeed('LT', 'Lithuania'),
  _CountrySeed('LU', 'Luxembourg'),
  _CountrySeed('MG', 'Madagascar'),
  _CountrySeed('MW', 'Malawi'),
  _CountrySeed('MY', 'Malaysia'),
  _CountrySeed('MV', 'Maldives'),
  _CountrySeed('ML', 'Mali'),
  _CountrySeed('MT', 'Malta'),
  _CountrySeed('MH', 'Marshall Islands'),
  _CountrySeed('MR', 'Mauritania'),
  _CountrySeed('MU', 'Mauritius'),
  _CountrySeed('MX', 'Mexico'),
  _CountrySeed('FM', 'Micronesia'),
  _CountrySeed('MD', 'Moldova'),
  _CountrySeed('MC', 'Monaco'),
  _CountrySeed('MN', 'Mongolia'),
  _CountrySeed('ME', 'Montenegro'),
  _CountrySeed('MA', 'Morocco'),
  _CountrySeed('MZ', 'Mozambique'),
  _CountrySeed('MM', 'Myanmar'),
  _CountrySeed('NA', 'Namibia'),
  _CountrySeed('NR', 'Nauru'),
  _CountrySeed('NP', 'Nepal'),
  _CountrySeed('NL', 'Netherlands'),
  _CountrySeed('NZ', 'New Zealand'),
  _CountrySeed('NI', 'Nicaragua'),
  _CountrySeed('NE', 'Niger'),
  _CountrySeed('NG', 'Nigeria'),
  _CountrySeed('MK', 'North Macedonia'),
  _CountrySeed('NO', 'Norway'),
  _CountrySeed('OM', 'Oman'),
  _CountrySeed('PK', 'Pakistan'),
  _CountrySeed('PW', 'Palau'),
  _CountrySeed('PA', 'Panama'),
  _CountrySeed('PG', 'Papua New Guinea'),
  _CountrySeed('PY', 'Paraguay'),
  _CountrySeed('PE', 'Peru'),
  _CountrySeed('PH', 'Philippines'),
  _CountrySeed('PL', 'Poland'),
  _CountrySeed('PT', 'Portugal'),
  _CountrySeed('QA', 'Qatar'),
  _CountrySeed('RO', 'Romania'),
  _CountrySeed('RU', 'Russia'),
  _CountrySeed('RW', 'Rwanda'),
  _CountrySeed('KN', 'Saint Kitts and Nevis'),
  _CountrySeed('LC', 'Saint Lucia'),
  _CountrySeed('VC', 'Saint Vincent and the Grenadines'),
  _CountrySeed('WS', 'Samoa'),
  _CountrySeed('SM', 'San Marino'),
  _CountrySeed('ST', 'Sao Tome and Principe'),
  _CountrySeed('SA', 'Saudi Arabia'),
  _CountrySeed('SN', 'Senegal'),
  _CountrySeed('RS', 'Serbia'),
  _CountrySeed('SC', 'Seychelles'),
  _CountrySeed('SL', 'Sierra Leone'),
  _CountrySeed('SG', 'Singapore'),
  _CountrySeed('SK', 'Slovakia'),
  _CountrySeed('SI', 'Slovenia'),
  _CountrySeed('SB', 'Solomon Islands'),
  _CountrySeed('SO', 'Somalia'),
  _CountrySeed('ZA', 'South Africa'),
  _CountrySeed('SS', 'South Sudan'),
  _CountrySeed('ES', 'Spain'),
  _CountrySeed('LK', 'Sri Lanka'),
  _CountrySeed('SD', 'Sudan'),
  _CountrySeed('SR', 'Suriname'),
  _CountrySeed('SE', 'Sweden'),
  _CountrySeed('CH', 'Switzerland'),
  _CountrySeed('SY', 'Syria'),
  _CountrySeed('TW', 'Taiwan'),
  _CountrySeed('TJ', 'Tajikistan'),
  _CountrySeed('TZ', 'Tanzania'),
  _CountrySeed('TH', 'Thailand'),
  _CountrySeed('TL', 'Timor-Leste'),
  _CountrySeed('TG', 'Togo'),
  _CountrySeed('TO', 'Tonga'),
  _CountrySeed('TT', 'Trinidad and Tobago'),
  _CountrySeed('TN', 'Tunisia'),
  _CountrySeed('TR', 'Turkey'),
  _CountrySeed('TM', 'Turkmenistan'),
  _CountrySeed('TV', 'Tuvalu'),
  _CountrySeed('UG', 'Uganda'),
  _CountrySeed('UA', 'Ukraine'),
  _CountrySeed('AE', 'United Arab Emirates'),
  _CountrySeed('GB', 'United Kingdom'),
  _CountrySeed('US', 'United States'),
  _CountrySeed('UY', 'Uruguay'),
  _CountrySeed('UZ', 'Uzbekistan'),
  _CountrySeed('VU', 'Vanuatu'),
  _CountrySeed('VA', 'Vatican City'),
  _CountrySeed('VE', 'Venezuela'),
  _CountrySeed('VN', 'Vietnam'),
  _CountrySeed('YE', 'Yemen'),
  _CountrySeed('ZM', 'Zambia'),
  _CountrySeed('ZW', 'Zimbabwe'),
];
