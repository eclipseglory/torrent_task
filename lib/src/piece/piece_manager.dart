import 'dart:async';

import 'package:torrent_model/torrent_model.dart';
import '../peer/bitfield.dart';
import '../utils.dart';
import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

typedef PieceCompleteHandle = void Function(int pieceIndex);

class PieceManager implements PieceProvider {
  List<Piece> _pieces;

  // final Set<int> _completedPieces = <int>{};

  final List<PieceCompleteHandle> _pieceCompleteHandles = [];

  final Set<int> _donwloadingPieces = <int>{};

  final PieceSelector _pieceSelector;

  PieceManager(this._pieceSelector, int piecesNumber) {
    _pieces = List<Piece>(piecesNumber);
  }

  static PieceManager createPieceManager(
      PieceSelector pieceSelector, Torrent metaInfo, Bitfield bitfield) {
    var p = PieceManager(pieceSelector, metaInfo.pieces.length);
    p.initPieces(metaInfo, bitfield);
    return p;
  }

  void initPieces(Torrent metaInfo, Bitfield bitfield) {
    for (var i = 0; i < metaInfo.pieces.length; i++) {
      var byteLength = metaInfo.pieceLength;
      if (i == metaInfo.pieces.length - 1) {
        byteLength = metaInfo.lastPriceLength;
      }
      var piece = Piece(metaInfo.pieces[i], i, byteLength);
      if (!bitfield.getBit(i)) _pieces[i] = piece;
      // if (localBitfield.getBit(i)) {
      //   _completedPieces.add(i);
      // }
    }
  }

  void onPieceComplete(PieceCompleteHandle handle) {
    _pieceCompleteHandles.add(handle);
  }

  void offPieceComplete(PieceCompleteHandle handle) {
    _pieceCompleteHandles.remove(handle);
  }

  bool isPieceCompleted(int index) {
    if (index < 0 || index >= _pieces.length) return false;
    var piece = _pieces[index];
    return piece.isCompleted;
  }

  /// 这个接口是用于FIleManager回调使用。
  ///
  /// 只有所有子Piece写入完成才认为该Piece算完成。
  ///
  /// 因为如果仅下载完成就修改bitfield，会造成发送have给对方后，对方请求的子piece还没在
  /// 文件系统中，会读取出错误的数据
  void processSubPieceWriteComplete(int pieceIndex, int begin, int length) {
    var piece = _pieces[pieceIndex];
    if (piece != null) {
      piece.subPieceWriteComplete(begin);
      if (piece.isCompleted) _processCompletePiece(pieceIndex);
    }
  }

  Piece selectPiece(
      String remotePeerId, List<int> remoteHavePieces, PieceProvider provider) {
    // 查看当前下载piece中是否可以使用该peer
    var avalidatePiece = <int>[];
    var candidatePieces = remoteHavePieces;
    for (var i = 0; i < _donwloadingPieces.length; i++) {
      var p = _pieces[_donwloadingPieces.elementAt(i)];
      if (p == null) continue;
      if (p.containsAvalidatePeer(remotePeerId) && p.haveAvalidateSubPiece()) {
        avalidatePiece.add(p.index);
      }
    }

    // 如果可以下载正在下载中的piece，就下载该piece（多个Peer同时下载一个piece使其尽快完成的原则）
    if (avalidatePiece.isNotEmpty) {
      candidatePieces = avalidatePiece;
    }
    var fitPieces =
        _pieceSelector.selectPiece(remotePeerId, candidatePieces, this);
    if (fitPieces.isEmpty) return null;
    var piece = fitPieces[randomInt(fitPieces.length)];
    _processDonwloadingPiece(remotePeerId, piece.index, remoteHavePieces);
    // log('随机使用：${piece.index}，当前下载中的piece 有：', name: 'PieceManager');
    // _donwloadingPieces.forEach((element) {
    //   var p = _pieces[element];
    //   if (p != null) {
    //     log(' - ${p.index}[${p.avalidateSubPieceCount}]');
    //   }
    // });
    return piece;
  }

  void _processDonwloadingPiece(
      String peerId, int pieceIndex, List<int> remoteHavePieces) {
    // 该peer被占用，修改其他piece的avalidate peer
    remoteHavePieces.forEach((index) {
      _pieces[index]?.removeAvalidatePeer(peerId);
    });
    _donwloadingPieces.add(pieceIndex);
  }

  /// 当有数据收到时，需要确定下一次要使用的piece。
  ///
  /// 下载的时候需要保证某一个Piece能尽快完成，这个方法会在Piece收到部分数据后:
  /// - 如果还有可下载的sun piece，返回[pieceIndex]，继续下载
  /// - 如果没有可下载的sun piece, 返回 -1，并且会将[remoteHavePieces]中
  /// 所有的Piece的`avalidatePeers`加入当前[peerId]，并且如果该Piece已经全部完成
  /// 会将它从下载列表和当前pieces列表中删除
  ///
  int selectPieceWhenReceiveData(
      String peerId, List<int> remoteHavePieces, int pieceIndex, int begin) {
    // 这是逻辑上的可能性，实际上不会发生，如果触发下面的判断内代码，只能说明其他地方某处没写对
    if (_pieces[pieceIndex] == null || _pieces[pieceIndex].isCompleted) {
      _setAvalidatePeerForPieces(peerId, remoteHavePieces);
      _processCompletePiece(pieceIndex);
      return -1;
    }
    var piece = _pieces[pieceIndex];
    piece.subPieceDownloadComplete(begin);

    if (piece.haveAvalidateSubPiece()) return pieceIndex;
    // 不能继续下载的话，就要重置peer的一些数据
    // print('$pieceIndex 没有可用sub piece，无法继续下载');
    _setAvalidatePeerForPieces(peerId, remoteHavePieces);
    // **NOTE** 没有可下载子piece并不一定就完成了，可能有一些在下载中
    if (piece.isCompleted) {
      _processCompletePiece(pieceIndex);
      // log('Piece $pieceIndex 完全写入磁盘系统中');
    } else {
      // log('Piece $pieceIndex 下载中：${piece.subPiecesCount - piece.avalidateSubPieceCount - piece.downloadedSubPiecesCount - piece.writtingSubPiecesCount} , 已完成: ${piece.downloadedSubPiecesCount} , 写入中：${piece.writtingSubPiecesCount}');
    }
    return -1;
  }

  /// 为给出的[piecesIndex]的所有`Piece`加上avalidate peer ([id])
  void _setAvalidatePeerForPieces(String id, List<int> piecesIndex) {
    piecesIndex.forEach((index) {
      _pieces[index]?.addAvalidatePeer(id);
    });
  }

  /// 完成后的Piece需要一些处理
  /// - 从`_pieces`列表中删除
  /// - 从`_downloadingPieces`列表中删除
  /// - 通知监听器
  void _processCompletePiece(int index) {
    _pieces[index] = null;
    _donwloadingPieces.remove(index);
    _pieceCompleteHandles.forEach((handle) {
      Timer.run(() => handle(index));
    });
  }

  @override
  Piece operator [](index) {
    return _pieces[index];
  }

  // @override
  // Piece getPiece(int index) {
  //   return _pieces[index];
  // }

  @override
  int get length => _pieces.length;
}
