import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import '../peer/peer_base.dart';

import 'download_file.dart';
import 'state_file.dart';

typedef SubPieceCompleteHandle = void Function(
    int pieceIndex, int begin, int length);

typedef SubPieceReadHandle = void Function(
    int pieceIndex, int begin, List<int> block);

class DownloadFileManager {
  final Torrent metainfo;

  final Set<DownloadFile> _files = {};

  List<List<DownloadFile>?>? _piece2fileMap;

  final Map<String, List<int>?> _file2pieceMap = {};

  final List<SubPieceCompleteHandle> _subPieceCompleteHandles = [];

  final List<SubPieceCompleteHandle> _subPieceFailedHandles = [];

  final List<SubPieceReadHandle> _subPieceReadHandles = [];

  final List<void Function(String path)> _fileCompleteHandles = [];

  final StateFile _stateFile;

  /// TODO: File read caching
  DownloadFileManager(this.metainfo, this._stateFile) {
    _piece2fileMap = List.filled(_stateFile.bitfield.piecesNum, null);
  }

  static Future<DownloadFileManager> createFileManager(
      Torrent metainfo, String localDirectory, StateFile stateFile) {
    var manager = DownloadFileManager(metainfo, stateFile);
    // manager._totalDownloaded = stateFile.downloaded;
    return manager._init(localDirectory);
  }

  Future<DownloadFileManager> _init(String directory) async {
    var lastc = directory.substring(directory.length - 1);
    if (lastc != Platform.pathSeparator) {
      directory = directory + Platform.pathSeparator;
    }
    _initFileMap(directory);
    return this;
  }

  Bitfield get localBitfield => _stateFile.bitfield;

  bool localHave(int index) {
    return _stateFile.bitfield.getBit(index);
  }

  bool get isAllComplete {
    return _stateFile.bitfield.piecesNum ==
        _stateFile.bitfield.completedPieces.length;
  }

  int get piecesNumber => _stateFile.bitfield.piecesNum;

  void _subPieceWriteComplete(int pieceIndex, int begin, int length) {
    for (var handle in _subPieceCompleteHandles) {
      Timer.run(() => handle(pieceIndex, begin, length));
    }
  }

  void _subPieceWriteFailed(int pieceIndex, int begin, int length) {
    for (var handle in _subPieceFailedHandles) {
      Timer.run(() => handle(pieceIndex, begin, length));
    }
  }

  Future<bool> updateBitfield(int index, [bool have = true]) {
    return _stateFile.updateBitfield(index, have);
  }

  // Future<bool> updateBitfields(List<int> indices, [List<bool> haves]) {
  //   return _stateFile.updateBitfields(indices, haves);
  // }

  Future<bool> updateUpload(int uploaded) {
    return _stateFile.updateUploaded(uploaded);
  }

  void _subPieceReadComplete(int pieceIndex, int begin, List<int> block) {
    for (var h in _subPieceReadHandles) {
      Timer.run(() => h(pieceIndex, begin, block));
    }
  }

  int get downloaded => _stateFile.downloaded;

  /// This method appears to only write the buffer content to the disk, but in
  /// reality,every time the cache is written, it is considered that the [Piece]
  /// corresponding to [pieceIndex] has been completed. Therefore, it will
  /// remove the file's corresponding piece index from the _file2pieceMap. When
  /// all the pieces have been removed, a File Complete event will be triggered.
  Future<bool> flushFiles(Set<int> pieceIndices) async {
    var d = _stateFile.downloaded;
    var flushed = <String>{};
    for (var i = 0; i < pieceIndices.length; i++) {
      var pieceIndex = pieceIndices.elementAt(i);
      var fs = _piece2fileMap?[pieceIndex];
      if (fs == null || fs.isEmpty) continue;
      for (var i = 0; i < fs.length; i++) {
        var file = fs[i];
        var pieces = _file2pieceMap[file.filePath];
        if (pieces == null) continue;
        pieces.remove(pieceIndex);
        if (flushed.add(file.filePath)) {
          await file.requestFlush();
        }
        if (pieces.isEmpty && _file2pieceMap[file.filePath] != null) {
          _file2pieceMap[file.filePath] = null;
          _fireFileComplete(file.filePath);
        }
      }
    }

    var msg =
        'downloaded：${d / (1024 * 1024)} mb , Progress ${((d / metainfo.length) * 10000).toInt() / 100} %';
    log(msg, name: runtimeType.toString());
    return true;
  }

  void onFileComplete(void Function(String) h) {
    _fileCompleteHandles.add(h);
  }

  void offFileComplete(void Function(String) h) {
    _fileCompleteHandles.remove(h);
  }

  void _fireFileComplete(String path) {
    for (var element in _fileCompleteHandles) {
      Timer.run(() => element(path));
    }
  }

  void _initFileMap(String directory) {
    for (var i = 0; i < metainfo.files.length; i++) {
      var file = metainfo.files[i];
      var df = DownloadFile(directory + file.path, file.offset, file.length);
      _files.add(df);
      var fs = df.start;
      var fe = df.end;
      var startPiece = fs ~/ metainfo.pieceLength;
      var endPiece = fe ~/ metainfo.pieceLength;
      var pieces = _file2pieceMap[df.filePath];
      if (pieces == null) {
        pieces = <int>[];
        _file2pieceMap[df.filePath] = pieces;
      }
      if (fe.remainder(metainfo.pieceLength) == 0) endPiece--;
      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var l = _piece2fileMap?[pieceIndex];
        if (l == null) {
          l = <DownloadFile>[];
          _piece2fileMap?[pieceIndex] = l;
          if (localHave(pieceIndex)) pieces.add(pieceIndex);
        }
        l.add(df);
      }
    }
  }

  void onSubPieceReadComplete(SubPieceReadHandle handle) {
    _subPieceReadHandles.add(handle);
  }

  void offSubPieceReadComplete(SubPieceReadHandle handle) {
    _subPieceReadHandles.remove(handle);
  }

  void onSubPieceWriteComplete(SubPieceCompleteHandle handle) {
    _subPieceCompleteHandles.add(handle);
  }

  void offSubPieceWriteComplete(SubPieceCompleteHandle handle) {
    _subPieceCompleteHandles.remove(handle);
  }

  void onSubPieceWriteFailed(SubPieceCompleteHandle handle) {
    _subPieceFailedHandles.add(handle);
  }

  void offSubPieceWriteFailed(SubPieceCompleteHandle handle) {
    _subPieceFailedHandles.remove(handle);
  }

  void readFile(int pieceIndex, int begin, int length) {
    var tempFiles = _piece2fileMap?[pieceIndex];
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var pe = ps + length;
    if (tempFiles == null || tempFiles.isEmpty) return;
    var futures = <Future>[];
    for (var i = 0; i < tempFiles.length; i++) {
      var tempFile = tempFiles[i];
      var re = _mapDownloadFilePosition(ps, pe, length, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures.add(tempFile.requestRead(position, subend - substart));
    }
    Stream.fromFutures(futures).fold<List<int>>(<int>[], (previous, element) {
      if (element != null && element is List<int>) previous.addAll(element);
      return previous;
    }).then((re) => _subPieceReadComplete(pieceIndex, begin, re));
    return;
  }

  ///
  // Writes the content of a Sub Piece to the file. After completion, a sub piece complete event will be sent.
  /// If it fails, a sub piece failed event will be sent.
  ///
  /// The Sub Piece is from the Piece corresponding to [pieceIndex], and the content is [block] starting from [begin].
  /// This class does not validate if the written Sub Piece is a duplicate; it simply overwrites the previous content.
  void writeFile(int pieceIndex, int begin, List<int> block) {
    var tempFiles = _piece2fileMap?[pieceIndex];
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var blockSize = block.length;
    var pe = ps + blockSize;
    if (tempFiles == null || tempFiles.isEmpty) return;
    var futures = <Future<bool>>[];
    for (var i = 0; i < tempFiles.length; i++) {
      var tempFile = tempFiles[i];
      var re = _mapDownloadFilePosition(ps, pe, blockSize, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures.add(tempFile.requestWrite(position, block, substart, subend));
    }
    Stream.fromFutures(futures).fold<bool>(true, (p, a) {
      return p && a;
    }).then((result) {
      if (result) {
        _subPieceWriteComplete(pieceIndex, begin, blockSize);
      } else {
        _subPieceWriteFailed(pieceIndex, begin, blockSize);
      }
    });
    return;
  }

  Map? _mapDownloadFilePosition(
      int pieceStart, int pieceEnd, int length, DownloadFile tempFile) {
    var fs = tempFile.start;
    var fe = fs + tempFile.length;
    if (pieceEnd < fs || pieceStart > fe) return null;
    var position = 0;
    var substart = 0;
    if (fs <= pieceStart) {
      position = pieceStart - fs;
      substart = 0;
    } else {
      position = 0;
      substart = fs - pieceStart;
    }
    var subend = substart;
    if (fe >= pieceEnd) {
      subend = length;
    } else {
      subend = fe - pieceStart;
    }
    return {'position': position, 'begin': substart, 'end': subend};
  }

  Future close() async {
    await _stateFile.close();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.close();
    }
    _clean();
  }

  void _clean() {
    _subPieceCompleteHandles.clear();
    _subPieceFailedHandles.clear();
    _subPieceReadHandles.clear();
    _fileCompleteHandles.clear();
    _file2pieceMap.clear();
    _piece2fileMap = null;
  }

  Future delete() async {
    await _stateFile.delete();
    for (var i = 0; i < _files.length; i++) {
      var file = _files.elementAt(i);
      await file.delete();
    }
    _clean();
  }
}
