import 'dart:collection';

import '../utils.dart';

class Piece {
  final String hashString;

  final int byteLength;

  final int index;

  final Set<String> _avalidatePeers = <String>{};

  Queue<int> _subPiecesQueue;

  final Set<int> _downloadedSubPieces = <int>{};

  final Set<int> _writtingSubPieces = <int>{};

  int _subPiecesCount = 0;

  Piece(this.hashString, this.index, this.byteLength,
      [int requestLength = DEFAULT_REQUEST_LENGTH]) {
    if (requestLength <= 0) {
      throw Exception('Request length should bigger than zero');
    }
    if (requestLength > DEFAULT_REQUEST_LENGTH) {
      throw Exception('Request length should smaller than 16kb');
    }
    _subPiecesCount = byteLength ~/ requestLength;
    if (_subPiecesCount * requestLength != byteLength) {
      _subPiecesCount++;
    }
    _subPiecesQueue =
        Queue.from(List.generate(_subPiecesCount, (index) => index));
  }

  bool get isDownloading {
    if (subPiecesCount == 0) return false;
    if (isCompleted) return false;
    return subPiecesCount !=
        _downloadedSubPieces.length +
            _subPiecesQueue.length +
            _writtingSubPieces.length;
  }

  Queue<int> get subPieceQueue => _subPiecesQueue;

  int get subPiecesCount => _subPiecesCount;

  double get completed {
    if (subPiecesCount == 0) return 0;
    return _downloadedSubPieces.length / subPiecesCount;
  }

  int get downloadedSubPiecesCount => _downloadedSubPieces.length;

  int get writtingSubPiecesCount => _writtingSubPieces.length;

  bool haveAvalidateSubPiece() {
    if (_subPiecesCount == 0) return false;
    return _subPiecesQueue.isNotEmpty;
  }

  bool haveAvalidatePeers() {
    if (_subPiecesCount == 0) return false;
    return _avalidatePeers.isNotEmpty;
  }

  int get avalidatePeersCount => _avalidatePeers.length;

  int get avalidateSubPieceCount {
    if (_subPiecesCount == 0) return 0;
    return _subPiecesQueue.length;
  }

  bool get isCompleted {
    if (subPiecesCount == 0) return false;
    return _downloadedSubPieces.length == subPiecesCount;
  }

  ///
  /// 子Piece下载完成。
  ///
  /// 将子piece放入 `_writtingSubPieces` 队列中
  /// 设置子Piece为完成状态。如果该子Piece已经设置过，返回`false`,没有设置
  /// 过说明设置成功，返回`true`
  bool subPieceDownloadComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    _subPiecesQueue.remove(subindex);
    return _writtingSubPieces.add(subindex);
    // var re = _downloadedSubPieces.add(subindex);
    // if (isCompleted) {
    //   clearAvalidatePeer();
    // }
    // return re;
  }

  bool subPieceWriteComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    _writtingSubPieces.remove(subindex);
    var re = _downloadedSubPieces.add(subindex);
    if (isCompleted) {
      clearAvalidatePeer();
    }
    return re;
  }

  ///
  ///子Piece [subIndex]是否还在。
  ///
  ///当子Piece被弹出栈用于下载，或者子Piece已经下载完成，那么就视为该Piece已经不再包含该子Piece
  bool containsSubpiece(int subIndex) {
    return subPieceQueue?.contains(subIndex);
  }

  bool containsAvalidatePeer(String id) {
    return _avalidatePeers.contains(id);
  }

  bool removeSubpiece(int subIndex) {
    return subPieceQueue?.remove(subIndex);
  }

  void addAvalidatePeers(List<String> peers) {
    peers.forEach((id) {
      _avalidatePeers.add(id);
    });
  }

  void removeAvalidatePeers(List<String> peers) {
    peers.forEach((id) {
      _avalidatePeers.remove(id);
    });
  }

  bool addAvalidatePeer(String id) {
    return _avalidatePeers.add(id);
  }

  bool removeAvalidatePeer(String id) {
    return _avalidatePeers.remove(id);
  }

  void clearAvalidatePeer() {
    _avalidatePeers.clear();
  }

  int popSubPiece() {
    return subPieceQueue.removeFirst();
  }

  void pushSubPiece(int subIndex) {
    if (subPieceQueue.contains(subIndex)) return;
    subPieceQueue.addFirst(subIndex);
  }

  int popLastSubPiece() {
    return subPieceQueue.removeLast();
  }

  void pushSubPieceLast(int index) {
    if (subPieceQueue.contains(index)) return;
    subPieceQueue.addLast(index);
  }

  @override
  int get hashCode => hashString.hashCode;

  @override
  bool operator ==(b) {
    if (b is Piece) {
      return b.hashString == hashString;
    }
    return false;
  }
}
