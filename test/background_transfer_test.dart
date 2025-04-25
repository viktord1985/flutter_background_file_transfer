import 'package:flutter_test/flutter_test.dart';
import 'package:background_transfer/background_transfer.dart';
import 'package:background_transfer/background_transfer_platform_interface.dart';
import 'package:background_transfer/background_transfer_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBackgroundTransferPlatform
    with MockPlatformInterfaceMixin
    implements BackgroundTransferPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BackgroundTransferPlatform initialPlatform = BackgroundTransferPlatform.instance;

  test('$MethodChannelBackgroundTransfer is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBackgroundTransfer>());
  });

  test('getPlatformVersion', () async {
    BackgroundTransfer backgroundTransferPlugin = BackgroundTransfer();
    MockBackgroundTransferPlatform fakePlatform = MockBackgroundTransferPlatform();
    BackgroundTransferPlatform.instance = fakePlatform;

    expect(await backgroundTransferPlugin.getPlatformVersion(), '42');
  });
}
