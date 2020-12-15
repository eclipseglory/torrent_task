import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:torrent_client/src/file/download_file_manager.dart';
import 'package:torrent_client/src/file/state_file.dart';
import 'package:torrent_client/src/piece/base_piece_selector.dart';
import 'package:torrent_client/src/piece/piece_manager.dart';
import 'package:torrent_client/src/peer/tcp_peer.dart';
import 'package:torrent_client/src/torrent_download_communicator.dart';
import 'package:torrent_client/src/torrent_task.dart';
import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_tracker/torrent_tracker.dart';

const pstrlen = 19;
const pstr = 'BitTorrent protocol';
const reserved = [0, 0, 0, 0, 0, 0, 0, 0];
const HAND_SHAKE_HEAD = [
  19,
  66,
  105,
  116,
  84,
  111,
  114,
  114,
  101,
  110,
  116,
  32,
  112,
  114,
  111,
  116,
  111,
  99,
  111,
  108
];

var peers = <Uri>{};
void main() async {
  // 65.40574264526367MB
  // var startTime = DateTime.now().millisecondsSinceEpoch;
  var model = await Torrent.parse('example/test4.torrent');
  var task = TorrentTask.newTask(model, 'g:/bttest2/');
  task.start();

  // var peerId = generatePeerId();

  // var serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
  // serverSocket.listen((event) {
  //   print('!!!! event');
  // });

  // var provider = SimpleProvider(model.length, peerId, serverSocket.port);

  // var tracker = TorrentAnnounceTracker(
  //     model.announces.toList(), model.infoHashBuffer, provider);

  // var baseDirectory = 'g:/bttest';

  // var stateFile = await StateFile.getStateFile(baseDirectory, model);
  // provider.downloaded = stateFile.downloaded;
  // var startD = stateFile.downloaded;
  // var startU = stateFile.uploaded;
  // provider.left = model.length - stateFile.downloaded;
  // provider.uploaded = stateFile.uploaded;
  // print('下载：${model.name}');
  // print(
  //     '已经下载${stateFile.bitfield.completedPieces.length}个片段，共有${stateFile.bitfield.piecesNum}个片段');
  // print('下载:${provider.downloaded / (1024 * 1024)} mb');
  // print('上传:${provider.uploaded / (1024 * 1024)} mb');
  // print('剩余:${provider.left / (1024 * 1024)} mb');
  // var pieceManager = PieceManager.createPieceManager(
  //     BasePieceSelector(), model, stateFile.bitfield);

  // var fileManager = await DownloadFileManager.createFileManager(
  //     model, baseDirectory, stateFile);

  // fileManager.onAllComplete(() {
  //   tracker.complete();
  // });

  // var communicator =
  //     TorrentDownloadCommunicator(pieceManager, pieceManager, fileManager);

  // var peerSet = <String>[];
  // tracker.onPeerEvent((source, event) {
  //   event.peers.forEach((peer) {
  //     var id = 'TCP:${peer.host}:${peer.port}';
  //     if (peerSet.contains(id)) return;
  //     peerSet.add(id);
  //     var p =
  //         TCPPeer(id, peerId, peer, model.infoHashBuffer, model.pieces.length);
  //     communicator.hookPeer(p);
  //   });
  // });

  // tracker.onAllAnnounceOver((totalTrackers) {
  //   peerSet.clear();
  // });

  Timer.periodic(Duration(seconds: 10), (timer) {
    print(
        'download speed : ${task.downloadSpeed * 1000 / 1024} , upload speed : ${task.uploadSpeed * 1000 / 1024}');
  });

  // tracker.start();
}

Uint8List randomBytes(count) {
  var random = math.Random();
  var bytes = Uint8List(count);
  for (var i = 0; i < count; i++) {
    bytes[i] = random.nextInt(254);
  }
  return bytes;
}

String generatePeerId() {
  var r = randomBytes(9);
  var base64Str = base64Encode(r);
  var id = '-bDRLIN-' + base64Str;
  return id;
}

class SimpleProvider implements AnnounceOptionsProvider {
  int left;
  int downloaded = 0;
  int uploaded = 0;
  String peerId;
  int port;
  SimpleProvider(this.left, this.peerId, this.port);
  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': downloaded,
      'uploaded': uploaded,
      'left': left,
      'numwant': 50,
      'compact': 1,
      'peerId': peerId,
      'port': port
    };
    return Future.value(map);
  }
}
