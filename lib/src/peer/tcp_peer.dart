// import 'dart:io';

// import 'peer.dart';

// class TCPPeer extends Peer {
//   Socket _socket;
//   TCPPeer(String id, String localPeerId, Uri address, List<int> infoHashBuffer,
//       int piecesNum,
//       [this._socket])
//       : super(id, localPeerId, address, infoHashBuffer, piecesNum);

//   @override
//   Future<Stream> connectRemote(int timeout) async {
//     timeout ??= 30;
//     _socket ??= await Socket.connect(address.host, address.port,
//         timeout: Duration(seconds: timeout));
//     return _socket;
//   }

//   @override
//   void sendByteMessage(List<int> bytes) {
//     _socket?.add(bytes);
//   }

//   @override
//   Future dispose([reason]) async {
//     try {
//       await _socket?.close();
//       _socket = null;
//     } finally {
//       return super.dispose(reason);
//     }
//   }
// }
