import 'dart:io';

import 'package:dbus/dbus.dart';

/// 카메라 권한이 없으면 스스로 승인한다 (appinfo.json 에 privileged.permission_agent 필요).
Future<bool> ensureCameraPermissions() async {
  const iface = 'com.atlas.PermissionAgent1';
  const permissions = [
    'com.atlas.permission.user_consent.cameradevice',
    'com.atlas.permission.user_consent.camerastream',
    'com.atlas.permission.user_consent.cameradescriptor',
    'com.atlas.permission.user_consent.cameracontrol',
  ];

  final client = DBusClient.system();
  final agent = DBusRemoteObject(client,
      name: 'com.atlas.PermissionAgent1', path: DBusObjectPath('/com/atlas/PermissionAgent1'));

  // 승인돼 있으면 빈 응답, 아니면 오류가 온다
  Future<bool> granted(String permission) async {
    try {
      await agent.callMethod(iface, 'CheckSelfUserConsentPermission', [DBusString(permission)]);
      return true;
    } catch (_) {
      return false;
    }
  }

  try {
    final missing = [for (final p in permissions) if (!await granted(p)) p];
    if (missing.isEmpty) return true;

    final uid = 'u0_a${await _processUid()}';
    for (final p in missing) {
      await agent.callMethod(iface, 'UpdateUserConsentPermission', [DBusString(uid), DBusString(p), DBusInt32(1)]);
    }
    for (final p in permissions) {
      if (!await granted(p)) return false;
    }
    return true;
  } catch (_) {
    return false;
  } finally {
    await client.close();
  }
}

Future<String> _processUid() async {
  final status = await File('/proc/self/status').readAsLines();
  return status.firstWhere((l) => l.startsWith('Uid:')).split(RegExp(r'\s+'))[1];
}
