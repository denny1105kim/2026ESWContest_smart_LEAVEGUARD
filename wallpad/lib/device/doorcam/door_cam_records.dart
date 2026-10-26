import 'dart:io';
import 'dart:typed_data';

/// 현관 카메라 캐시 파일: 최신 프레임, 판정 로그, 모르는 사람 사진. 실패해도 무시한다.
class DoorCamRecords {
  DoorCamRecords({String? dir}) : dir = dir ?? Platform.environment['XDG_CACHE_HOME'] ?? '/tmp';

  final String dir;

  static const keepVisitors = 20;

  String framePath(String device) => '$dir/doorcam_$device.jpg';

  Future<void> writeFrame(String device, Uint8List jpeg) => File(framePath(device)).writeAsBytes(jpeg);

  void log(String line) {
    try {
      final now = DateTime.now().toIso8601String().substring(11, 19);
      File('$dir/doorcam.log').writeAsStringSync('$now $line\n', mode: FileMode.append);
    } catch (_) {}
  }

  void saveVisitor(Uint8List jpeg) {
    try {
      final folder = Directory('$dir/visitors')..createSync(recursive: true);
      final stamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
      File('${folder.path}/$stamp.jpg').writeAsBytesSync(jpeg);
      final files = folder.listSync().whereType<File>().toList()..sort((a, b) => a.path.compareTo(b.path));
      for (var i = 0; i < files.length - keepVisitors; i++) {
        files[i].deleteSync();
      }
    } catch (_) {}
  }
}
