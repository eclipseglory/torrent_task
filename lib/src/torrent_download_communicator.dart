import 'dart:async';
import 'dart:developer';

import 'file/download_file_manager.dart';

import 'peer/bitfield.dart';
import 'peer/peer.dart';
import 'piece/piece_manager.dart';
import 'piece/piece_provider.dart';
import 'utils.dart';

const MAX_ACTIVE_PEERS = 50;

const MAX_UPLOADED_NOTIFY_SIZE = 1024 * 1024 * 10; // 10 mb

///
/// TODO:
/// - 没有处理Suggest Piece
class TorrentDownloadCommunicator {
  // final Map<String, Peer> readyPeersMap = {};
  // final Map<String, Peer> avalidatePeersMap = {};
  // final Map<String, Peer> disposedPeersMap = {};

  final Set<Peer> interestedPeers = {};
  final Set<Peer> notInterestedPeers = {};
  final Set<Peer> noResponsePeers = {};

  final Set<void Function()> _allcompletehandles = {};

  final List<List<int>> _timeoutRequest = [];

  int _uploaded = 0;

  int _uploadedNotifySize = 0;

  final List<List> _remoteRequest = [];

  final DownloadFileManager _fileManager;

  final PieceProvider _pieceProvider;

  final PieceManager _pieceManager;

  final _flushStream = StreamController<List<int>>();

  final _flushBuffer = <int>{};

  StreamSubscription _flushStreamS;

  Timer keepAliveTimer;

  TorrentDownloadCommunicator(
      this._pieceManager, this._pieceProvider, this._fileManager) {
    assert(_pieceManager != null &&
        _pieceProvider != null &&
        _fileManager != null);
    // hook FileManager and PieceManager
    _fileManager.onSubPieceWriteComplete(_processSubPieceWriteComplte);
    _fileManager.onSubPieceReadComplete(readSubpieceComplete);
    _pieceManager.onPieceComplete(_pieceWrittenComplete);
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

  void _pieceWrittenComplete(int index) async {
    // 防止多次更新
    if (_fileManager.localHave(index)) return;
    // 先要更新完本地才去通知远程
    var success = await _fileManager.updateBitfield(index);
    if (!success) return;

    interestedPeers.forEach((peer) {
      // if (!peer.remoteHave(index)) {
      log('收到完整片段，通知 ${peer.address} : $index');
      peer.sendHave(index);
      // }
    });
    notInterestedPeers.forEach((peer) {
      // if (!peer.remoteHave(index)) {
      log('收到完整片段，通知 ${peer.address} : $index');
      peer.sendHave(index);
      // }
    });
    // TODO flush和写入以及下载速度不匹配，这导致会重复flush，
    // 目前用一个buffer缓存需要flush的pieceindex，但问题没有彻底解决
    _flushBuffer.add(index);
    _flushStreamS ??= _flushStream.stream.listen((piecesIndieces) async {
      _flushStreamS?.pause();
      await _fileManager.flushPiece(piecesIndieces);
      // 等到完全将缓冲区写入磁盘再验证是否全部成
      if (_fileManager.localBitfield.completedPieces.length ==
          _pieceManager.length) {
        _fireAllComplete();
      }
      _flushStreamS?.resume();
    });
    if (!_flushStream.isPaused) {
      if (_flushBuffer.isEmpty) return;
      var temp = List<int>.from(_flushBuffer);
      _flushBuffer.clear();
      _flushStream.add(temp);
    }
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

  void readSubpieceComplete(int pieceIndex, int begin, List<int> block) {
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
    if (piece != null) {
      piece.addAvalidatePeer(peer.id);
    }
    _requestPieces(source, index);
  }

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
  }

  void _peerConnected(dynamic source) {
    var peer = source as Peer;
    log('${peer.address} is connected', name: runtimeType.toString());
    noResponsePeers.add(peer);
    peer.sendHandShake();
  }

  void _requestPieces(dynamic source, [int pieceIndex = -1]) {
    var peer = source as Peer;
    var piece;
    if (pieceIndex != -1) {
      piece = _pieceProvider[pieceIndex];
    } else {
      piece = _pieceManager.selectPiece(
          peer.id, peer.remoteCompletePieces, _pieceProvider);
    }
    if (piece == null) return;
    var subIndex = piece.popSubPiece();
    var size = DEFAULT_REQUEST_LENGTH;
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
      if (tr[0] == index && tr[1] == begin) {
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
    print('handshake ${peer.address}:$remotePeerId');
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
    log('bitfield updated : ${peer.address}');
    if (bitfield != null) {
      if (peer.interestedRemote) return; // 避免有些发送have all同时发送bitfield的客户端
      for (var i = 0; i < _fileManager.piecesNumber; i++) {
        if (bitfield.getBit(i)) {
          // piecesManager[i].addOwnerPeer(peer.id);
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
      peer.sendInterested(true);
      log('${peer.address} 有我要的资源，发送 interested');
      notInterestedPeers.remove(peer);
      interestedPeers.add(peer);
      _pieceProvider[index]?.addAvalidatePeer(peer.id);
      Timer.run(() => _requestPieces(peer));
      return;
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
      peer.sendChoke(true);
    }
  }

  void _processRequestTimeout(
      dynamic source, int index, int begin, int length) {
    // 如果超时，将该subpiece放入piece的subpiece队尾，然后重新请求
    var peer = source as Peer;
    _addTimeoutRequest(index, begin, length);
    // _timeoutRequest.add([index, begin]);
    log('从 ${peer.address} 请求 [$index,$begin] 超时 , 所有超时Request :$_timeoutRequest',
        name: runtimeType.toString());
    // var subIndex = begin ~/ DEFAULT_REQUEST_LENGTH;
    // piecesManager[index]?.pushSubPieceLast(subIndex);
    if (_pieceProvider[index] != null) {
      if (_pieceProvider[index].haveAvalidateSubPiece()) {
        _requestPieces(peer, index);
      } else {
        _requestPieces(peer);
      }
    } else {
      _requestPieces(peer);
    }
  }

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

  void stop() {
    // TODO implement it
    // keepAliveTimer?.cancel();
  }
}
