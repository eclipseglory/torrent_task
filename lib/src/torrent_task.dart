import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:torrent_client/src/utils.dart';
import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_tracker/torrent_tracker.dart';

import 'file/download_file_manager.dart';
import 'file/state_file.dart';
import 'peer/peer.dart';
import 'peer/tcp_peer.dart';
import 'piece/base_piece_selector.dart';
import 'piece/piece_manager.dart';
import 'peer/peers_manager.dart';

const MAX_PEERS = 50;
const MAX_IN_PEERS = 10;

abstract class TorrentTask {
  factory TorrentTask.newTask(Torrent metaInfo, String savePath) {
    return _TorrentTask(metaInfo, savePath);
  }
  Future<double> get downloadSpeed;

  double get uploadSpeed;

  Future start();

  Future stop();

  Future complete();

  void pause();

  void resume();

  void delete();

  @Deprecated('This method is just for debug')
  void addPeer(Uri host, Uri peer);

  TorrentAnnounceTracker get tracker;
}

class _TorrentTask implements TorrentTask, AnnounceOptionsProvider {
  TorrentAnnounceTracker _tracker;

  bool _trackerRunning = false;

  StateFile _stateFile;

  PieceManager _pieceManager;

  DownloadFileManager _fileManager;

  PeersManager _peersManager;

  final Torrent _metaInfo;

  final String _savePath;

  final Set<String> _peerIds = {};

  String _peerId;

  ServerSocket _serverSocket;

  Uint8List _infoHashBuffer;

  int _startTime = -1;

  int _startDownloaded = 0;

  int _startUploaded = 0;

  final Set<String> _cominIp = {};

  _TorrentTask(this._metaInfo, this._savePath) {
    _peerId = generatePeerId();
    _infoHashBuffer = _metaInfo.infoHashBuffer;
  }

  @override
  Future<double> get downloadSpeed async {
    if (_startTime == null || _startTime <= 0) return 0.0;
    var passed = DateTime.now().millisecondsSinceEpoch - _startTime;
    return (_stateFile.downloaded - _startDownloaded) / passed;
  }

  @override
  double get uploadSpeed {
    if (_startTime == null || _startTime <= 0) return 0.0;
    var passed = DateTime.now().millisecondsSinceEpoch - _startTime;
    return (_stateFile.uploaded - _startUploaded) / passed;
  }

  Future<PeersManager> init(Torrent model, String savePath) async {
    _tracker ??=
        TorrentAnnounceTracker(model.announces.toList(), _infoHashBuffer, this);
    if (_stateFile == null) {
      _stateFile = await StateFile.getStateFile(savePath, model);
      _startDownloaded = _stateFile.downloaded;
      _startUploaded = _stateFile.uploaded;
    }
    _pieceManager ??= PieceManager.createPieceManager(
        BasePieceSelector(), model, _stateFile.bitfield);
    _fileManager ??= await DownloadFileManager.createFileManager(
        model, savePath, _stateFile);
    _peersManager ??=
        PeersManager(_pieceManager, _pieceManager, _fileManager, model);
    return _peersManager;
  }

  @override
  void addPeer(Uri host, Uri peer) {
    _tracker?.addPeer(host, peer, _metaInfo.infoHash);
  }

  void _whenTaskDownloadComplete() async {
    var results = await _tracker.complete();
    var peers = <Peer>{};
    peers.addAll(_peersManager.interestedPeers);
    peers.addAll(_peersManager.notInterestedPeers);
    peers.addAll(_peersManager.noResponsePeers);

    peers.forEach((peer) {
      if (peer.isSeeder) {
        peer.dispose('Download complete,disconnect seeder: ${peer.address}');
      }
    });

    // TODO DEBUG , need to remove later
    results.forEach((element) {
      print(element);
    });
    print('全部下载完毕');
  }

  void _whenFileDownloadComplete(String filePath) {
    print('$filePath 下载完成');
  }

  void _whenTrackerOverOneturn(int totalTrackers) {
    print('all tracker over');
    _trackerRunning = false;
    _peerIds.clear();
  }

  void _whenNoActivePeers() {
    if (_fileManager.isAllComplete) return;
    if (!_trackerRunning) {
      _trackerRunning = true;
      _tracker.restart();
    }
  }

  void _hookOutPeer(Tracker source, PeerEvent event) {
    var ps = event.peers;
    var piecesNum = _metaInfo.pieces.length;
    if (ps != null && ps.isNotEmpty) {
      ps.forEach((url) {
        var id = 'Out:${url.host}:${url.port}';
        if (_peerIds.contains(id)) return;
        _peerIds.add(id);
        var p = TCPPeer(id, _peerId, url, _infoHashBuffer, piecesNum);
        _connectPeer(p);
      });
    }
  }

  void _connectPeer(Peer p) {
    if (p == null) return;
    p.onDispose((source, [reason]) {
      var peer = source as Peer;
      var host = peer.address.host;
      _cominIp.remove(host);
    });
    _peersManager.hookPeer(p);
  }

  void _hookInPeer(Socket socket) {
    var id = 'In:${socket.address.host}:${socket.port}';
    if (_cominIp.length >= MAX_IN_PEERS) {
      socket.close();
      return;
    }
    if (_cominIp.add(socket.address.host)) {
      log('New come in peer : $id', name: runtimeType.toString());
      var piecesNum = _metaInfo.pieces.length;
      var p = TCPPeer(
          id,
          _peerId,
          Uri(host: socket.address.host, port: socket.port),
          _infoHashBuffer,
          piecesNum,
          socket);
      _connectPeer(p);
    } else {
      socket.close();
    }
  }

  @override
  void delete([bool deleteFiles = false]) {
    _tracker?.stop();
    if (deleteFiles) {
      _fileManager?.delete();
    } else {
      _stateFile?.delete();
    }
  }

  @override
  void pause() {
    // TODO: implement pause
  }

  @override
  void resume() {
    // TODO: implement resume
  }

  @override
  Future start() async {
    _startTime = DateTime.now().millisecondsSinceEpoch;
    // 进入的peer：
    _serverSocket ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    await init(_metaInfo, _savePath);
    _serverSocket.listen(_hookInPeer);

    print('开始下载：${_metaInfo.name} , ${_serverSocket.port}');
    print(
        '已经下载${_stateFile.bitfield.completedPieces.length}个片段，共有${_stateFile.bitfield.piecesNum}个片段');
    print('下载:${_stateFile.downloaded / (1024 * 1024)} mb');
    print('上传:${_stateFile.uploaded / (1024 * 1024)} mb');
    print(
        '剩余:${(_metaInfo.length - _stateFile.downloaded) / (1024 * 1024)} mb');
    // 主动访问的peer:
    _tracker.onPeerEvent(_hookOutPeer);
    _tracker.onAllAnnounceOver(_whenTrackerOverOneturn);
    _peersManager.onAllComplete(_whenTaskDownloadComplete);
    _peersManager.onNoActivePeerEvent(_whenNoActivePeers);
    _fileManager.onFileComplete(_whenFileDownloadComplete);

    if (_fileManager.localBitfield.completedPieces.length ==
        _fileManager.localBitfield.piecesNum) {
      try {
        return _tracker.complete();
      } catch (e) {
        log('Try to complete tracker error :',
            error: e, name: runtimeType.toString());
        return dispose();
      }
    } else {
      try {
        _trackerRunning = true;
        return _tracker.start(true);
      } catch (e) {
        log('Try to start tracker error :',
            error: e, name: runtimeType.toString());
        return dispose();
      }
    }
  }

  @override
  Future stop([bool force = false]) async {
    await _tracker?.stop(force);
    return dispose();
  }

  Future dispose() async {
    var l = <Future>[];
    _tracker.offPeerEvent(_hookOutPeer);
    _tracker.offAllAnnounceOver(_whenTrackerOverOneturn);
    _peersManager.offAllComplete(_whenTaskDownloadComplete);
    _fileManager.offFileComplete(_whenFileDownloadComplete);
    l.add(_tracker?.dispose());
    _tracker = null;
    l.add(_peersManager?.dispose());
    _peersManager = null;
    l.add(_fileManager?.close());
    _fileManager = null;

    _peerIds.clear();

    l.add(_serverSocket?.close());
    _serverSocket = null;
    _startTime = -1;
    _cominIp.clear();
    return Stream.fromFutures(l).toList();
  }

  @override
  Future complete() {
    // TODO: implement complete
    throw UnimplementedError();
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
}
