import 'dart:collection';

import '../utils.dart';

class Piece {
  final String hashString;

  final int byteLength;

  final int index;

  final Set<String> _avalidatePeers = <String>{};

  late Queue<int> _subPiecesQueue;

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
  /// SubPiece download completed.
  ///
  /// Put the subpiece into the _writtingSubPieces queue and mark it as completed.
  /// If the subpiece has already been marked, return false; if it hasn't been marked
  /// yet, mark it as completed and return true.
  bool subPieceDownloadComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    _subPiecesQueue.remove(subindex);
    return _writtingSubPieces.add(subindex);
  }

  bool subPieceWriteComplete(int begin) {
    var subindex = begin ~/ DEFAULT_REQUEST_LENGTH;
    // _subPiecesQueue.remove(subindex); // Is this possible?
    _writtingSubPieces.remove(subindex);
    var re = _downloadedSubPieces.add(subindex);
    if (isCompleted) {
      clearAvalidatePeer();
    }
    return re;
  }

  ///
  /// Whether the sub-piece [subIndex] is still available.
  ///
  /// When a sub-piece is popped from the stack for download or if the sub-piece has already been downloaded,
  /// the piece is considered to no longer contain that sub-piece.
  bool containsSubpiece(int subIndex) {
    return subPieceQueue.contains(subIndex);
  }

  bool containsAvalidatePeer(String id) {
    return _avalidatePeers.contains(id);
  }

  bool removeSubpiece(int subIndex) {
    return subPieceQueue.remove(subIndex);
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

  int? popSubPiece() {
    if (subPieceQueue.isNotEmpty) return subPieceQueue.removeFirst();
    return null;
  }

  bool pushSubPiece(int subIndex) {
    if (subPieceQueue.contains(subIndex) ||
        _writtingSubPieces.contains(subIndex) ||
        _downloadedSubPieces.contains(subIndex)) return false;
    subPieceQueue.addFirst(subIndex);
    return true;
  }

  int? popLastSubPiece() {
    if (subPieceQueue.isNotEmpty) return subPieceQueue.removeLast();
    return null;
  }

  bool pushSubPieceLast(int index) {
    if (subPieceQueue.contains(index) ||
        _writtingSubPieces.contains(index) ||
        _downloadedSubPieces.contains(index)) return false;
    subPieceQueue.addLast(index);
    return true;
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  void dispose() {
    if (isDisposed) return;
    _disposed = true;
    _avalidatePeers.clear();
    _downloadedSubPieces.clear();
    _writtingSubPieces.clear();
  }

  @override
  int get hashCode => hashString.hashCode;

  @override
  bool operator ==(other) {
    if (other is Piece) {
      return other.hashString == hashString;
    }
    return false;
  }
}
