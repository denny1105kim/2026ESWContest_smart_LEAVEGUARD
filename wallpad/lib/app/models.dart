import 'dart:typed_data';

import 'package:flutter/material.dart';

class User {
  final String id;
  final String name;
  final Color color;
  bool calendarLinked;
  bool calendarNeedsReauth = false;

  User(this.id, this.name, this.color, {this.calendarLinked = false});

  String get initial => name.characters.first;
}

class Belonging {
  final String id;
  final List<String> userIds; // 둘 이상이면 공용
  final String name;
  final IconData icon;
  final int photos;
  final Uint8List? thumbnail;
  final bool hardToDetect; // 자동 박스가 못 잡아 직접 그려 등록했다

  Belonging(this.id, this.userIds, this.name, this.icon, {this.photos = 1, this.thumbnail, this.hardToDetect = false});

  bool ownedBy(String? userId) => userIds.contains(userId);
  bool get shared => userIds.length > 1;
}

class Appliance {
  final String id;
  final String name;
  final String room;
  final IconData icon;
  double currentA;
  bool on; // 전류 기준 사용 중 (릴레이만 켜진 것은 아니다)

  Appliance(this.id, this.name, this.room, this.icon, this.currentA) : on = currentA > 0.05;

  bool get isOn => on;
}

class CalendarEvent {
  final String time;
  final String title;

  const CalendarEvent(this.time, this.title);
}

class WeatherHour {
  final DateTime at;
  final int tempC, precipProb;
  final IconData icon;

  const WeatherHour({required this.at, required this.tempC, required this.precipProb, required this.icon});
}

class Weather {
  final String location;
  final int tempC, highC, lowC, precipProb;
  final IconData icon;
  final String label;
  final List<WeatherHour> hours; // 지금부터 18시간

  const Weather({
    required this.location,
    required this.tempC,
    required this.highC,
    required this.lowC,
    required this.precipProb,
    required this.icon,
    required this.label,
    this.hours = const [],
  });
}

enum EntryKind { weather, air, uv, essential, leftOut, note }

class ChecklistEntry {
  final String id;
  final String name;
  final EntryKind kind;
  final String reason;
  final IconData icon;

  const ChecklistEntry(this.id, this.name, this.kind, this.reason, this.icon);
}

class FamilyTodo {
  final String id;
  final String name;
  final String timeLabel;
  DateTime? doneAt;
  String? doneBy;

  FamilyTodo(this.id, this.name, this.timeLabel);

  bool get done => doneAt != null;
}

enum Prompt { none, skip, lastOut, groupPick, groupEnd }

// confirming = 얼굴이 쌓여 누군지 확인 중
enum DoorPhase { idle, confirming, known, unknown }
