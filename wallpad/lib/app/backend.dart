import 'dart:io';

import '../features/belongings/tray_link.dart';
import '../features/belongings/tray_node.dart';
import '../device/broker.dart';
import '../core/data/database.dart';
import '../core/data/repository.dart';
import '../device/pir_sensor.dart';
import '../device/shelly_direct.dart';
import '../device/voice_memo.dart';
import '../core/config/constants.dart';
import '../device/power_link.dart';
import '../device/camera/vision.dart';
import '../device/doorcam/door_cam_link.dart';
import '../device/doorcam/door_cam_records.dart';
import '../device/doorcam/door_cam_server.dart';

// 이 경로가 있으면 보드, 없으면 PC 에서 예시 데이터로 돈다
final onBoard = Directory('/usr/atlas/apps').existsSync();

final vision = Vision();
final broker = Broker();
final trayLink = TrayLink();
final trayNode = TrayNode();
final powerLink = PowerLink();
final shellyDirect = ShellyDirect(shellyPlugs);

final voiceMemo = VoiceMemo();
final doorCamServer = DoorCamServer();
final doorCamLink = DoorCamLink();
final doorCamRecords = DoorCamRecords();
final pirSensor = PirSensor();
final database = AppDatabase();
final Repository repo = SqliteRepository(database);
