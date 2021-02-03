import 'dart:async';
import 'dart:io';

import 'package:torrent_model/torrent_model.dart';
import 'package:dartorrent_common/dartorrent_common.dart';

import 'bitfield.dart';
import 'peer.dart';
import '../file/download_file_manager.dart';
import '../piece/piece_manager.dart';
import '../piece/piece.dart';
import '../piece/piece_provider.dart';
import '../utils.dart';
import '../peer/pex.dart';
import '../peer/holepunch.dart';

const MAX_ACTIVE_PEERS = 50;

const MAX_WRITE_BUFFER_SIZE = 10 * 1024 * 1024;

const MAX_UPLOADED_NOTIFY_SIZE = 1024 * 1024 * 10; // 10 mb

///
/// TODO:
/// - 没有处理对外的Suggest Piece/Fast Allow
class PeersManager with Holepunch, PEX {
  final List<InternetAddress> IGNORE_IPS = [
    InternetAddress.tryParse('0.0.0.0'),
    InternetAddress.tryParse('127.0.0.1')
  ];

  bool _disposed = false;

  bool get isDisposed => _disposed;

  final Set<Peer> _activePeers = {};

  final Set<CompactAddress> _peersAddress = {};

  final Set<InternetAddress> _incomingAddress = {};

  InternetAddress localExtenelIP;

  /// 写入磁盘的缓存最大值
  int maxWriteBufferSize;

  final _flushIndicesBuffer = <int>{};

  final Set<void Function()> _allcompletehandles = {};

  final Set<void Function()> _noActivePeerhandles = {};

  final Torrent _metaInfo;

  int _uploaded = 0;

  int _downloaded = 0;

  int _startedTime;

  int _endTime;

  int _uploadedNotifySize = 0;

  final List<List> _remoteRequest = [];

  final DownloadFileManager _fileManager;

  final PieceProvider _pieceProvider;

  final PieceManager _pieceManager;

  bool _paused = false;

  Timer _keepAliveTimer;

  final List _pausedRequest = [];

  final Map<String, List> _pausedRemoteRequest = {};

  final String _localPeerId;

  PeersManager(this._localPeerId, this._pieceManager, this._pieceProvider,
      this._fileManager, this._metaInfo,
      [this.maxWriteBufferSize = MAX_WRITE_BUFFER_SIZE]) {
    assert(_pieceManager != null &&
        _pieceProvider != null &&
        _fileManager != null);
    // hook FileManager and PieceManager
    _fileManager.onSubPieceWriteComplete(_processSubPieceWriteComplte);
    _fileManager.onSubPieceReadComplete(readSubPieceComplete);
    _pieceManager.onPieceComplete(_processPieceWriteComplete);

    // Start pex interval
    startPEX();
  }

  /// Task is paused
  bool get isPaused => _paused;

  /// All peers number. Include the connecting peer.
  int get peersNumber {
    if (_peersAddress == null || _peersAddress.isEmpty) return 0;
    return _peersAddress.length;
  }

  /// All connected peers number. Include seeder.
  int get connectedPeersNumber {
    if (_activePeers == null || _activePeers.isEmpty) return 0;
    return _activePeers.length;
  }

  /// All seeder number
  int get seederNumber {
    if (_activePeers == null || _activePeers.isEmpty) return 0;
    var c = 0;
    return _activePeers.fold(c, (previousValue, element) {
      if (element.isSeeder) {
        return previousValue + 1;
      }
      return previousValue;
    });
  }

  /// Since first peer connected to end time ,
  ///
  /// The end time is current, but once `dispose` this class
  /// the end time is when manager was disposed.
  int get liveTime {
    if (_startedTime == null) return 0;
    var passed = DateTime.now().millisecondsSinceEpoch - _startedTime;
    if (_endTime != null) {
      passed = _endTime - _startedTime;
    }
    return passed;
  }

  /// Average download speed , b/ms
  ///
  /// This speed caculation : `total download content bytes` / [liveTime]
  double get averageDownloadSpeed {
    var live = liveTime;
    if (live == 0) return 0.0;
    return _downloaded / live;
  }

  /// Average upload speed , b/ms
  ///
  /// This speed caculation : `total upload content bytes` / [liveTime]
  double get averageUploadSpeed {
    var live = liveTime;
    if (live == 0) return 0.0;
    return _uploaded / live;
  }

  /// Current download speed , b/ms
  ///
  /// This speed caculation: sum(`active peer download speed`)
  double get currentDownloadSpeed {
    if (_activePeers == null || _activePeers.isEmpty) return 0.0;
    return _activePeers.fold(
        0.0, (p, element) => p + element.currentDownloadSpeed);
  }

  /// Current upload speed , b/ms
  ///
  /// This speed caculation: sum(`active peer upload speed`)
  double get uploadSpeed {
    if (_activePeers == null || _activePeers.isEmpty) return 0.0;
    return _activePeers.fold(
        0.0, (p, element) => p + element.averageUploadSpeed);
  }

  void _hookPeer(Peer peer) {
    if (peer.address.address == localExtenelIP) return;
    if (_peerExsist(peer)) return;
    peer.onDispose(_processPeerDispose);
    peer.onBitfield(_processBitfieldUpdate);
    peer.onHaveAll(_processHaveAll);
    peer.onHaveNone(_processHaveNone);
    peer.onHandShake(_processPeerHandshake);
    peer.onChokeChange(_processChokeChange);
    peer.onInterestedChange(_processInterestedChange);
    peer.onConnect(_peerConnected);
    peer.onHave(_processHaveUpdate);
    peer.onPiece(_processReceivePiece);
    peer.onRequest(_processRemoteRequest);
    peer.onRequestTimeout(_processRequestTimeout);
    peer.onSuggestPiece(_processSuggestPiece);
    peer.onRejectRequest(_processRejectRequest);
    peer.onAllowFast(_processAllowFast);
    peer.onExtendedEvent(_processExtendedMessage);
    _registerExtended(peer);
    peer.connect();
  }

  /// 支持哪些扩展在这里添加
  void _registerExtended(Peer peer) {
    peer.registerExtened('ut_pex');
    peer.registerExtened('ut_holepunch');
  }

  void unHookPeer(Peer peer) {
    if (peer == null) return;
    peer.offDispose(_processPeerDispose);
    peer.offBitfield(_processBitfieldUpdate);
    peer.offHaveAll(_processHaveAll);
    peer.offHaveNone(_processHaveNone);
    peer.offHandShake(_processPeerHandshake);
    peer.offChokeChange(_processChokeChange);
    peer.offInterestedChange(_processInterestedChange);
    peer.offConnect(_peerConnected);
    peer.offHave(_processHaveUpdate);
    peer.offPiece(_processReceivePiece);
    peer.offRequest(_processRemoteRequest);
    peer.offRequestTimeout(_processRequestTimeout);
    peer.offRejectRequest(_processRejectRequest);
    peer.offAllowFast(_processAllowFast);
    peer.offExtendedEvent(_processExtendedMessage);
  }

  bool _peerExsist(Peer id) {
    return _activePeers.contains(id);
  }

  void _processExtendedMessage(dynamic source, String name, dynamic data) {
    if (name == 'ut_holepunch') {
      parseHolepuchMessage(data);
    }
    if (name == 'ut_pex') {
      parsePEXDatas(source, data);
    }
    if (name == 'handshake') {
      if (localExtenelIP != null &&
          data['yourip'] != null &&
          (data['yourip'].length == 4 || data['yourip'].length == 16)) {
        InternetAddress myip;
        try {
          myip = InternetAddress.fromRawAddress(data['yourip']);
        } catch (e) {
          return;
        }
        if (IGNORE_IPS.contains(myip)) return;
        localExtenelIP = InternetAddress.fromRawAddress(data['yourip']);
      }
    }
  }

  /// Add a new peer [address] , the default [type] is `PeerType.TCP`,
  /// [socket] is null.
  ///
  /// Usually [socket] is null , unless this peer was incoming connection, but
  /// this type peer was managed by [TorrentTask] , user don't need to know that.
  void addNewPeerAddress(CompactAddress address,
      [PeerType type = PeerType.TCP, Socket socket]) {
    if (address == null) return;
    if (address.address == localExtenelIP) return;
    if (socket != null) {
      // 说明是主动连接的peer,目前只允许一个ip连一次
      if (!_incomingAddress.add(address.address)) {
        return;
      }
    }
    if (_peersAddress.add(address)) {
      Peer peer;
      if (type == PeerType.TCP) {
        peer = Peer.newTCPPeer(_localPeerId, address, _metaInfo.infoHashBuffer,
            _metaInfo.pieces.length, socket);
      }
      if (type == PeerType.UTP) {
        peer = Peer.newUTPPeer(_localPeerId, address, _metaInfo.infoHashBuffer,
            _metaInfo.pieces.length, socket);
      }
      if (peer != null) _hookPeer(peer);
    }
  }

  void _processSubPieceWriteComplte(int pieceIndex, int begin, int length) {
    _pieceManager.processSubPieceWriteComplete(pieceIndex, begin, length);
  }

  void _processPieceWriteComplete(int index) async {
    if (_fileManager.localHave(index)) return;
    await _fileManager.updateBitfield(index);
    _activePeers.forEach((peer) {
      // if (!peer.remoteHave(index)) {
      peer.sendHave(index);
      // }
    });
    _flushIndicesBuffer.add(index);
    if (_fileManager.isAllComplete) {
      await _flushFiles(_flushIndicesBuffer);
      _fireAllComplete();
    } else {
      await _flushFiles(_flushIndicesBuffer);
    }
  }

  Future _flushFiles(final Set<int> indices) async {
    if (indices.isEmpty) return;
    var piecesSize = _metaInfo.pieceLength;
    var _buffer = indices.length * piecesSize;
    if (_buffer >= maxWriteBufferSize || _fileManager.isAllComplete) {
      var temp = Set<int>.from(indices);
      indices.clear();
      await _fileManager.flushFiles(temp);
    }
    return;
  }

  void _fireAllComplete() {
    _allcompletehandles.forEach((element) {
      Timer.run(() => element());
    });
  }

  bool onAllComplete(void Function() h) {
    return _allcompletehandles.add(h);
  }

  bool offAllComplete(void Function() h) {
    return _allcompletehandles.remove(h);
  }

  /// When read the resource content complete , invoke this method to notify
  /// this class to send it to related peer.
  ///
  /// [pieceIndex] is the index of the piece, [begin] is the byte index of the whole
  /// contents , [block] should be uint8 list, it's the sub-piece contents bytes.
  void readSubPieceComplete(int pieceIndex, int begin, List<int> block) {
    var dindex = [];
    for (var i = 0; i < _remoteRequest.length; i++) {
      var request = _remoteRequest[i];
      if (request[0] == pieceIndex && request[1] == begin) {
        dindex.add(i);
        var peer = request[2] as Peer;
        if (peer != null && !peer.isDisposed) {
          if (peer.sendPiece(pieceIndex, begin, block)) {
            _uploaded += block.length;
            _uploadedNotifySize += block.length;
          }
        }
        break;
      }
    }
    if (dindex.isNotEmpty) {
      dindex.forEach((i) {
        _remoteRequest.removeAt(i);
      });
      if (_uploadedNotifySize >= MAX_UPLOADED_NOTIFY_SIZE) {
        _uploadedNotifySize = 0;
        _fileManager.updateUpload(_uploaded);
      }
    }
  }

  /// 即使对方choke了我，也可以下载
  void _processAllowFast(dynamic source, int index) {
    var peer = source as Peer;
    var piece = _pieceProvider[index];
    if (piece != null && piece.haveAvalidateSubPiece()) {
      piece.addAvalidatePeer(peer.id);
      _pieceManager.processDownloadingPiece(index);
      _requestPieces(source, index);
    }
  }

  void _processSuggestPiece(dynamic source, int index) {}

  void _processRejectRequest(dynamic source, int index, int begin, int length) {
    var piece = _pieceProvider[index];
    piece?.pushSubPieceLast(begin ~/ DEFAULT_REQUEST_LENGTH);
  }

  void _pushSubpicesBack(List<List<int>> requests) {
    if (requests == null || requests.isEmpty) return;
    requests.forEach((element) {
      var pindex = element[0];
      var begin = element[1];
      // TODO 这里很危险，目前都是已16kb来分解一个piece，如果不是呢？
      var piece = _pieceManager[pindex];
      var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
      piece?.pushSubPiece(subindex);
    });
  }

  void _processPeerDispose(dynamic source, [dynamic reason]) {
    var peer = source as Peer;
    var reconnect = true;
    if (reason is BadException) {
      reconnect = false;
    }

    _peersAddress.remove(peer.address);
    _incomingAddress.remove(peer.address.address);
    _activePeers.remove(peer);

    var bufferRequests = peer.requestBuffer;
    _pushSubpicesBack(bufferRequests);

    var completedPieces = peer.remoteCompletePieces;
    completedPieces.forEach((index) {
      _pieceProvider[index]?.removeAvalidatePeer(peer.id);
    });
    _pausedRemoteRequest.remove(peer.id);
    var tempIndex = [];
    for (var i = 0; i < _pausedRequest.length; i++) {
      var pr = _pausedRequest[i];
      if (pr[0] == peer) {
        tempIndex.add(i);
      }
    }
    tempIndex.forEach((index) {
      _pausedRequest.removeAt(index);
    });

    if (reason is TCPConnectException) {
      // print('TCPConnectException');
      // addNewPeerAddress(peer.address, PeerType.UTP);
      return;
    }

    if (reconnect) {
      if (_activePeers.length < MAX_ACTIVE_PEERS && !isDisposed) {
        addNewPeerAddress(peer.address, peer.type);
      }
    } else {
      if (peer.isSeeder && !_fileManager.isAllComplete && !isDisposed) {
        addNewPeerAddress(peer.address, peer.type);
      }
    }
  }

  void _peerConnected(dynamic source) {
    _startedTime ??= DateTime.now().millisecondsSinceEpoch;
    _endTime = null;
    var peer = source as Peer;
    _activePeers.add(peer);
    peer.sendHandShake();
  }

  void _requestPieces(dynamic source, [int pieceIndex = -1]) async {
    if (isPaused) {
      _pausedRequest.add([source, pieceIndex]);
      return;
    }
    var peer = source as Peer;

    // TODO : 0.2.1 代码：
    // Piece piece;
    // if (pieceIndex != -1) {
    //   piece = _pieceProvider[pieceIndex];
    // } else {
    //   piece = _pieceManager.selectPiece(peer.id, peer.remoteCompletePieces,
    //       _pieceProvider, peer.remoteSuggestPieces);
    // }
    // if (piece == null) return;

    // var flag = true;
    // for (var i = 0; i < 5; i++) {
    //   var subIndex = piece.popSubPiece();
    //   if (subIndex == null) {
    //     flag = false;
    //     break;
    //   }
    //   var size = DEFAULT_REQUEST_LENGTH; // block大小现算
    //   var begin = subIndex * size;
    //   if ((begin + size) > piece.byteLength) {
    //     size = piece.byteLength - begin;
    //   }
    //   // print('${peer.id} : ${peer.allowWindow}');
    //   if (!peer.sendRequest(piece.index, begin, size)) {
    //     piece.pushSubPiece(subIndex);
    //     flag = false;
    //     break;
    //   } else {
    //     _requestPieces(peer); // 疯狂请求资源
    //   }
    // }
    // if (flag) _requestPieces(peer);

    // TODO : 0.2.0 代码：
    Piece piece;
    if (pieceIndex != -1) {
      piece = _pieceProvider[pieceIndex];
      if (!piece.haveAvalidateSubPiece()) {
        piece = _pieceManager.selectPiece(peer.id, peer.remoteCompletePieces,
            _pieceProvider, peer.remoteSuggestPieces);
      }
    } else {
      piece = _pieceManager.selectPiece(peer.id, peer.remoteCompletePieces,
          _pieceProvider, peer.remoteSuggestPieces);
    }
    if (piece == null) return;

    var subIndex = piece.popSubPiece();
    var size = DEFAULT_REQUEST_LENGTH; // block大小现算
    var begin = subIndex * size;
    if ((begin + size) > piece.byteLength) {
      size = piece.byteLength - begin;
    }
    // print('${peer.id} : ${peer.allowWindow}');
    if (!peer.sendRequest(piece.index, begin, size)) {
      piece.pushSubPiece(subIndex);
    } else {
      Timer.run(() => _requestPieces(peer, pieceIndex));
      // _requestPieces(peer, pieceIndex); // 疯狂请求资源
    }
  }

  void _processReceivePiece(
      dynamic source, int index, int begin, List<int> block) {
    var peer = source as Peer;
    _downloaded += block.length;

    var piece = _pieceManager[index];
    if (piece != null) {
      var i = index;
      Timer.run(() => _fileManager.writeFile(i, begin, block));
      piece.subPieceDownloadComplete(begin);
      if (piece.haveAvalidateSubPiece()) index = -1;
    }
    Timer.run(() => _requestPieces(peer, index));
  }

  void _processPeerHandshake(dynamic source, String remotePeerId, data) {
    var peer = source as Peer;
    peer.sendBitfield(_fileManager.localBitfield);
  }

  void _processRemoteRequest(dynamic source, int index, int begin, int length) {
    if (isPaused) {
      var peer = source as Peer;
      _pausedRemoteRequest[peer.id] ??= [];
      var pausedRequest = _pausedRemoteRequest[peer.id];
      pausedRequest.add([source, index, begin, length]);
      return;
    }
    var peer = source as Peer;
    _remoteRequest.add([index, begin, peer]);
    _fileManager.readFile(index, begin, length);
  }

  void _processHaveAll(dynamic source) {
    var peer = source as Peer;
    _processBitfieldUpdate(source, peer.remoteBitfield);
  }

  void _processHaveNone(dynamic source) {
    _processBitfieldUpdate(source, null);
  }

  void _processBitfieldUpdate(dynamic source, Bitfield bitfield) {
    var peer = source as Peer;
    if (bitfield != null) {
      if (peer.interestedRemote) return;
      if (_fileManager.isAllComplete && peer.isSeeder) {
        peer.dispose(BadException('已经下载完成不再连接Seeder'));
        return;
      }
      for (var i = 0; i < _fileManager.piecesNumber; i++) {
        if (bitfield.getBit(i)) {
          if (!peer.interestedRemote && !_fileManager.localHave(i)) {
            peer.sendInterested(true);
            return;
          }
        }
      }
    }
    peer.sendInterested(false);
  }

  void _processHaveUpdate(dynamic source, int index) {
    var peer = source as Peer;
    if (_pieceProvider[index] == null) return;

    if (!_fileManager.localHave(index)) {
      if (peer.chokeMe) {
        peer.sendInterested(true);
      } else {
        _pieceProvider[index]?.addAvalidatePeer(peer.id);
        if (peer.isSleeping) Timer.run(() => _requestPieces(peer));
      }
    }
  }

  void _processChokeChange(dynamic source, bool choke) {
    var peer = source as Peer;
    // 更新pieces的可用Peer
    if (!choke) {
      var completedPieces = peer.remoteCompletePieces;
      completedPieces.forEach((index) {
        _pieceProvider[index]?.addAvalidatePeer(peer.id);
      });
      // 这里开始通知request;
      Timer.run(() => _requestPieces(peer));
    } else {
      var completedPieces = peer.remoteCompletePieces;
      completedPieces.forEach((index) {
        _pieceProvider[index]?.removeAvalidatePeer(peer.id);
      });
    }
  }

  void _processInterestedChange(dynamic source, bool interested) {
    var peer = source as Peer;
    if (interested) {
      peer.sendChoke(false);
    } else {
      peer.sendChoke(true); // 不感兴趣就choke它
    }
  }

  void _processRequestTimeout(dynamic source, List<List<int>> requests) {
    var peer = source as Peer;
    var flag = false;
    requests.forEach((element) {
      if (element[4] >= 3) {
        flag = true;
        print(
            'Cancel and re-request it by others :  ${element[0]} - ${element[1]}');
        peer.requestCancel(element[0], element[1], element[2]);
        var index = element[0];
        var begin = element[1];
        var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
        var piece = _pieceManager[index];
        if (piece != null) {
          var subPieceCompleted = piece.subPieceIsDownloaded(begin) ||
              piece.subPieceIsWritting(begin);
          if (!subPieceCompleted) {
            piece?.pushSubPiece(subindex);
            return;
          }
        }
      }
    });
    // 唤醒其他可能没有工作的peer
    if (flag) {
      _activePeers.forEach((p) {
        if (p != peer && p.currentRequestBuffer.isEmpty) {
          Timer.run(() => _requestPieces(p));
        }
      });
    }
  }

  void _sendKeepAliveToAll() {
    _activePeers?.forEach((peer) {
      Timer.run(() => _keepAlive(peer));
    });
  }

  void _keepAlive(Peer peer) {
    peer.sendKeeplive();
  }

  /// Pause the task
  ///
  /// All the incoming request message will be received but they will be stored
  /// in buffer and no response to remote.
  ///
  /// All out message/incoming connection will be processed even task is paused.
  void pause() {
    if (_paused) return;
    _paused = true;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(Duration(seconds: 110), _sendKeepAliveToAll);
  }

  /// Resume the task
  void resume() {
    if (!_paused) return;
    _paused = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    _pausedRequest.forEach((element) {
      var peer = element[0] as Peer;
      var index = element[1];
      if (!peer.isDisposed) Timer.run(() => _requestPieces(peer, index));
    });
    _pausedRequest.clear();

    _pausedRemoteRequest.forEach((key, value) {
      value.forEach((element) {
        var peer = element[0] as Peer;
        var index = element[1];
        var begin = element[2];
        var length = element[3];
        if (!peer.isDisposed) {
          Timer.run(() => _processRemoteRequest(peer, index, begin, length));
        }
      });
    });
    _pausedRemoteRequest.clear();
  }

  Future disposeAllSeeder([dynamic reason]) async {
    _activePeers?.forEach((peer) async {
      if (peer.isSeeder) {
        await peer.dispose(reason);
      }
    });
    return;
  }

  Future dispose() async {
    if (isDisposed) return;
    _disposed = true;
    clearHolepunch();
    clearPEX();
    _endTime = DateTime.now().millisecondsSinceEpoch;

    _fileManager.offSubPieceWriteComplete(_processSubPieceWriteComplte);
    _fileManager.offSubPieceReadComplete(readSubPieceComplete);
    _pieceManager.offPieceComplete(_processPieceWriteComplete);

    await _flushFiles(_flushIndicesBuffer);
    _flushIndicesBuffer?.clear();
    _allcompletehandles?.clear();
    _noActivePeerhandles?.clear();
    _remoteRequest?.clear();
    _pausedRequest?.clear();
    _pausedRemoteRequest?.clear();
    Function _disposePeers = (Set<Peer> peers) async {
      if (peers != null && peers.isNotEmpty) {
        for (var i = 0; i < peers.length; i++) {
          var peer = peers.elementAt(i);
          unHookPeer(peer);
          await peer.dispose('Peer Manager disposed');
        }
      }
      peers.clear();
    };
    await _disposePeers(_activePeers);
  }

  //TODO test:

  @override
  void addPEXPeer(dynamic source, CompactAddress address, Map options) {
    // addNewPeerAddress(address);
    // return;
    // if (options['reachable'] != null) {
    //   if (options['utp'] != null) {
    //     print('UTP/TCP reachable');
    //   }
    //   addNewPeerAddress(address);
    //   return;
    // }
    if ((options['utp'] != null || options['ut_holepunch'] != null) &&
        options['reachable'] == null) {
      var peer = source as Peer;
      var message = getRendezvousMessage(address);
      peer.sendExtendMessage('ut_holepunch', message);
      return;
    }
    addNewPeerAddress(address);
  }

  @override
  Iterable<Peer> get activePeers => _activePeers;

  @override
  void holePunchConnect(CompactAddress ip) {
    addNewPeerAddress(ip, PeerType.UTP);
  }

  int get utpPeerCount {
    return _activePeers.fold(0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += 1;
      }
      return previousValue;
    });
  }

  double get utpDownloadSpeed {
    return _activePeers.fold(0.0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += element.currentDownloadSpeed;
      }
      return previousValue;
    });
  }

  double get utpUploadSpeed {
    return _activePeers.fold(0.0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += element.averageUploadSpeed;
      }
      return previousValue;
    });
  }

  @override
  void holePunchError(String err, CompactAddress ip) {
    // print('holepunch error - $err');
  }

  @override
  void holePunchRendezvous(CompactAddress ip) {
    // TODO: implement holePunchRendezvous
    print('收到 holePunch Rendezvous');
  }
}
