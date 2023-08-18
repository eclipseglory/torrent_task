import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/src/piece/base_piece_selector.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';

class TorrentStream implements AnnounceOptionsProvider {
  static InternetAddress LOCAL_ADDRESS =
      InternetAddress.fromRawAddress(Uint8List.fromList([127, 0, 0, 1]));

  TorrentAnnounceTracker? _tracker;
  StateFile? _stateFile;

  PieceManager? _pieceManager;

  DownloadFileManager? _fileManager;

  PeersManager? _peersManager;

  final Torrent _metaInfo;

  final String _savePath;
  final Set<String> _peerIds = {};

  late String
      _peerId; // This is the generated local peer ID, which is different from the ID used in the Peer class.

  ServerSocket? _serverSocket;

  final Set<InternetAddress> _cominIp = {};

  bool _paused = false;
  late String _infoHashString;
  StreamController _fileStream = StreamController();
  Stream get fileStream => _fileStream.stream;

  void seek(int position) {
    if (position < 1 || position > _metaInfo.length) return;
    var pieceIndex = position ~/ _metaInfo.pieceLength;
    // _pieceManager
  }

  TorrentStream(this._metaInfo, this._savePath) {
    _peerId = generatePeerId();
  }
  final Set<void Function()> _taskCompleteHandlers = {};

  void _fireTaskComplete() {
    for (var element in _taskCompleteHandlers) {
      Timer.run(() => element());
    }
  }

  void addPeer(CompactAddress address, PeerSource source,
      {PeerType? type, Socket? socket}) {
    _peersManager?.addNewPeerAddress(address, source,
        type: type, socket: socket);
  }

  void _whenTaskDownloadComplete() async {
    await _peersManager
        ?.disposeAllSeeder('Download complete,disconnect seeder');
    await _tracker?.complete();
    _fireTaskComplete();
  }

  final Set<void Function(String filePath)> _fileCompleteHandlers = {};

  void _fireFileComplete(String filepath) {
    for (var handler in _fileCompleteHandlers) {
      Timer.run(() => handler(filepath));
    }
  }

  void _whenFileDownloadComplete(String filePath) {
    _fireFileComplete(filePath);
  }

  void _processTrackerPeerEvent(Tracker source, PeerEvent? event) {
    if (event == null) return;
    var ps = event.peers;
    if (ps.isNotEmpty) {
      for (var url in ps) {
        _processNewPeerFound(url, PeerSource.tracker);
      }
    }
  }

  void _processLSDPeerEvent(CompactAddress address, String infoHash) {
    print('There is LSD! !');
  }

  void _processNewPeerFound(CompactAddress url, PeerSource source) {
    log("Add new peer ${url.toString()} from ${source.name} to peersManager",
        name: runtimeType.toString());
    _peersManager?.addNewPeerAddress(url, source);
  }

  void _processDHTPeer(CompactAddress peer, String infoHash) {
    log("Got new peer from $peer DHT for infohash: ${Uint8List.fromList(infoHash.codeUnits).toHexString()}",
        name: runtimeType.toString());
    if (infoHash == _infoHashString) {
      _processNewPeerFound(peer, PeerSource.dht);
    }
  }

  void _hookInPeer(Socket socket) {
    if (socket.remoteAddress == LOCAL_ADDRESS) {
      socket.close();
      return;
    }
    if (_cominIp.length >= MAX_IN_PEERS || !_cominIp.add(socket.address)) {
      socket.close();
      return;
    }
    log('incoming connect: ${socket.remoteAddress.address}:${socket.remotePort}',
        name: runtimeType.toString());
    _peersManager?.addNewPeerAddress(
        CompactAddress(socket.remoteAddress, socket.remotePort),
        PeerSource.incoming,
        type: PeerType.TCP,
        socket: socket);
  }

  Future<PeersManager> _init(Torrent model, String savePath) async {
    _infoHashString = String.fromCharCodes(model.infoHashBuffer);
    _tracker ??= TorrentAnnounceTracker(this);
    _stateFile ??= await StateFile.getStateFile(savePath, model);
    _pieceManager ??= PieceManager.createPieceManager(
        BasePieceSelector(), model, _stateFile!.bitfield);
    _fileManager ??= await DownloadFileManager.createFileManager(
        model, savePath, _stateFile!);
    _peersManager ??= PeersManager(
        _peerId, _pieceManager!, _pieceManager!, _fileManager!, model);
    return _peersManager!;
  }

  Future start() async {
    // Incoming peer:
    _serverSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    await _init(_metaInfo, _savePath);
    _serverSocket?.listen(_hookInPeer);

    var map = {};
    map['name'] = _metaInfo.name;
    map['tcp_socket'] = _serverSocket?.port;
    map['comoplete_pieces'] = List.from(_stateFile!.bitfield.completedPieces);
    map['total_pieces_num'] = _stateFile!.bitfield.piecesNum;
    map['downloaded'] = _stateFile!.downloaded;
    map['uploaded'] = _stateFile!.uploaded;
    map['total_length'] = _metaInfo.length;
    // Outgoing peer:
    _tracker?.onPeerEvent(_processTrackerPeerEvent);
    _peersManager?.onAllComplete(_whenTaskDownloadComplete);
    _fileManager?.onFileComplete(_whenFileDownloadComplete);

    // _dht?.announce(
    //     String.fromCharCodes(_metaInfo.infoHashBuffer), _serverSocket!.port);
    // _dht?.onNewPeer(_processDHTPeer);
    // ignore: unawaited_futures
    // _dht?.bootstrap();
    if (_fileManager != null && _fileManager!.isAllComplete) {
      // ignore: unawaited_futures
      _tracker?.complete();
    } else {
      _tracker?.runTrackers(_metaInfo.announces, _metaInfo.infoHashBuffer,
          event: EVENT_STARTED);
    }
    return map;
  }

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': _stateFile?.downloaded,
      'uploaded': _stateFile?.uploaded,
      'left': _metaInfo.length - _stateFile!.downloaded,
      'numwant': 50,
      'compact': 1,
      'peerId': _peerId,
      'port': _serverSocket?.port
    };
    return Future.value(map);
  }
}
