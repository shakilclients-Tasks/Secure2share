import 'dart:convert';

enum SecureDetailImageSide {
  front('front', 'Front image'),
  back('back', 'Back image');

  const SecureDetailImageSide(this.value, this.label);

  final String value;
  final String label;

  static SecureDetailImageSide fromValue(String value) {
    return SecureDetailImageSide.values.firstWhere(
      (side) => side.value == value,
      orElse: () => SecureDetailImageSide.front,
    );
  }
}

class SecureDetailImage {
  const SecureDetailImage({
    required this.side,
    required this.localPath,
    required this.fileName,
    required this.mimeType,
    this.driveFileId,
    this.driveWebViewLink,
  });

  final SecureDetailImageSide side;
  final String localPath;
  final String fileName;
  final String mimeType;
  final String? driveFileId;
  final String? driveWebViewLink;

  bool get isUploadedToDrive => driveFileId?.isNotEmpty == true;

  SecureDetailImage copyWith({
    String? localPath,
    String? fileName,
    String? mimeType,
    String? driveFileId,
    String? driveWebViewLink,
  }) {
    return SecureDetailImage(
      side: side,
      localPath: localPath ?? this.localPath,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      driveFileId: driveFileId ?? this.driveFileId,
      driveWebViewLink: driveWebViewLink ?? this.driveWebViewLink,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'side': side.value,
      'localPath': localPath,
      'fileName': fileName,
      'mimeType': mimeType,
      if (driveFileId != null) 'driveFileId': driveFileId,
      if (driveWebViewLink != null) 'driveWebViewLink': driveWebViewLink,
    };
  }

  factory SecureDetailImage.fromJson(Map<String, dynamic> json) {
    return SecureDetailImage(
      side: SecureDetailImageSide.fromValue(json['side'] as String? ?? ''),
      localPath: json['localPath'] as String? ?? '',
      fileName: json['fileName'] as String? ?? 'image',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      driveFileId: json['driveFileId'] as String?,
      driveWebViewLink: json['driveWebViewLink'] as String?,
    );
  }
}

enum SecureDetailType {
  bank('bank', 'Bank Details'),
  aadhaar('aadhaar', 'Aadhaar Details'),
  pan('pan', 'PAN Details'),
  passport('passport', 'Passport Details'),
  drivingLicense('drivingLicense', 'Driving License'),
  voterId('voterId', 'Voter ID'),
  upi('upi', 'UPI Details'),
  login('login', 'Login Details'),
  password('password', 'Passwords'),
  nationalId('nationalId', 'National ID'),
  taxId('taxId', 'Tax ID'),
  socialSecurity('socialSecurity', 'Social Security'),
  healthInsurance('healthInsurance', 'Health Insurance'),
  residencePermit('residencePermit', 'Residence Permit'),
  debitCard('debitCard', 'Debit Card'),
  creditCard('creditCard', 'Credit Card'),
  address('address', 'Address Details');

  const SecureDetailType(this.value, this.title);

  final String value;
  final String title;

  static SecureDetailType fromValue(String value) {
    return SecureDetailType.values.firstWhere(
      (type) => type.value == value,
      orElse: () => SecureDetailType.bank,
    );
  }
}

class SecureDetail {
  const SecureDetail({
    required this.id,
    required this.type,
    required this.fields,
    required this.createdAtMillis,
    required this.updatedAtMillis,
    this.images = const <SecureDetailImage>[],
  });

  final String id;
  final SecureDetailType type;
  final Map<String, String> fields;
  final int createdAtMillis;
  final int updatedAtMillis;
  final List<SecureDetailImage> images;

  String get title => type.title;

  int get secretFieldCount =>
      fields.keys.where(SecureDetail.isSecretField).length;

  bool get hasEmptyField => fields.values.any((value) => value.trim().isEmpty);

  DateTime? get expiryDate {
    for (final key in _expiryFieldKeys) {
      final parsed = _parseDate(fields[key]);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? get daysUntilExpiry {
    final expiry = expiryDate;
    if (expiry == null) return null;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return expiry.difference(today).inDays;
  }

  bool get isExpired {
    final days = daysUntilExpiry;
    return days != null && days < 0;
  }

  bool get expiresSoon {
    final days = daysUntilExpiry;
    return days != null && days >= 0 && days <= 45;
  }

  bool get needsAttention => hasEmptyField || isExpired || expiresSoon;

  String get searchableText {
    final labels = fields.keys.map(SecureDetail.labelFor);
    return <String>[title, ...labels, ...fields.values].join(' ').toLowerCase();
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'type': type.value,
      'title': title,
      'dataJson': jsonEncode(<String, Object?>{
        'fields': fields,
        'images': images.map((image) => image.toJson()).toList(),
      }),
      'createdAtMillis': createdAtMillis,
      'updatedAtMillis': updatedAtMillis,
    };
  }

  String toShareText({bool maskSecrets = false}) {
    final lines = <String>[
      title,
      '',
      for (final entry in fields.entries)
        '${labelFor(entry.key)}: ${maskSecrets && isSecretField(entry.key) ? maskedValue(entry.value) : entry.value}',
    ];
    return lines.join('\n');
  }

  static bool isSecretField(String key) => _secretFieldKeys.contains(key);

  static String maskedValue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.length <= 2) return '*' * trimmed.length;

    final visibleCount = trimmed.length <= 6 ? 2 : 4;
    final visibleTail = trimmed.substring(trimmed.length - visibleCount);
    return '${'*' * (trimmed.length - visibleCount)}$visibleTail';
  }

  factory SecureDetail.fromMap(Map<String, Object?> map) {
    final dataJson = map['dataJson'] as String? ?? '{}';
    final decoded = jsonDecode(dataJson) as Map<String, dynamic>;
    final nestedFields = decoded['fields'];
    final rawFields = nestedFields is Map<String, dynamic>
        ? nestedFields
        : decoded;
    final rawImages = decoded['images'];
    return SecureDetail(
      id: map['id'] as String,
      type: SecureDetailType.fromValue(map['type'] as String),
      fields: rawFields.map((key, value) => MapEntry(key, value.toString())),
      createdAtMillis: map['createdAtMillis'] as int,
      updatedAtMillis: map['updatedAtMillis'] as int,
      images: rawImages is List<dynamic>
          ? rawImages
                .whereType<Map<String, dynamic>>()
                .map(SecureDetailImage.fromJson)
                .toList(growable: false)
          : const <SecureDetailImage>[],
    );
  }

  SecureDetail copyWith({
    Map<String, String>? fields,
    int? updatedAtMillis,
    List<SecureDetailImage>? images,
  }) {
    return SecureDetail(
      id: id,
      type: type,
      fields: fields ?? this.fields,
      createdAtMillis: createdAtMillis,
      updatedAtMillis: updatedAtMillis ?? this.updatedAtMillis,
      images: images ?? this.images,
    );
  }

  static const Set<String> _secretFieldKeys = <String>{
    'accountNumber',
    'aadhaarNumber',
    'panNumber',
    'passportNumber',
    'licenseNumber',
    'voterIdNumber',
    'mobileNumber',
    'password',
    'phoneNumber',
    'cardNumber',
    'idNumber',
    'taxNumber',
    'socialSecurityNumber',
    'healthId',
    'policyNumber',
    'permitNumber',
  };

  static const Set<String> _expiryFieldKeys = <String>{
    'expiryDate',
    'validUntil',
  };

  static DateTime? _parseDate(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;

    final parts = text.split(RegExp(r'[-/]'));
    if (parts.length == 2) {
      final month = int.tryParse(parts[0]);
      final year = int.tryParse(parts[1]);
      if (month == null || year == null) return null;
      if (year < 1900 || month < 1 || month > 12) return null;
      return DateTime(year, month + 1, 0);
    }

    if (parts.length != 3) return null;

    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    final third = int.tryParse(parts[2]);
    if (first == null || second == null || third == null) return null;

    final hasYearFirst = parts[0].length == 4;
    final year = hasYearFirst ? first : third;
    final month = second;
    final day = hasYearFirst ? third : first;
    if (year < 1900 || month < 1 || month > 12 || day < 1 || day > 31) {
      return null;
    }

    final parsed = DateTime(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed;
  }

  static String labelFor(String key) {
    return switch (key) {
      'name' => 'Name',
      'accountNumber' => 'Account number',
      'ifsc' => 'IFSC code',
      'branch' => 'Bank branch',
      'dob' => 'Date of birth',
      'aadhaarNumber' => 'Aadhaar number',
      'address' => 'Address',
      'panNumber' => 'PAN number',
      'fatherName' => 'Father name',
      'passportNumber' => 'Passport number',
      'nationality' => 'Nationality',
      'expiryDate' => 'Expiry date',
      'licenseNumber' => 'License number',
      'validUntil' => 'Valid until',
      'voterIdNumber' => 'Voter ID number',
      'upiId' => 'UPI ID',
      'mobileNumber' => 'Mobile number',
      'bankName' => 'Bank name',
      'serviceName' => 'Service name',
      'username' => 'Username',
      'password' => 'Password',
      'cardHolderName' => 'Cardholder name',
      'cardNumber' => 'Card number',
      'idNumber' => 'ID number',
      'taxNumber' => 'Tax number',
      'socialSecurityNumber' => 'Social Security number',
      'healthId' => 'Health ID',
      'policyNumber' => 'Policy number',
      'provider' => 'Provider',
      'permitNumber' => 'Permit number',
      'notes' => 'Notes',
      'fullName' => 'Full name',
      'phoneNumber' => 'Phone number',
      'addressLine1' => 'Address line 1',
      'addressLine2' => 'Address line 2',
      'city' => 'City',
      'district' => 'District',
      'state' => 'State',
      'pincode' => 'Pincode',
      'country' => 'Country',
      _ => key,
    };
  }
}
