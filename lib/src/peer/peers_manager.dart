import 'dart:async';
import 'dart:developer';

import 'package:torrent_model/torrent_model.dart';

import 'bitfield.dart';
import 'peer.dart';
import '../file/download_file_manager.dart';
import '../piece/piece_manager.dart';
import '../piece/piece.dart';
import '../piece/piece_provider.dart';
import '../utils.dart';

const MAX_ACTIVE_PEERS = 50;

const MAX_WRITE_BUFFER_SIZE = 10 * 1024 * 1024;

const MAX_UPLOADED_NOTIFY_SIZE = 1024 * 1024 * 10; // 10 mb

///
/// TODO:
/// - 没有处理对外的Suggest Piece/Fast Allow
class PeersManager {
  final Set<Peer> interestedPeers = {};
  final Set<Peer> notInterestedPeers = {};
  final Set<Peer> noResponsePeers = {};

  /// 写入磁盘的缓存最大值
  int maxWriteBufferSize;

  final _flushIndicesBuffer = <int>{};

  final Set<void Function()> _allcompletehandles = {};

  final Set<void Function()> _noActivePeerhandles = {};

  final List<List<int>> _timeoutRequest = [];

  final Torrent _metaInfo;

  int _uploaded = 0;

  int _uploadedNotifySize = 0;

  final List<List> _remoteRequest = [];

  final DownloadFileManager _fileManager;

  final PieceProvider _pieceProvider;

  final PieceManager _pieceManager;

  final _flushStream = StreamController<Set<int>>();

  final _flushBuffer = <int>{};

  StreamSubscription _flushStreamS;

  PeersManager(this._pieceManager, this._pieceProvider, this._fileManager,
      this._metaInfo,
      [this.maxWriteBufferSize = MAX_WRITE_BUFFER_SIZE]) {
    assert(_pieceManager != null &&
        _pieceProvider != null &&
        _fileManager != null);
    // hook FileManager and PieceManager
    _fileManager.onSubPieceWriteComplete(_processSubPieceWriteComplte);
    _fileManager.onSubPieceReadComplete(readSubPieceComplete);
    _pieceManager.onPieceComplete(_processPieceWriteComplete);
  }

  void hookPeer(Peer peer) {
    if (_peerExsist(peer)) return;
    peer.onDispose(_processPeerDispose);
    peer.onBitfield(_processBitfieldUpdate);
    peer.onHaveAll((peer) => _processBitfieldUpdate(peer, peer.remoteBitfield));
    peer.onHaveNone((peer) => _processBitfieldUpdate(peer, null));
    peer.onHandShake(_processPeerHandshake);
    peer.onChokeChange(_processChokeChange);
    peer.onInterestedChange(_processInterestedChange);
    peer.onConnect(_peerConnected);
    peer.onHave(_processHaveUpdate);
    peer.onPiece(_processReceivePiece);
    peer.onRequest(_processRemoteRequest);
    peer.onRequestTimeout(_processRequestTimeout);
    peer.onRejectRequest(_processRejectRequest);
    peer.onAllowFast(_processAllowFast);
    peer.connect();
  }

  bool _peerExsist(Peer id) {
    return interestedPeers.contains(id) ||
        notInterestedPeers.contains(id) ||
        noResponsePeers.contains(id);
  }

  void _processSubPieceWriteComplte(int pieceIndex, int begin, int length) {
    _pieceManager.processSubPieceWriteComplete(pieceIndex, begin, length);
  }

  void _processPieceWriteComplete(int index) async {
    if (_fileManager.localHave(index)) return;
    await _fileManager.updateBitfield(index);
    interestedPeers.forEach((peer) {
      // if (!peer.remoteHave(index)) {
      log('收到完整片段，通知 ${peer.address} : $index', name: runtimeType.toString());
      peer.sendHave(index);
      // }
    });
    notInterestedPeers.forEach((peer) {
      // if (!peer.remoteHave(index)) {
      log('收到完整片段，通知 ${peer.address} : $index', name: runtimeType.toString());
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

  // void _sendKeepAliveToNotInterseted() {
  //   if (notInterestedPeers.isEmpty) return;

  //   var length = MAX_ACTIVE_PEERS - interestedPeers.length;
  //   for (var i = 0; i < length; i++) {
  //     var index = randomInt(notInterestedPeers.length);
  //     var p = notInterestedPeers.elementAt(index);
  //     p?.sendKeeplive();
  //   }
  // }

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
      _pieceManager.processDownloadingPiece(
          peer.id, index, peer.remoteBitfield.completedPieces);
      _requestPieces(source, index);
    }
  }

  void _processSuggestPiece(dynamic source, int index) {}

  void _processRejectRequest(dynamic source, int index, int begin, int length) {
    var piece = _pieceProvider[index];
    piece?.pushSubPieceLast(begin ~/ DEFAULT_REQUEST_LENGTH);
  }

  void _processPeerDispose(dynamic source, [dynamic reason]) {
    var peer = source as Peer;
    var bufferRequests = peer.requestBuffer;
    log('Peer已销毁, ${peer.address},退还收到未收到Request:$bufferRequests,将其删除',
        error: reason, name: runtimeType.toString());

    bufferRequests.forEach((element) {
      var pindex = element[0];
      var begin = element[1];
      var length = element[2];
      var piece = _pieceManager[pindex];
      var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
      _removeTimeoutRequest(pindex, begin, length);
      piece?.pushSubPiece(subindex);
    });
    var completedPieces = peer.remoteCompletePieces;
    completedPieces.forEach((index) {
      _pieceProvider[index]?.removeAvalidatePeer(peer.id);
    });
    interestedPeers.remove(peer);
    notInterestedPeers.remove(peer);
    noResponsePeers.remove(peer);
    log('目前还有 ${interestedPeers.length}个活跃节点. ');
    if (interestedPeers.isEmpty) {
      _fireNoActivePeer();
    }
  }

  bool onNoActivePeerEvent(Function k) {
    return _noActivePeerhandles.add(k);
  }

  bool offNoActivePeerEvent(Function k) {
    return _noActivePeerhandles.remove(k);
  }

  void _fireNoActivePeer() {
    _noActivePeerhandles.forEach((element) {
      Timer.run(() => element());
    });
  }

  void _peerConnected(dynamic source) {
    var peer = source as Peer;
    log('${peer.address} is connected', name: runtimeType.toString());
    noResponsePeers.add(peer);
    peer.sendHandShake();
  }

  void _requestPieces(dynamic source, [int pieceIndex = -1]) {
    var peer = source as Peer;
    Piece piece;
    if (pieceIndex != -1) {
      piece = _pieceProvider[pieceIndex];
    } else {
      piece = _pieceManager.selectPiece(peer.id, peer.remoteCompletePieces,
          _pieceProvider, peer.remoteSuggestPieces);
    }
    if (piece == null) {
      if (_timeoutRequest.isNotEmpty) {
        // 如果已经没有可以请求的piece，看看超时piece
        var timeoutR = _timeoutRequest.removeAt(0);
        if (!peer.sendRequest(timeoutR[0], timeoutR[1], timeoutR[2])) {
          _timeoutRequest.insert(0, timeoutR);
        }
      }
      return;
    }
    var subIndex = piece.popSubPiece();
    var size = DEFAULT_REQUEST_LENGTH; // block大小现算
    var begin = subIndex * size;
    if ((begin + size) > piece.byteLength) {
      size = piece.byteLength - begin;
    }

    if (!peer.sendRequest(piece.index, begin, size)) {
      piece.pushSubPiece(subIndex);
    }
  }

  void _processReceivePiece(dynamic source, int index, int begin,
      List<int> block, bool afterTimeout) {
    var peer = source as Peer;
    var rindex = -1;
    for (var i = 0; i < _timeoutRequest.length; i++) {
      var tr = _timeoutRequest[i];
      if (tr[0] == index && tr[1] == begin && tr[2] == block.length) {
        log('超时Request[$index,$begin]已从${peer.address}获得，当前超时Request:$_timeoutRequest',
            name: runtimeType.toString());
        rindex = i;
        break;
      }
    }
    if (rindex != -1) {
      _timeoutRequest.removeAt(rindex);
    }
    _fileManager.writeFile(index, begin, block);
    var nextIndex = _pieceManager.selectPieceWhenReceiveData(
        peer.id, peer.remoteCompletePieces, index, begin);
    _requestPieces(peer, nextIndex);
  }

  void _processPeerHandshake(dynamic source, String remotePeerId, data) {
    var peer = source as Peer;
    noResponsePeers.remove(peer);
    notInterestedPeers.add(peer);
    peer.sendBitfield(_fileManager.localBitfield);
  }

  void _processRemoteRequest(dynamic source, int index, int begin, int length) {
    var peer = source as Peer;
    _remoteRequest.add([index, begin, peer]);
    _fileManager.readFile(index, begin, length);
  }

  void _processBitfieldUpdate(dynamic source, Bitfield bitfield) {
    var peer = source as Peer;
    if (bitfield != null) {
      if (peer.interestedRemote) return;
      for (var i = 0; i < _fileManager.piecesNumber; i++) {
        if (bitfield.getBit(i)) {
          if (!peer.interestedRemote && !_fileManager.localHave(i)) {
            peer.sendInterested(true);
            notInterestedPeers.remove(peer);
            interestedPeers.add(peer);
            log('${peer.address} 有我要的资源 $bitfield，发送 interested');
            return;
          }
        }
      }
    }
    log('${peer.address} 没有我要的资源 $bitfield，发送 not interested');
    peer.sendInterested(false);
  }

  void _processHaveUpdate(dynamic source, int index) {
    var peer = source as Peer;
    if (!_fileManager.localHave(index)) {
      log('${peer.address} 有我要的资源，发送 interested并更新piece的avalidate peer');
      peer.sendInterested(true);
      notInterestedPeers.remove(peer);
      interestedPeers.add(peer);
      _pieceProvider[index]?.addAvalidatePeer(peer.id);
      Timer.run(() => _requestPieces(peer));
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

  void _processRequestTimeout(
      dynamic source, int index, int begin, int length) {
    var peer = source as Peer;
    // 如果超时，不会重新请求，等待。实在不来会在销毁peer的时候释放所有它对应的请求
    _addTimeoutRequest(index, begin, length);
    log('从 ${peer.address} 请求 [$index,$begin] 超时 , 所有超时Request :$_timeoutRequest',
        name: runtimeType.toString());
    if (_pieceProvider[index] != null &&
        _pieceProvider[index].haveAvalidateSubPiece()) {
      _requestPieces(peer, index);
    } else {
      _requestPieces(peer);
    }
  }

  /// 往time out request buffer中记录
  bool _addTimeoutRequest(int index, int begin, int length) {
    for (var i = 0; i < _timeoutRequest.length; i++) {
      var r = _timeoutRequest[i];
      if (r[0] == index && r[1] == begin && length == r[2]) {
        return false;
      }
    }
    _timeoutRequest.add([index, begin, length]);
    return true;
  }

  bool _removeTimeoutRequest(int index, int begin, int length) {
    var di;
    for (var i = 0; i < _timeoutRequest.length; i++) {
      var r = _timeoutRequest[i];
      if (r[0] == index && r[1] == begin && r[2] == length) {
        di = i;
        break;
      }
    }
    if (di != null) {
      _timeoutRequest.removeAt(di);
      return true;
    }
    return false;
  }

  Future dispose() async {
    var l = <Future>[];
    _fileManager.offSubPieceWriteComplete(_processSubPieceWriteComplte);
    _fileManager.offSubPieceReadComplete(readSubPieceComplete);
    _pieceManager.offPieceComplete(_processPieceWriteComplete);

    l.add(_flushStream?.close());
    l.add(_flushStreamS.cancel());

    // await _fileManager.flushPiece(_flushBuffer.toList());

    _flushBuffer.clear();

    interestedPeers.forEach((peer) {
      l.add(peer.dispose('Peer Manager disposed'));
    });
    notInterestedPeers.forEach((peer) {
      l.add(peer.dispose('Peer Manager disposed'));
    });
    noResponsePeers.forEach((peer) {
      l.add(peer.dispose('Peer Manager disposed'));
    });
    _timeoutRequest.clear();

    return Stream.fromFutures(l).toList();
  }
}