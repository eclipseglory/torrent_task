library torrent_task;

import 'dart:io';

export 'src/torrent_task_base.dart';
export 'src/file/file_base.dart';
export 'src/piece/piece_base.dart';
export 'src/peer/peer_base.dart';

/// Peer ID前缀
const ID_PREFIX = '-DT0201-';

/// 当前版本号
Future<String> getTorrenTaskVersion() async {
  var file = File('pubspec.yaml');
  if (await file.exists()) {
    var lines = await file.readAsLines();
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i];
      var strs = line.split(':');
      if (strs.length == 2) {
        var key = strs[0];
        var value = strs[1];
        if (key == 'version') return value;
      }
    }
  }
  return null;
}
