import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await app.connect();
  } catch (e) {
    // DB 가 없어도 화면은 띄운다
    stderr.writeln('[app] DB 를 열지 못했다: $e');
  }
  runApp(const LeaveGuardApp());
}
