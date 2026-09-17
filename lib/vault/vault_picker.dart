import 'package:flutter/services.dart';

/// Windows native picker. Null is a normal user cancellation.
class VaultPicker {
  const VaultPicker();
  static const channel = MethodChannel('fptu_se_brain/vault');
  Future<String?> pickDirectory() => channel.invokeMethod<String>('pickDirectory');
}
