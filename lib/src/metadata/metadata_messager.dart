import 'package:b_encode_decode/b_encode_decode.dart';

mixin MetaDataMessager {
  List<int> createRequestMessage(int piece) {
    // {'msg_type': 0, 'piece': 0}
    var message = {};
    message['msg_type'] = 0;
    message['piece'] = piece;
    return encode(message);
  }

  List<int> createRejectMessage(int piece) {
    // {'msg_type': 2, 'piece': 0}
    var message = {};
    message['msg_type'] = 2;
    message['piece'] = piece;
    return encode(message);
  }

  List<int> createDataMessage(int piece, List<int> bytes) {
    // {'msg_type': 1, 'piece': 0 , 'total_size' : xxxx}xxxx
    var message = {};
    message['msg_type'] = 1;
    message['piece'] = piece;
    message['total_size'] = bytes.length;
    return encode(message);
  }
}
