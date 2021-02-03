import 'dart:async';

import 'package:torrent_model/torrent_model.dart';
import '../peer/bitfield.dart';
import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

typedef PieceCompleteHandle = void Function(int pieceIndex);

class PieceManager implements PieceProvider {
  bool _isFirst = true;

  final Map<int, Piece> _pieces = {};

  // final Set<int> _completedPieces = <int>{};

  final List<PieceCompleteHandle> _pieceCompleteHandles = [];

  final Set<int> _donwloadingPieces = <int>{};

  final PieceSelector _pieceSelector;

  PieceManager(this._pieceSelector, int piecesNumber);

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
    }
  }

  void onPieceComplete(PieceCompleteHandle handle) {
    _pieceCompleteHandles.add(handle);
  }

  void offPieceComplete(PieceCompleteHandle handle) {
    _pieceCompleteHandles.remove(handle);
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

  Piece selectPiece(String remotePeerId, List<int> remoteHavePieces,
      PieceProvider provider, final Set<int> suggestPieces) {
    // 查看当前下载piece中是否可以使用该peer
    var avalidatePiece = <int>[];
    // 优先下载Suggest Pieces
    if (suggestPieces != null && suggestPieces.isNotEmpty) {
      for (var i = 0; i < suggestPieces.length; i++) {
        var p = _pieces[suggestPieces.elementAt(i)];
        if (p != null && p.haveAvalidateSubPiece()) {
          processDownloadingPiece(p.index);
          return p;
        }
      }
    }
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
    var piece = _pieceSelector.selectPiece(
        remotePeerId, candidatePieces, this, _isFirst);
    _isFirst = false;
    if (piece == null) return null;
    processDownloadingPiece(piece.index);
    return piece;
  }

  void processDownloadingPiece(int pieceIndex) {
    _donwloadingPieces.add(pieceIndex);
  }

  /// 完成后的Piece需要一些处理
  /// - 从`_pieces`列表中删除
  /// - 从`_downloadingPieces`列表中删除
  /// - 通知监听器
  void _processCompletePiece(int index) {
    var piece = _pieces.remove(index);
    _donwloadingPieces.remove(index);
    if (piece != null) {
      piece.dispose();
      _pieceCompleteHandles.forEach((handle) {
        Timer.run(() => handle(index));
      });
    }
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (isDisposed) return;
    _disposed = true;
    _pieces.forEach((key, value) {
      value.dispose();
    });
    _pieces.clear();
    _pieceCompleteHandles.clear();
    _donwloadingPieces.clear();
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
