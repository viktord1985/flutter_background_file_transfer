import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_transfer_platform_interface.dart';

/// An implementation of [BackgroundTransferPlatform] that uses method channels.
class MethodChannelBackgroundTransfer extends BackgroundTransferPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('background_transfer');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
