import 'dart:convert';
import 'dart:math';

import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_task/torrent_task.dart';

String generatePeerId([String prefix = ID_PREFIX]) {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = prefix + base64Str;
  return id;
}

/// return random int number , `0 - max`
///
/// [max] values  between 1 and (1<<32) inclusive.
int randomInt(int max) {
  return Random(DateTime.now().millisecond).nextInt(max);
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
