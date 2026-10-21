import 'package:flutter_test/flutter_test.dart';

// The app needs its full provider + router tree, so this package keeps a
// minimal smoke test here. Real coverage lives in the backend test suite.
void main() {
  test('harness works', () {
    expect(1 + 1, 2);
  });
}
