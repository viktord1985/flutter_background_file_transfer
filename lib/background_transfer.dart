
import 'background_transfer_platform_interface.dart';

class BackgroundTransfer {
  Future<String?> getPlatformVersion() {
    return BackgroundTransferPlatform.instance.getPlatformVersion();
  }
}
