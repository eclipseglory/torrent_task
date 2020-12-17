import 'dart:io';
import 'dart:typed_data';

import 'package:torrent_client/src/utils.dart';
import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_tracker/torrent_tracker.dart';

import 'file/download_file_manager.dart';
import 'file/state_file.dart';
import 'peer/tcp_peer.dart';
import 'piece/base_piece_selector.dart';
import 'piece/piece_manager.dart';
import 'torrent_download_communicator.dart';

abstract class TorrentTask {
  factory TorrentTask.newTask(Torrent metaInfo, String savePath) {
    return _TorrentTask(metaInfo, savePath);
  }
  double get downloadSpeed;

  double get uploadSpeed;

  Future start();

  void stop();

  void pause();

  void resume();

  void delete();

  void addPeer(Uri host, Uri peer);
}

class _TorrentTask implements TorrentTask, AnnounceOptionsProvider {
  TorrentAnnounceTracker _tracker;

  StateFile _stateFile;

  PieceManager _pieceManager;

  DownloadFileManager _fileManager;

  TorrentDownloadCommunicator _communicator;

  Torrent _metaInfo;

  String _savePath;

  final Set<String> _peers = {};

  String _peerId;

  ServerSocket _serverSocket;

  Uint8List _infoHashBuffer;

  int _startTime = -1;

  int _startDownloaded = 0;

  int _startUploaded = 0;

  _TorrentTask(this._metaInfo, this._savePath) {
    _peerId = generatePeerId();
    _infoHashBuffer = _metaInfo.infoHashBuffer;
  }

  @override
  double get downloadSpeed {
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

  Future<TorrentDownloadCommunicator> init(
      Torrent model, String savePath) async {
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
    _communicator ??=
        TorrentDownloadCommunicator(_pieceManager, _pieceManager, _fileManager);
    return _communicator;
  }

  @override
  void addPeer(Uri host, Uri peer) {
    _tracker?.addPeer(host, peer, _metaInfo.infoHash);
  }

  void _whenTaskDownloadComplete() async {
    var results = await _tracker.complete();
    results.forEach((element) {
      print(element);
    });
    print('全部下载完毕');
  }

  void _whenFileDownloadComplete(String filePath) {}

  void _whenTrackerOverOneturn(int totalTrackers) {
    _peers.clear();
  }

  void _hookCommunicator(Tracker source, PeerEvent event) {
    var ps = event.peers;
    var piecesNum = _metaInfo.pieces.length;
    if (ps != null && ps.isNotEmpty) {
      ps.forEach((url) {
        var id = 'TCP:${url.host}:${url.port}';
        if (_peers.contains(id)) return;
        print('Try to connect peer : $id');
        _peers.add(id);
        var p = TCPPeer(id, _peerId, url, _infoHashBuffer, piecesNum);
        _communicator.hookPeer(p);
      });
    }
  }

  void _hookComeinPeer(Socket socket) {
    var id = 'TCP:${socket.address.host}:${socket.port}';
    print('New come in peer : $id');
    var piecesNum = _metaInfo.pieces.length;
    var p = TCPPeer(
        id,
        _peerId,
        Uri(host: socket.address.host, port: socket.port),
        _infoHashBuffer,
        piecesNum,
        socket);
    _communicator.hookPeer(p);
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
    _serverSocket.listen(_hookComeinPeer);
    await init(_metaInfo, _savePath);

    print('开始下载：${_metaInfo.name}');
    print(
        '已经下载${_stateFile.bitfield.completedPieces.length}个片段，共有${_stateFile.bitfield.piecesNum}个片段');
    print('下载:${_stateFile.downloaded / (1024 * 1024)} mb');
    print('上传:${_stateFile.uploaded / (1024 * 1024)} mb');
    print('剩余:${_metaInfo.length - _stateFile.downloaded / (1024 * 1024)} mb');
    // 主动访问的peer:
    _tracker.onPeerEvent(_hookCommunicator);
    _tracker.onAllAnnounceOver(_whenTrackerOverOneturn);
    _fileManager.onAllComplete(_whenTaskDownloadComplete);
    _fileManager.onFileWriteComplete(_whenFileDownloadComplete);
    _tracker.start(true);
    return Uri(host: _serverSocket.address.address, port: _serverSocket.port);
  }

  @override
  void stop([bool force = false]) {
    // _tracker?.stop(force);
    // _fileManager?.close();
  }

  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) {
    var map = {
      'downloaded': 0,//_stateFile?.downloaded,
      'uploaded': 0,//_stateFile?.uploaded,
      'left': _metaInfo.length,// - _stateFile.downloaded,
      'numwant': 50,
      'compact': 1,
      'peerId': _peerId,
      'port': _serverSocket?.port
    };
    return Future.value(map);
  }
}
