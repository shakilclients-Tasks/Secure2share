import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../main.dart';
import '../models/secure_detail.dart' as model;

Future<model.SecureDetail?> openSecureDetailsCreator(
  BuildContext context,
) async {
  final type = await showModalBottomSheet<model.SecureDetailType>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    builder: (context) => const _SecureDetailsSheet(),
  );
  if (!context.mounted || type == null) return null;

  return Navigator.of(context).push<model.SecureDetail>(
    PageRouteBuilder<model.SecureDetail>(
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
    final formState = _formKey.currentState;
    if (formState == null || !formState.validate()) return;

    setState(() => _isSaving = true);
    try {
      final dependencies = Drive2ShareScope.of(context);
      final now = DateTime.now().millisecondsSinceEpoch;
      final detail = model.SecureDetail(
        id: _uuid.v4(),
        type: widget.type,
        fields: <String, String>{
          for (final field in _fields)
            field.key: _controllers[field.key]!.text.trim(),
        },
        createdAtMillis: now,
        updatedAtMillis: now,
      );

      await dependencies.recentFileStore.saveSecureDetail(detail);
      try {
        await dependencies.googleSheetsService.appendSecureDetail(detail);
      } catch (sheetsError) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Saved in app, but Google Sheets sync failed: $sheetsError',
            ),
          ),
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(detail);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to save: $error')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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
        const _SecureDetailsField(
          key: 'ifsc',
          label: 'IFSC code',
          hint: 'Example: SBIN0000001',
          icon: Icons.tag_outlined,
          textCapitalization: TextCapitalization.characters,
          minLength: 11,
          exactLength: 11,
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
          icon: Icons.credit_card_outlined,
          textCapitalization: TextCapitalization.characters,
          inputFormatters: <TextInputFormatter>[
            LengthLimitingTextInputFormatter(10),
          ],
          isSecret: true,
          exactLength: 10,
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
    return null;
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
        icon: Icons.credit_card_outlined,
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
            icon: Icons.credit_card_outlined,
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
            icon: Icons.key_outlined,
            tooltip: 'Login Details',
            onTap: () =>
                Navigator.of(context).pop(model.SecureDetailType.login),
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
