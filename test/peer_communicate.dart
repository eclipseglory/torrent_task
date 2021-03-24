import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_task/torrent_task.dart';

void main() async {
  ServerSocket serverSocket;
  int serverPort;
  var infoBuffer = randomBytes(20);
  var piecesNum = 20;
  var bitfield = Bitfield.createEmptyBitfield(piecesNum);
  bitfield.setBit(10, true);
  var callMap = <String, bool>{
    'connect1': false,
    'handshake1': false,
    'connect2': false,
    'handshake2': false,
    'choke': false,
    'interested': false,
    'bitfield': false,
    'have': false,
    'request': false,
    'piece': false,
    'port': false,
    'have_all': false,
    'have_none': false,
    'keep_live': false,
    'cancel': false,
    'reject_request': false,
    'allow_fast': false,
    'suggest_piece': false
  };
  serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  serverPort = serverSocket.port;
  serverSocket.listen((socket) {
    print('client connected : ${socket.address}:${socket.port}');
    var peer = Peer.newTCPPeer(
        generatePeerId(),
        CompactAddress(socket.address, socket.port),
        infoBuffer,
        piecesNum,
        socket);
    peer.onConnect((peer) {
      callMap['connect1'] = true;
      peer.sendHandShake();
    });
    peer.onHandShake((peer, remotePeerId, data) {
      callMap['handshake1'] = true;
      print('receive ${remotePeerId} handshake');
      peer.sendInterested(true);
      print('send interested to $remotePeerId');
    });
    peer.onBitfield((peer, bitfield) {
      assert(bitfield.getBit(10));
      print('receive client bitfield');
      callMap['bitfield'] = true;
    });
    peer.onInterestedChange((peer, interested) {
      callMap['interested'] = true;
      print('receive client interested');
      peer.sendChoke(false);
      print('send choke false to client');
    });
    peer.onChokeChange((peer, choke) {
      callMap['choke'] = true;
      print('receive client choke change');
    });
    peer.onRequest((p, index, begin, length) {
      callMap['request'] = true;
      assert(begin == 0);
      assert(length == DEFAULT_REQUEST_LENGTH);
      if (index == 1) {
        peer.sendRejectRequest(index, begin, DEFAULT_REQUEST_LENGTH);
      }
    });
    peer.onCancel((peer, index, begin, length) {
      callMap['cancel'] = true;
      assert(index == 1);
      assert(begin == 0);
      assert(length == DEFAULT_REQUEST_LENGTH);
      print('receive client cancel');
    });
    peer.onPortChange((peer, port) {
      callMap['port'] = true;
      assert(port == 3321);
      print('receive client onPortChange');
    });
    peer.onHave((peer, index) {
      callMap['have'] = true;
      assert(index[0] == 2);
      print('receive client have');
    });
    peer.onKeepalive((peer) {
      callMap['keep_live'] = true;
    });
    peer.onHaveAll((peer) {
      callMap['have_all'] = true;
      print('receive client have all');
    });
    peer.onHaveNone((peer) {
      callMap['have_none'] = true;
      print('receive client have none');
    });
    peer.onSuggestPiece((peer, index) {
      assert(index == 3);
      callMap['suggest_piece'] = true;
      peer.sendRequest(index, 0);
      print('receive client suggest');
    });

    peer.onAllowFast((peer, index) {
      assert(index == 4);
      callMap['allow_fast'] = true;
      Timer.run(() => peer.sendRequest(index, 0));
      print('receive client allow fast');
    });
    peer.onPiece((p, index, begin, block) async {
      callMap['piece'] = true;
      assert(block.length == DEFAULT_REQUEST_LENGTH);
      assert(block[0] == index);
      assert(block[1] == begin);
      var id = String.fromCharCodes(block.getRange(2, 22));
      assert(id == peer.remotePeerId);
      if (index == 4) {
        print('测试完毕 $callMap');
        await peer.dispose(BadException('测试完成'));
      }
    });
    peer.onDispose((peer, [reason]) async {
      print('come in destroyed : $reason');
      await serverSocket?.close();
      serverSocket = null;
    });
    peer.connect();
  });

  var pid = generatePeerId();
  var peer = Peer.newTCPPeer(
      pid,
      CompactAddress(InternetAddress.tryParse('127.0.0.1'), serverPort),
      infoBuffer,
      piecesNum,
      null);
  peer.onConnect((peer) {
    callMap['connect2'] = true;
    print('connect server success');
    peer.sendHandShake();
    // peer.dispose();
  });
  peer.onHandShake((peer, remotePeerId, data) {
    callMap['handshake2'] = true;
    print('receive ${remotePeerId} handshake');
    peer.sendBitfield(bitfield);
    print('send bitfield to server');
    peer.sendInterested(true);
    print('send interseted true to server');
    peer.sendChoke(false);
    print('send choke false to server');
  });
  peer.onChokeChange((peer, choke) {
    if (!choke) {
      peer.sendRequest(1, 0);
      peer.requestCancel(1, 0, DEFAULT_REQUEST_LENGTH);
      peer.sendRequest(1, 0);
      peer.sendHave(2);
      peer.sendKeeplive();
      peer.sendPortChange(3321);
      peer.sendHaveAll();
      peer.sendHaveNone();
      peer.sendSuggestPiece(3);
    }
  });
  peer.onRejectRequest((peer, index, begin, length) {
    assert(index == 1);
    assert(begin == 0);
    assert(length == DEFAULT_REQUEST_LENGTH);
    callMap['reject_request'] = true;
  });
  peer.onRequest((peer, index, begin, length) {
    var content = Uint8List(DEFAULT_REQUEST_LENGTH);
    var view = ByteData.view(content.buffer);
    view.setUint8(0, index);
    view.setUint8(1, begin);
    var id = peer.localPeerId;
    var idcontent = utf8.encode(id);
    for (var i = 0; i < idcontent.length; i++) {
      view.setUint8(i + 2, idcontent[i]);
    }
    peer.sendPiece(index, begin, content);
    peer.sendChoke(true); // 测试allow fast
    peer.sendAllowFast(4);
  });
  peer.onDispose((peer, [reason]) async {
    print('come out destroyed : $reason');
    await serverSocket?.close();
    serverSocket = null;
    var callAll = callMap.values
        .fold(true, (previousValue, element) => (previousValue && element));
    assert(callAll);
  });
  print('connect to : ${peer.address}');
  await peer.connect();
}
