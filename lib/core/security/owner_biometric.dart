import 'package:local_auth/local_auth.dart';

class OwnerBiometric {
  OwnerBiometric._();

  static final LocalAuthentication _auth = LocalAuthentication();

  static Future<bool> confirmSensitiveAction({
    String reason = 'Confirm this owner action in Next',
  }) async {
    try {
      final supported = await _auth.isDeviceSupported();
      final canCheck = await _auth.canCheckBiometrics;
      if (!supported && !canCheck) return false;
      return _auth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}
