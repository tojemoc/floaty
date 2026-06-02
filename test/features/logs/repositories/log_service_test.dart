import 'package:floaty/features/logs/repositories/log_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogService.redactSensitiveLogData', () {
    test('redacts common auth tokens and cookies', () {
      const input =
          'Authorization: Bearer abc123 token=secret accessToken=abc sails.sid=session-cookie';

      final redacted = LogService.redactSensitiveLogData(input);

      expect(redacted, isNot(contains('abc123')));
      expect(redacted, isNot(contains('secret')));
      expect(redacted, isNot(contains('session-cookie')));
      expect(redacted, contains('Authorization: [REDACTED]'));
      expect(redacted, contains('token= [REDACTED]'));
      expect(redacted, contains('sails.sid= [REDACTED]'));
    });
  });
}
