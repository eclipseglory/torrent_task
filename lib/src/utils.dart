import 'dart:convert';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task/dtorrent_task.dart';

String generatePeerId([String prefix = ID_PREFIX]) {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = prefix + base64Str;
  return id;
}

List<int>? hexString2Buffer(String hexStr) {
  // ignore: prefer_is_empty
  if (hexStr.isEmpty || hexStr.length.remainder(2) != 0) return null;
  var size = hexStr.length ~/ 2;
  var re = <int>[];
  for (var i = 0; i < size; i++) {
    var s = hexStr.substring(i * 2, i * 2 + 2);
    var byte = int.parse(s, radix: 16);
    re.add(byte);
  }
  return re;
}

/// pow(2, 14)
///
/// download piece max size
const DEFAULT_REQUEST_LENGTH = 16384;

/// pow(2,17)
///
/// Remote is request piece length large or eqaul this length
/// , it must close the connection
const MAX_REQUEST_LENGTH = 131072;
