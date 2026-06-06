import 'package:drive2share/models/secure_detail.dart';
import 'package:drive2share/services/auth_service.dart';
import 'package:drive2share/services/google_sheets_service.dart';
import 'package:drive2share/services/recent_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;

void main() {
  test('reads legacy secure detail data without images', () {
    final detail = SecureDetail.fromMap(<String, Object?>{
      'id': 'legacy-id',
      'type': 'aadhaar',
      'dataJson': '{"name":"Shakil","aadhaarNumber":"1234"}',
      'createdAtMillis': 1,
      'updatedAtMillis': 1,
    });

    expect(detail.fields['name'], 'Shakil');
    expect(detail.images, isEmpty);
  });

  test('persists front and back image metadata', () {
    const detail = SecureDetail(
      id: 'detail-id',
      type: SecureDetailType.passport,
      fields: <String, String>{'name': 'Shakil'},
      createdAtMillis: 1,
      updatedAtMillis: 2,
      images: <SecureDetailImage>[
        SecureDetailImage(
          side: SecureDetailImageSide.front,
          localPath: '/private/front.jpg',
          fileName: 'front.jpg',
          mimeType: 'image/jpeg',
          driveFileId: 'drive-front',
        ),
        SecureDetailImage(
          side: SecureDetailImageSide.back,
          localPath: '/private/back.png',
          fileName: 'back.png',
          mimeType: 'image/png',
          driveFileId: 'drive-back',
        ),
      ],
    );

    final restored = SecureDetail.fromMap(detail.toMap());

    expect(restored.fields, detail.fields);
    expect(restored.images, hasLength(2));
    expect(restored.images.first.side, SecureDetailImageSide.front);
    expect(restored.images.first.driveFileId, 'drive-front');
    expect(restored.images.last.side, SecureDetailImageSide.back);
    expect(restored.images.last.mimeType, 'image/png');
  });

  test('uses only the limited Drive file OAuth scope', () {
    expect(googleApiScopes, <String>[drive.DriveApi.driveFileScope]);
    expect(
      AuthService.isInsufficientScope(StateError('error="insufficient_scope"')),
      isTrue,
    );
  });

  test('secure details are retained only for the current session', () async {
    final store = RecentFileStore();
    const detail = SecureDetail(
      id: 'session-detail',
      type: SecureDetailType.bank,
      fields: <String, String>{'name': 'Shakil'},
      createdAtMillis: 1,
      updatedAtMillis: 1,
    );

    await store.saveSecureDetail(detail);

    expect(await store.listSecureDetails(), <SecureDetail>[detail]);
    expect(await RecentFileStore().listSecureDetails(), isEmpty);
  });

  test('uses a separate worksheet name for each secure detail type', () {
    const upi = SecureDetail(
      id: 'upi-id',
      type: SecureDetailType.upi,
      fields: <String, String>{'name': 'Shakil', 'upiId': 'shakil@upi'},
      createdAtMillis: 1,
      updatedAtMillis: 1,
    );
    const voterId = SecureDetail(
      id: 'voter-id',
      type: SecureDetailType.voterId,
      fields: <String, String>{'name': 'Shakil', 'voterIdNumber': 'ABC123'},
      createdAtMillis: 1,
      updatedAtMillis: 1,
    );

    expect(GoogleSheetsService.worksheetNameFor(upi), 'UPI');
    expect(GoogleSheetsService.worksheetNameFor(voterId), 'Voter ID');
  });

  test('category worksheets contain only field values', () {
    const detail = SecureDetail(
      id: 'upi-id',
      type: SecureDetailType.upi,
      fields: <String, String>{
        'name': 'Shakil',
        'upiId': 'shakil@upi',
        'mobileNumber': '8122702183',
      },
      createdAtMillis: 1,
      updatedAtMillis: 1,
    );
    const headers = <String>['Name', 'UPI ID', 'Mobile number'];

    expect(GoogleSheetsService.rowForDetail(detail, headers), <Object?>[
      'Shakil',
      'shakil@upi',
      '8122702183',
    ]);
  });
}
