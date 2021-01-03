import 'dart:convert';
import 'dart:math';
import 'package:dartorrent_common/dartorrent_common.dart';

import 'dart:typed_data';

String generatePeerId([String prefix = '-bDRLIN-']) {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = prefix + base64Str;
  return id;
}

// List<int> randomBytes(count) {
//   var random = Random();
//   var bytes = List<int>(count);
//   for (var i = 0; i < count; i++) {
//     bytes[i] = random.nextInt(254);
//   }
//   return bytes;
// }

/// return random int number , `0 - max`
///
/// [max] values  between 1 and (1<<32) inclusive.
int randomInt(int max) {
  return Random(DateTime.now().millisecond).nextInt(max);
}

Random createRandom() {
  return Random(DateTime.now().millisecond);
}

Uri parseAddress(List<int> message, [int offset = 0]) {
  var ip = '';
  for (var i = 0; i < 4; i++) {
    ip += message[i + offset].toString();
    if (i != 3) {
      ip += '.';
    }
  }
  var v = ByteData.view(Uint8List.fromList(message).buffer, 4 + offset, 2);
  var port = v.getUint16(0);
  return Uri(host: ip, port: port);
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
