import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
// shakils projects this
import '../main.dart';
import '../models/secure_detail.dart' as model;
import '../services/drive_service.dart';
import '../services/secure_image_service.dart';

Future<SecureDetailSaveResult?> openSecureDetailsCreator(
  BuildContext context,
) async {
  final type = await showModalBottomSheet<model.SecureDetailType>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _SecureDetailsSheet(),
  );
  if (!context.mounted || type == null) return null;

  return openSecureDetailsForm(context, type);
}

Future<SecureDetailSaveResult?> openSecureDetailsForm(
  BuildContext context,
  model.SecureDetailType type,
) {
  return Navigator.of(context).push<SecureDetailSaveResult>(
    PageRouteBuilder<SecureDetailSaveResult>(
      pageBuilder: (_, animation, _) => FadeTransition(
        opacity: animation,
        child: SecureDetailsFormScreen(type: type),
      ),
      transitionsBuilder: (_, animation, _, child) {
        final offsetAnimation =
            Tween<Offset>(
              begin: const Offset(0.08, 0.04),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );
        return SlideTransition(position: offsetAnimation, child: child);
      },
    ),
  );
}

class SecureDetailSaveResult {
  const SecureDetailSaveResult({
    required this.detail,
    this.sheetsError,
    this.driveError,
  });

  final model.SecureDetail detail;
  final String? sheetsError;
  final String? driveError;

  bool get syncedToSheets => sheetsError == null;
  bool get imagesUploadedToDrive => detail.images.isEmpty || driveError == null;
}

class SecureDetailsFormScreen extends StatefulWidget {
  const SecureDetailsFormScreen({super.key, required this.type});

  final model.SecureDetailType type;

  @override
  State<SecureDetailsFormScreen> createState() =>
      _SecureDetailsFormScreenState();
}

class _SecureDetailsFormScreenState extends State<SecureDetailsFormScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final Uuid _uuid = const Uuid();
  late final List<_SecureDetailsField> _fields;
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, bool> _hiddenFields;
  final Map<model.SecureDetailImageSide, SelectedSecureImage> _selectedImages =
      <model.SecureDetailImageSide, SelectedSecureImage>{};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fields = _fieldsFor(widget.type);
    _controllers = <String, TextEditingController>{
      for (final field in _fields) field.key: TextEditingController(),
    };
    _hiddenFields = <String, bool>{
      for (final field in _fields)
        if (field.isSecret) field.key: true,
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    setState(() => _isSaving = true);
    try {
      final dependencies = Drive2ShareScope.of(context);
      final now = DateTime.now().millisecondsSinceEpoch;
      final detailId = _uuid.v4();
      final images = await dependencies.secureImageService.prepareImages(
        selectedImages: model.SecureDetailImageSide.values
            .map((side) => _selectedImages[side])
            .whereType<SelectedSecureImage>()
            .toList(growable: false),
      );
      var detail = model.SecureDetail(
        id: detailId,
        type: widget.type,
        fields: _normalizedFields(),
        createdAtMillis: now,
        updatedAtMillis: now,
        images: images,
      );

      final sheetsSave = _saveToSheets(dependencies, detail);
      final driveUpload = _uploadImages(dependencies, detail);

      final sheetsErrorMessage = await sheetsSave;
      final uploadResult = await driveUpload;
      final driveErrorMessage = uploadResult.error;
      if (detail.images.isNotEmpty) {
        detail = detail.copyWith(
          images: uploadResult.images,
          updatedAtMillis: DateTime.now().millisecondsSinceEpoch,
        );
        if (uploadResult.isSuccessful) {
          try {
            await FilePicker.clearTemporaryFiles();
          } catch (_) {
            // Some platforms do not create or expose picker temporary files.
          }
        }
      }
      await dependencies.recentFileStore.saveSecureDetail(detail);
      if (!mounted) return;
      Navigator.of(context).pop(
        SecureDetailSaveResult(
          detail: detail,
          sheetsError: sheetsErrorMessage,
          driveError: driveErrorMessage,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<String?> _saveToSheets(
    AppDependencies dependencies,
    model.SecureDetail detail,
  ) async {
    try {
      await dependencies.googleSheetsService.appendSecureDetail(detail);
      return null;
    } catch (error) {
      return error.toString();
    }
  }

  Future<DriveImageUploadResult> _uploadImages(
    AppDependencies dependencies,
    model.SecureDetail detail,
  ) {
    if (detail.images.isEmpty) {
      return Future<DriveImageUploadResult>.value(
        DriveImageUploadResult(images: detail.images),
      );
    }
    return dependencies.driveService.uploadSecureDetailImages(
      config: dependencies.config.driveFolder,
      detail: detail,
    );
  }

  Map<String, String> _normalizedFields() {
    final fields = <String, String>{};
    for (final field in _fields) {
      final controller = _controllers[field.key];
      if (controller == null) continue;

      final value = _normalizeFieldValue(field, controller.text);
      if (field.isRequired || value.isNotEmpty) {
        fields[field.key] = value;
      }
    }
    return fields;
  }

  String _normalizeFieldValue(_SecureDetailsField field, String value) {
    final text = value.trim();
    if (field.textCapitalization == TextCapitalization.characters) {
      return text.toUpperCase();
    }
    return text;
  }

  Future<void> _pickImage(model.SecureDetailImageSide side) async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: false,
    );
    if (result == null || result.files.isEmpty || !mounted) return;

    final file = result.files.single;
    final path = file.path;
    if (path == null || path.isEmpty) {
      _showSnack('Unable to read the selected image.');
      return;
    }
    if (file.size > 10 * 1024 * 1024) {
      _showSnack('Please select an image smaller than 10 MB.');
      return;
    }

    setState(() {
      _selectedImages[side] = SelectedSecureImage(
        side: side,
        sourcePath: path,
        originalName: file.name,
      );
    });
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final details = _DetailsMeta.fromType(widget.type);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(details.title)),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(20, 10, 20, 20),
        child: FilledButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_outline),
          label: Text(_isSaving ? 'Saving securely' : 'Save details'),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: <Widget>[
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                      child: Icon(details.icon),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            details.title,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Column(
                  children: <Widget>[
                    for (final field in _fields) ...<Widget>[
                      TextFormField(
                        controller: _controllers[field.key],
                        keyboardType: field.keyboardType,
                        inputFormatters: field.inputFormatters,
                        textCapitalization: field.textCapitalization,
                        maxLines: field.maxLines,
                        obscureText:
                            field.isSecret &&
                            (_hiddenFields[field.key] ?? false),
                        obscuringCharacter: '*',
                        validator: (value) => field.validate(value?.trim()),
                        decoration: InputDecoration(
                          labelText: field.label,
                          hintText: field.hint,
                          prefixIcon: Icon(field.icon),
                          suffixIcon: field.isSecret
                              ? IconButton(
                                  tooltip: (_hiddenFields[field.key] ?? false)
                                      ? 'Show'
                                      : 'Hide',
                                  onPressed: () {
                                    setState(() {
                                      _hiddenFields[field.key] =
                                          !(_hiddenFields[field.key] ?? false);
                                    });
                                  },
                                  icon: Icon(
                                    (_hiddenFields[field.key] ?? false)
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      if (field != _fields.last) const SizedBox(height: 14),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Document images',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  for (final side in model.SecureDetailImageSide.values) ...[
                    Expanded(
                      child: _ImagePickerTile(
                        side: side,
                        selectedImage: _selectedImages[side],
                        onPick: () => _pickImage(side),
                        onRemove: () {
                          setState(() => _selectedImages.remove(side));
                        },
                      ),
                    ),
                    if (side != model.SecureDetailImageSide.values.last)
                      const SizedBox(width: 12),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<_SecureDetailsField> _fieldsFor(model.SecureDetailType type) {
    return switch (type) {
      model.SecureDetailType.bank => <_SecureDetailsField>[
        _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Account holder name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'accountNumber',
          label: 'Account number',
          hint: 'Enter account number',
          icon: Icons.numbers_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
          ],
          isSecret: true,
          minLength: 6,
        ),
        _SecureDetailsField(
          key: 'ifsc',
          label: 'IFSC code',
          hint: 'Example: SBIN0000001',
          icon: Icons.tag_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(11),
          ],
          minLength: 11,
          exactLength: 11,
          pattern: RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$'),
          patternMessage: 'Enter a valid IFSC code.',
        ),
        const _SecureDetailsField(
          key: 'branch',
          label: 'Bank branch',
          hint: 'Branch name or address',
          icon: Icons.account_balance_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.aadhaar => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
        _SecureDetailsField(
          key: 'aadhaarNumber',
          label: 'Aadhaar number',
          hint: '12 digit Aadhaar number',
          icon: Icons.badge_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          isSecret: true,
          exactLength: 12,
        ),
        const _SecureDetailsField(
          key: 'address',
          label: 'Address',
          hint: 'Full address',
          icon: Icons.home_outlined,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.pan => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'panNumber',
          label: 'PAN number',
          hint: 'Example: ABCDE1234F',
          icon: Icons.assignment_ind_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(10),
          ],
          isSecret: true,
          exactLength: 10,
          pattern: RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$'),
          patternMessage: 'Enter a valid PAN number.',
        ),
        const _SecureDetailsField(
          key: 'fatherName',
          label: 'Father name',
          hint: 'Father name',
          icon: Icons.person_2_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
      ],
      model.SecureDetailType.passport => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'passportNumber',
          label: 'Passport number',
          hint: 'Enter passport number',
          icon: Icons.flight_takeoff_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(16),
          ],
          isSecret: true,
          minLength: 6,
        ),
        const _SecureDetailsField(
          key: 'nationality',
          label: 'Nationality',
          hint: 'Nationality',
          icon: Icons.public_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
        ),
      ],
      model.SecureDetailType.drivingLicense => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'licenseNumber',
          label: 'License number',
          hint: 'Enter license number',
          icon: Icons.badge_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(20),
          ],
          isSecret: true,
          minLength: 6,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'validUntil',
          label: 'Valid until',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
        ),
      ],
      model.SecureDetailType.voterId => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'voterIdNumber',
          label: 'Voter ID number',
          hint: 'Enter voter ID number',
          icon: Icons.how_to_vote_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(16),
          ],
          isSecret: true,
          minLength: 6,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'address',
          label: 'Address',
          hint: 'Full address',
          icon: Icons.home_outlined,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.upi => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Account holder name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'upiId',
          label: 'UPI ID',
          hint: 'name@bank',
          icon: Icons.currency_rupee_outlined,
          keyboardType: TextInputType.emailAddress,
        ),
        _SecureDetailsField(
          key: 'mobileNumber',
          label: 'Mobile number',
          hint: 'Registered mobile number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          isSecret: true,
          exactLength: 10,
        ),
        const _SecureDetailsField(
          key: 'bankName',
          label: 'Bank name',
          hint: 'Linked bank name',
          icon: Icons.account_balance_outlined,
          textCapitalization: TextCapitalization.words,
        ),
      ],
      model.SecureDetailType.login => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'serviceName',
          label: 'Service name',
          hint: 'App or website name',
          icon: Icons.apps_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'username',
          label: 'Username',
          hint: 'Email, phone, or username',
          icon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const _SecureDetailsField(
          key: 'password',
          label: 'Password',
          hint: 'Password',
          icon: Icons.password_outlined,
          isSecret: true,
          minLength: 1,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Recovery notes',
          icon: Icons.notes_outlined,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.password => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'serviceName',
          label: 'Service name',
          hint: 'App or website name',
          icon: Icons.apps_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'username',
          label: 'Username',
          hint: 'Email, phone, or username',
          icon: Icons.person_outline,
          keyboardType: TextInputType.emailAddress,
        ),
        const _SecureDetailsField(
          key: 'password',
          label: 'Password',
          hint: 'Password',
          icon: Icons.password_outlined,
          isSecret: true,
          minLength: 1,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Recovery notes',
          icon: Icons.notes_outlined,
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.nationalId => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'idNumber',
          label: 'ID number',
          hint: 'National ID number',
          icon: Icons.badge_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
          isRequired: false,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Extra notes',
          icon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          isRequired: false,
        ),
      ],
      model.SecureDetailType.taxId => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name or business name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'taxNumber',
          label: 'Tax number',
          hint: 'Tax ID / TIN / NIF',
          icon: Icons.receipt_long_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
        ),
        const _SecureDetailsField(
          key: 'country',
          label: 'Country',
          hint: 'Country',
          icon: Icons.public_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Extra notes',
          icon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          isRequired: false,
        ),
      ],
      model.SecureDetailType.socialSecurity => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'socialSecurityNumber',
          label: 'Social Security number',
          hint: 'Social Security / Insurance number',
          icon: Icons.security_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
        ),
        const _SecureDetailsField(
          key: 'dob',
          label: 'Date of birth',
          hint: 'DD/MM/YYYY',
          icon: Icons.calendar_today_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Extra notes',
          icon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          isRequired: false,
        ),
      ],
      model.SecureDetailType.healthInsurance => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Member name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'healthId',
          label: 'Health ID',
          hint: 'Health card or member ID',
          icon: Icons.medical_information_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
        ),
        _SecureDetailsField(
          key: 'policyNumber',
          label: 'Policy number',
          hint: 'Insurance policy number',
          icon: Icons.policy_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
          isRequired: false,
        ),
        const _SecureDetailsField(
          key: 'provider',
          label: 'Provider',
          hint: 'Insurance or health provider',
          icon: Icons.local_hospital_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
          isRequired: false,
        ),
      ],
      model.SecureDetailType.residencePermit => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'name',
          label: 'Name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'permitNumber',
          label: 'Permit number',
          hint: 'Residence permit number',
          icon: Icons.assignment_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            const _UpperCaseTextFormatter(),
            LengthLimitingTextInputFormatter(32),
          ],
          isSecret: true,
          minLength: 4,
        ),
        const _SecureDetailsField(
          key: 'nationality',
          label: 'Nationality',
          hint: 'Nationality',
          icon: Icons.public_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'DD/MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'address',
          label: 'Address',
          hint: 'Local address',
          icon: Icons.home_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
          isRequired: false,
        ),
      ],
      model.SecureDetailType.debitCard => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'cardHolderName',
          label: 'Cardholder name',
          hint: 'Name on card',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'cardNumber',
          label: 'Card number',
          hint: 'Debit card number',
          icon: Icons.account_balance_wallet_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(19),
          ],
          isSecret: true,
          minLength: 12,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'bankName',
          label: 'Bank name',
          hint: 'Card issuing bank',
          icon: Icons.account_balance_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Card notes',
          icon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.creditCard => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'cardHolderName',
          label: 'Cardholder name',
          hint: 'Name on card',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'cardNumber',
          label: 'Card number',
          hint: 'Credit card number',
          icon: Icons.credit_card_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(19),
          ],
          isSecret: true,
          minLength: 12,
        ),
        const _SecureDetailsField(
          key: 'expiryDate',
          label: 'Expiry date',
          hint: 'MM/YYYY',
          icon: Icons.event_available_outlined,
          keyboardType: TextInputType.datetime,
        ),
        const _SecureDetailsField(
          key: 'bankName',
          label: 'Bank name',
          hint: 'Card issuing bank',
          icon: Icons.account_balance_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'notes',
          label: 'Notes',
          hint: 'Card notes',
          icon: Icons.notes_outlined,
          maxLines: 3,
          textCapitalization: TextCapitalization.sentences,
        ),
      ],
      model.SecureDetailType.address => <_SecureDetailsField>[
        const _SecureDetailsField(
          key: 'fullName',
          label: 'Full name',
          hint: 'Full name',
          icon: Icons.person_outline,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'phoneNumber',
          label: 'Phone number',
          hint: '10 digit phone number',
          icon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(10),
          ],
          isSecret: true,
          exactLength: 10,
        ),
        const _SecureDetailsField(
          key: 'addressLine1',
          label: 'Address line 1',
          hint: 'House, street, area',
          icon: Icons.home_outlined,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
        ),
        const _SecureDetailsField(
          key: 'addressLine2',
          label: 'Address line 2',
          hint: 'Landmark or extra address',
          icon: Icons.add_home_work_outlined,
          maxLines: 2,
          textCapitalization: TextCapitalization.sentences,
          isRequired: false,
        ),
        const _SecureDetailsField(
          key: 'city',
          label: 'City',
          hint: 'City',
          icon: Icons.location_city_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'district',
          label: 'District',
          hint: 'District',
          icon: Icons.map_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        const _SecureDetailsField(
          key: 'state',
          label: 'State',
          hint: 'State',
          icon: Icons.explore_outlined,
          textCapitalization: TextCapitalization.words,
        ),
        _SecureDetailsField(
          key: 'pincode',
          label: 'Pincode',
          hint: '6 digit pincode',
          icon: Icons.pin_drop_outlined,
          keyboardType: TextInputType.number,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(6),
          ],
          exactLength: 6,
        ),
        const _SecureDetailsField(
          key: 'country',
          label: 'Country',
          hint: 'Country',
          icon: Icons.public_outlined,
          textCapitalization: TextCapitalization.words,
        ),
      ],
    };
  }
}

class _ImagePickerTile extends StatelessWidget {
  const _ImagePickerTile({
    required this.side,
    required this.selectedImage,
    required this.onPick,
    required this.onRemove,
  });

  final model.SecureDetailImageSide side;
  final SelectedSecureImage? selectedImage;
  final VoidCallback onPick;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = selectedImage;

    return Material(
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPick,
        child: SizedBox(
          height: 152,
          child: selected == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(
                      side == model.SecureDetailImageSide.front
                          ? Icons.add_photo_alternate_outlined
                          : Icons.flip_to_back_outlined,
                      size: 34,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      side.label,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                )
              : Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Image.file(
                      File(selected.sourcePath),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Center(
                        child: Icon(Icons.broken_image_outlined, size: 36),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 7,
                        ),
                        color: colorScheme.scrim.withValues(alpha: 0.7),
                        child: Text(
                          side.label,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: IconButton.filled(
                        tooltip: 'Remove ${side.label}',
                        onPressed: onRemove,
                        icon: const Icon(Icons.close, size: 18),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _SecureDetailsField {
  const _SecureDetailsField({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters = const <TextInputFormatter>[],
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
    this.isSecret = false,
    this.isRequired = true,
    this.minLength,
    this.exactLength,
    this.pattern,
    this.patternMessage,
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool isSecret;
  final bool isRequired;
  final int? minLength;
  final int? exactLength;
  final RegExp? pattern;
  final String? patternMessage;

  String? validate(String? value) {
    final text = value ?? '';
    if (text.isEmpty) {
      return isRequired ? '$label is required.' : null;
    }
    final exact = exactLength;
    if (exact != null && text.length != exact) {
      return '$label must be $exact characters.';
    }
    final min = minLength;
    if (min != null && text.length < min) {
      return '$label must be at least $min characters.';
    }
    final validationPattern = pattern;
    if (validationPattern != null && !validationPattern.hasMatch(text)) {
      return patternMessage ?? '$label is invalid.';
    }
    return null;
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
  const _UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class _DetailsMeta {
  const _DetailsMeta({required this.title, required this.icon});

  final String title;
  final IconData icon;

  factory _DetailsMeta.fromType(model.SecureDetailType type) {
    return switch (type) {
      model.SecureDetailType.bank => const _DetailsMeta(
        title: 'Bank Details',
        icon: Icons.account_balance_outlined,
      ),
      model.SecureDetailType.aadhaar => const _DetailsMeta(
        title: 'Aadhaar Details',
        icon: Icons.badge_outlined,
      ),
      model.SecureDetailType.pan => const _DetailsMeta(
        title: 'PAN Details',
        icon: Icons.assignment_ind_outlined,
      ),
      model.SecureDetailType.passport => const _DetailsMeta(
        title: 'Passport Details',
        icon: Icons.flight_takeoff_outlined,
      ),
      model.SecureDetailType.drivingLicense => const _DetailsMeta(
        title: 'Driving License',
        icon: Icons.directions_car_outlined,
      ),
      model.SecureDetailType.voterId => const _DetailsMeta(
        title: 'Voter ID',
        icon: Icons.how_to_vote_outlined,
      ),
      model.SecureDetailType.upi => const _DetailsMeta(
        title: 'UPI Details',
        icon: Icons.currency_rupee_outlined,
      ),
      model.SecureDetailType.login => const _DetailsMeta(
        title: 'Login Details',
        icon: Icons.key_outlined,
      ),
      model.SecureDetailType.password => const _DetailsMeta(
        title: 'Passwords',
        icon: Icons.password_outlined,
      ),
      model.SecureDetailType.nationalId => const _DetailsMeta(
        title: 'National ID',
        icon: Icons.badge_outlined,
      ),
      model.SecureDetailType.taxId => const _DetailsMeta(
        title: 'Tax ID',
        icon: Icons.receipt_long_outlined,
      ),
      model.SecureDetailType.socialSecurity => const _DetailsMeta(
        title: 'Social Security',
        icon: Icons.security_outlined,
      ),
      model.SecureDetailType.healthInsurance => const _DetailsMeta(
        title: 'Health Insurance',
        icon: Icons.medical_information_outlined,
      ),
      model.SecureDetailType.residencePermit => const _DetailsMeta(
        title: 'Residence Permit',
        icon: Icons.assignment_outlined,
      ),
      model.SecureDetailType.debitCard => const _DetailsMeta(
        title: 'Debit Card',
        icon: Icons.account_balance_wallet_outlined,
      ),
      model.SecureDetailType.creditCard => const _DetailsMeta(
        title: 'Credit Card',
        icon: Icons.credit_card_outlined,
      ),
      model.SecureDetailType.address => const _DetailsMeta(
        title: 'Address Details',
        icon: Icons.location_on_outlined,
      ),
    };
  }
}

class _SecureDetailsSheet extends StatelessWidget {
  const _SecureDetailsSheet();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 18,
        children: <Widget>[
          _SecureChoiceButton(
            icon: Icons.account_balance_outlined,
            tooltip: 'Bank Details',
            onTap: () => Navigator.of(context).pop(model.SecureDetailType.bank),
          ),
          _SecureChoiceButton(
            icon: Icons.badge_outlined,
            tooltip: 'Aadhaar Details',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.aadhaar),
          ),
          _SecureChoiceButton(
            icon: Icons.assignment_ind_outlined,
            tooltip: 'PAN Details',
            onTap: () => Navigator.of(context).pop(model.SecureDetailType.pan),
          ),
          _SecureChoiceButton(
            icon: Icons.flight_takeoff_outlined,
            tooltip: 'Passport Details',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.passport),
          ),
          _SecureChoiceButton(
            icon: Icons.directions_car_outlined,
            tooltip: 'Driving License',
            onTap: () => Navigator.of(
              context,
            ).pop(model.SecureDetailType.drivingLicense),
          ),
          _SecureChoiceButton(
            icon: Icons.how_to_vote_outlined,
            tooltip: 'Voter ID',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.voterId),
          ),
          _SecureChoiceButton(
            icon: Icons.currency_rupee_outlined,
            tooltip: 'UPI Details',
            onTap: () => Navigator.of(context).pop(model.SecureDetailType.upi),
          ),
          _SecureChoiceButton(
            icon: Icons.account_balance_wallet_outlined,
            tooltip: 'Debit Card',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.debitCard),
          ),
          _SecureChoiceButton(
            icon: Icons.credit_card_outlined,
            tooltip: 'Credit Card',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.creditCard),
          ),
          _SecureChoiceButton(
            icon: Icons.location_on_outlined,
            tooltip: 'Address Details',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.address),
          ),
        ],
      ),
    );
  }
}

class _SecureChoiceButton extends StatelessWidget {
  const _SecureChoiceButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 48,
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: colorScheme.onPrimaryContainer),
        ),
      ),
    );
  }
}
