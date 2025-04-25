import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'background_transfer_method_channel.dart';

abstract class BackgroundTransferPlatform extends PlatformInterface {
  /// Constructs a BackgroundTransferPlatform.
  BackgroundTransferPlatform() : super(token: _token);

  static final Object _token = Object();

  static BackgroundTransferPlatform _instance = MethodChannelBackgroundTransfer();

  /// The default instance of [BackgroundTransferPlatform] to use.
  ///
  /// Defaults to [MethodChannelBackgroundTransfer].
  static BackgroundTransferPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BackgroundTransferPlatform] when
  /// they register themselves.
  static set instance(BackgroundTransferPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
