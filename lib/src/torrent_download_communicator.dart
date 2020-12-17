import 'dart:async';
import 'dart:developer';

import 'package:torrent_tracker/torrent_tracker.dart';

import 'file/download_file_manager.dart';

import 'peer/bitfield.dart';
import 'peer/peer.dart';
import 'piece/piece_manager.dart';
import 'piece/piece_provider.dart';
import 'utils.dart';

const MAX_ACTIVE_PEERS = 50;

///
/// TODO LIST:
/// - 没有处理Allow Fast
/// - 没有处理Suggest Piece
class TorrentDownloadCommunicator {
  // final Map<String, Peer> readyPeersMap = {};
  // final Map<String, Peer> avalidatePeersMap = {};
  // final Map<String, Peer> disposedPeersMap = {};

  final Set<Peer> interestedPeers = {};
  final Set<Peer> notInterestedPeers = {};
  final Set<Peer> noResponsePeers = {};

  final List<List<int>> _timeoutRequest = [];

  int _uploaded = 0;

  final List<List> _remoteRequest = [];

  final DownloadFileManager _fileManager;

  final PieceProvider _pieceProvider;

  final PieceManager _pieceManager;

  Timer keepAliveTimer;

  final _peerSet = <String>[];

  TorrentDownloadCommunicator(
      this._pieceManager, this._pieceProvider, this._fileManager) {
    assert(_pieceManager != null &&
        _pieceProvider != null &&
        _fileManager != null);
    // hook FileManager and PieceManager
    _fileManager
        .onSubPieceWriteComplete(_pieceManager.processSubPieceWriteComplete);
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
    peer.connect();
  }

  bool _peerExsist(Peer id) {
    return interestedPeers.contains(id) ||
        notInterestedPeers.contains(id) ||
        noResponsePeers.contains(id);
  }

  void _pieceWrittenComplete(int index) async {
    // 先要更新完本地才去通知远程
    await _fileManager.updateBitfield(index);
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
          }
        }
        break;
      }
    }
    if (dindex.isNotEmpty) {
      dindex.forEach((i) {
        _remoteRequest.removeAt(i);
      });
      _fileManager.updateUpload(_uploaded);
    }
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

    log('目前还有 ${interestedPeers.length}个活跃节点');
    bufferRequests.forEach((element) {
      var pindex = element[0];
      var begin = element[1];
      var piece = _pieceManager[pindex];
      var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
      piece?.pushSubPiece(subindex);
    });
    var completedPieces = peer.remoteCompletePieces;
    completedPieces.forEach((index) {
      _pieceProvider[index]?.removeAvalidatePeer(peer.id);
    });
    interestedPeers.remove(peer);
    notInterestedPeers.remove(peer);
    noResponsePeers.remove(peer);
  }

  void _peerConnected(dynamic source) {
    var peer = source as Peer;
    print('${peer.address} is connected');
    noResponsePeers.add(peer);
    peer.sendHandShake();
  }

  void _requestPieces(dynamic source, [int pieceIndex = -1]) {
    var peer = source as Peer;
    if (peer.address.host == '127.0.0.1') {
      // TODO DEBUG
      print('hjere');
    }
    var piece;
    if (pieceIndex != -1) {
      piece = _pieceProvider[pieceIndex];
    } else {
      piece = _pieceManager.selectPiece(
          peer.id, peer.remoteCompletePieces, _pieceProvider);
    }
    if (piece == null) {
      return;
    }
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
    var nextIndex = _pieceManager.selectPieceWhenReceiveData(
        peer.id, peer.remoteCompletePieces, index, begin);
    _fileManager.writeFile(index, begin, block);
    if (nextIndex == -1) {
      // TODO DEBG
      print('dafda');
    }
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
    if (peer.address.host == '127.0.0.1') {
      // TODO DEBUG
      print('hhh');
    }
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
      if (r[0] == index && r[1] == begin) {
        return false;
      }
    }
    _timeoutRequest.add([index, begin, length]);
    return true;
  }

  void stop() {
    // TODO implement it
    // keepAliveTimer?.cancel();
  }
}
