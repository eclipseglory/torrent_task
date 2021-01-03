import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_tracker/torrent_tracker.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:dht_dart/dht_dart.dart';

import 'file/download_file_manager.dart';
import 'file/state_file.dart';
import 'peer/peer.dart';
import 'piece/base_piece_selector.dart';
import 'piece/piece_manager.dart';
import 'peer/peers_manager.dart';
import 'utils.dart';

const MAX_PEERS = 50;
const MAX_IN_PEERS = 10;

abstract class TorrentTask {
  factory TorrentTask.newTask(Torrent metaInfo, String savePath) {
    return _TorrentTask(metaInfo, savePath);
  }

  void startAnnounceUrl(Uri url, Uint8List infoHash);

  int get allPeersNumber;

  int get connectedPeersNumber;

  int get seederNumber;

  double get downloadSpeed;

  double get uploadSpeed;

  /// Downloaded total bytes length
  int get downloaded;

  /// Downloaded percent
  double get progress;

  Future start();

  Future stop();

  bool get isPaused;

  void pause();

  void resume();

  // Future deleteTask();

  // Future deleteTaskAndFiles();

  bool onTaskComplete(void Function() handler);

  bool offTaskComplete(void Function() handler);

  bool onFileComplete(void Function(String filepath) handler);

  bool offFileComplete(void Function(String filepath) handler);

  bool onStop(void Function() handler);

  bool offStop(void Function() handler);

  bool onPause(void Function() handler);

  bool offPause(void Function() handler);

  bool onResume(void Function() handler);

  bool offResume(void Function() handler);

  /// 增加DHT node，一般是将torrent文件中的nodes加入进去。
  ///
  /// 当然也可以直接添加已知的node地址
  void addDHTNode(Uri uri);

  @Deprecated('This method is just for debug')
  void addPeer(Uri peer, [Uri trackerHost]);

  @Deprecated('This property is just for debug')
  TorrentAnnounceTracker get tracker;
}

class _TorrentTask implements TorrentTask, AnnounceOptionsProvider {
  final Set<void Function()> _taskCompleteHandlers = {};

  final Set<void Function(String filePath)> _fileCompleteHandlers = {};

  final Set<void Function()> _stopHandlers = {};

  final Set<void Function()> _resumeHandlers = {};

  final Set<void Function()> _pauseHandlers = {};

  TorrentAnnounceTracker _tracker;

  DHT _dht;

  StateFile _stateFile;

  PieceManager _pieceManager;

  DownloadFileManager _fileManager;

  PeersManager _peersManager;

  final Torrent _metaInfo;

  final String _savePath;

  final Set<String> _peerIds = {};

  String _peerId; // 这个是生成的本地peer的id，和Peer类的id是两回事

  ServerSocket _serverSocket;

  final Set<String> _cominIp = {};

  bool _paused = false;

  _TorrentTask(this._metaInfo, this._savePath) {
    _peerId = generatePeerId();
  }

  @override
  double get downloadSpeed {
    if (_peersManager != null) {
      return _peersManager.downloadSpeed;
    } else {
      return 0.0;
    }
  }

  @override
  double get uploadSpeed {
    if (_peersManager != null) {
      return _peersManager.uploadSpeed;
    } else {
      return 0.0;
    }
  }

  String _infoHashString;

  Future<PeersManager> _init(Torrent model, String savePath) async {
    _dht = DHT();
    _infoHashString = String.fromCharCodes(model.infoHashBuffer);
    _tracker ??= TorrentAnnounceTracker(this);
    _stateFile ??= await StateFile.getStateFile(savePath, model);
    _pieceManager ??= PieceManager.createPieceManager(
        BasePieceSelector(), model, _stateFile.bitfield);
    _fileManager ??= await DownloadFileManager.createFileManager(
        model, savePath, _stateFile);
    _peersManager ??= PeersManager(
        _peerId, _pieceManager, _pieceManager, _fileManager, model);
    return _peersManager;
  }

  @override
  void addPeer(Uri peer, [Uri trackerHost]) {}

  void _whenTaskDownloadComplete() async {
    await _peersManager.disposeAllSeeder('Download complete,disconnect seeder');
    await _tracker.runTrackers(_metaInfo.announces, _metaInfo.infoHashBuffer,
        event: EVENT_COMPLETED);
    _fireTaskComplete();
  }

  void _whenFileDownloadComplete(String filePath) {
    _fireFileComplete(filePath);
  }

  @Deprecated('useless')
  void _whenNoActivePeers() {
    // if (_fileManager != null && _fileManager.isAllComplete) return;
    // if (!_trackerRunning) {
    //   _trackerRunning = true;
    //   try {
    //     _tracker?.restartAll();
    //   } finally {}
    // }
  }

  void _processTrackerPeerEvent(Tracker source, PeerEvent event) {
    var ps = event.peers;
    if (ps != null && ps.isNotEmpty) {
      ps.forEach((url) {
        _processNewPeerFound(url);
      });
    }
  }

  void _processNewPeerFound(CompactAddress url) {
    _peersManager.addNewPeerAddress(url);
  }

  void _processDHTPeer(CompactAddress peer, String infoHash) {
    if (infoHash == _infoHashString) {
      _processNewPeerFound(peer);
    }
  }

  void _hookInPeer(Socket socket) {
    if (_cominIp.length >= MAX_IN_PEERS ||
        !_cominIp.add(socket.address.address)) {
      socket.close();
      return;
    }
    _peersManager.addNewPeerAddress(
        CompactAddress(socket.address, socket.port), PeerType.TCP, socket);
  }

  @override
  void pause() {
    if (_paused) return;
    _paused = true;
    _peersManager?.pause();
    _fireTaskPaused();
  }

  @override
  bool get isPaused => _paused;

  @override
  void resume() {
    if (isPaused) {
      _paused = false;
      _peersManager?.resume();
      _fireTaskResume();
    }
  }

  @override
  Future start() async {
    // 进入的peer：
    _serverSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    await _init(_metaInfo, _savePath);
    _serverSocket.listen(_hookInPeer);
    var map = {};
    map['name'] = _metaInfo.name;
    map['tcp_socket'] = _serverSocket.port;
    map['comoplete_pieces'] = List.from(_stateFile.bitfield.completedPieces);
    map['total_pieces_num'] = _stateFile.bitfield.piecesNum;
    map['downloaded'] = _stateFile.downloaded;
    map['uploaded'] = _stateFile.uploaded;
    map['total_length'] = _metaInfo.length;
    // 主动访问的peer:
    _tracker.onPeerEvent(_processTrackerPeerEvent);
    _peersManager.onAllComplete(_whenTaskDownloadComplete);
    _peersManager.onNoActivePeerEvent(_whenNoActivePeers);
    _fileManager.onFileComplete(_whenFileDownloadComplete);
    _dht.announce(
        String.fromCharCodes(_metaInfo.infoHashBuffer), _serverSocket.port);
    _dht.onNewPeer(_processDHTPeer);
    // ignore: unawaited_futures
    _dht.bootstrap();

    if (_fileManager.isAllComplete) {
      _tracker.runTrackers(_metaInfo.announces, _metaInfo.infoHashBuffer,
          event: EVENT_COMPLETED);
    } else {
      _tracker.runTrackers(_metaInfo.announces, _metaInfo.infoHashBuffer,
          event: EVENT_STARTED);
    }
    return map;
  }

  @override
  Future stop([bool force = false]) async {
    await _tracker?.stop(force);
    var tempHandler = Set<Function>.from(_stopHandlers);
    await dispose();
    tempHandler.forEach((element) {
      Timer.run(() => element());
    });
    tempHandler.clear();
    tempHandler = null;
  }

  Future dispose() async {
    _fileCompleteHandlers.clear();
    _taskCompleteHandlers.clear();
    _pauseHandlers.clear();
    _resumeHandlers.clear();
    _stopHandlers.clear();
    _tracker?.offPeerEvent(_processTrackerPeerEvent);
    _peersManager?.offAllComplete(_whenTaskDownloadComplete);
    _fileManager?.offFileComplete(_whenFileDownloadComplete);
    // 这是有顺序的,先停止tracker运行,然后停止监听serversocket以及所有的peer,最后关闭文件系统
    await _tracker?.dispose();
    _tracker = null;
    await _peersManager?.dispose();
    _peersManager = null;
    await _serverSocket?.close();
    _serverSocket = null;
    await _fileManager?.close();
    _fileManager = null;
    await _dht?.stop();
    _dht = null;

    _peerIds.clear();
    _cominIp.clear();
    return;
  }

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': _stateFile?.downloaded,
      'uploaded': _stateFile?.uploaded,
      'left': _metaInfo.length - _stateFile.downloaded,
      'numwant': 50,
      'compact': 1,
      'peerId': _peerId,
      'port': _serverSocket?.port
    };
    return Future.value(map);
  }

  @override
  TorrentAnnounceTracker get tracker => _tracker;

  @override
  bool offFileComplete(void Function(String filepath) handler) {
    return _fileCompleteHandlers.remove(handler);
  }

  void _fireFileComplete(String filepath) {
    _fileCompleteHandlers.forEach((handler) {
      Timer.run(() => handler(filepath));
    });
  }

  @override
  bool offPause(void Function() handler) {
    return _pauseHandlers.remove(handler);
  }

  @override
  bool offResume(void Function() handler) {
    return _resumeHandlers.remove(handler);
  }

  @override
  bool offStop(void Function() handler) {
    return _stopHandlers.remove(handler);
  }

  @override
  bool offTaskComplete(void Function() handler) {
    return _taskCompleteHandlers.remove(handler);
  }

  @override
  bool onFileComplete(void Function(String filepath) handler) {
    return _fileCompleteHandlers.add(handler);
  }

  @override
  bool onPause(void Function() handler) {
    return _pauseHandlers.add(handler);
  }

  @override
  bool onResume(void Function() handler) {
    return _resumeHandlers.add(handler);
  }

  @override
  bool onStop(void Function() handler) {
    return _stopHandlers.add(handler);
  }

  @override
  bool onTaskComplete(void Function() handler) {
    return _taskCompleteHandlers.add(handler);
  }

  void _fireTaskComplete() {
    _taskCompleteHandlers.forEach((element) {
      Timer.run(() => element());
    });
  }

  @override
  int get downloaded => _fileManager?.downloaded;

  @override
  double get progress {
    var d = downloaded;
    if (d == null) return 0.0;
    var l = _metaInfo?.length;
    if (l == null) return 0.0;
    return d / l;
  }

  void _fireTaskPaused() {
    _pauseHandlers.forEach((element) {
      Timer.run(() => element());
    });
  }

  void _fireTaskResume() {
    _resumeHandlers.forEach((element) {
      Timer.run(() => element());
    });
  }

  @override
  int get allPeersNumber {
    if (_peersManager != null) {
      return _peersManager.peersNumber;
    } else {
      return 0;
    }
  }

  @override
  void addDHTNode(Uri url) {
    _dht?.addBootstrapNode(url);
  }

  @override
  int get connectedPeersNumber {
    if (_peersManager != null) {
      return _peersManager.connectedPeersNumber;
    } else {
      return 0;
    }
  }

  int get seederNumber {
    if (_peersManager != null) {
      return _peersManager.seederNumber;
    } else {
      return 0;
    }
  }

  @override
  void startAnnounceUrl(Uri url, Uint8List infoHash) {
    _tracker?.runTracker(url, infoHash);
  }
}
