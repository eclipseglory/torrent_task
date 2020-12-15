import 'dart:async';
import 'dart:developer';

import 'package:torrent_client/src/peer/bitfield.dart';
import 'package:torrent_model/torrent_model.dart';

import 'download_file.dart';
import 'state_file.dart';

typedef SubPieceCompleteHandle = void Function(
    int pieceIndex, int begin, int length);

typedef SubPieceReadHandle = void Function(
    int pieceIndex, int begin, List<int> block);

class DownloadFileManager {
  final Torrent metainfo;

  final Map<int, List<DownloadFile>> _piece2fileMap = {};

  final List<SubPieceCompleteHandle> _subPieceCompleteHandles = [];

  final List<SubPieceReadHandle> _subPieceReadHandles = [];

  final List<void Function(String path)> _fileWriteCompleteHandles = [];

  final List<void Function()> _allCompleteHandles = [];

  int _totalDownloaded = 0;

  final StateFile _stateFile;

  /// TODO
  /// - 没有建立文件读取缓存
  DownloadFileManager(this.metainfo, this._stateFile);

  static Future<DownloadFileManager> createFileManager(
      Torrent metainfo, String localDirectory, StateFile stateFile) {
    var manager = DownloadFileManager(metainfo, stateFile);
    manager._totalDownloaded = stateFile.downloaded;
    return manager._init(localDirectory);
  }

  Future<DownloadFileManager> _init(String directory) async {
    var lastc = directory.substring(directory.length - 1);
    if (lastc != '\\' || lastc != '/') {
      directory = directory + '\\';
    }
    _initFileMap(directory);
    return this;
  }

  Bitfield get localBitfield => _stateFile.bitfield;

  bool localHave(int index) {
    return _stateFile.bitfield.getBit(index);
  }

  int get piecesNumber => _stateFile.bitfield.piecesNum;

  void _subPieceWriteComplete(int pieceIndex, int begin, int length) {
    _totalDownloaded += length;

    _subPieceCompleteHandles.forEach((handle) {
      Timer.run(() => handle(pieceIndex, begin, length));
    });
    _stateFile.updateDownloaded(_totalDownloaded);
    log('已写入磁盘 : ${_totalDownloaded / ONE_M}MB ， ${((_totalDownloaded / metainfo.length) * 10000).toInt() / 100}%',
        name: runtimeType.toString());
    if (_totalDownloaded >= metainfo.length) {
      log('所有内容下载完成 ${metainfo.name}');
      _allCompleteHandles.forEach((handle) {
        handle();
      });
    }
  }

  Future<bool> updateBitfield(int index, [bool have = true]) {
    return _stateFile.updateBitfield(index, have);
  }

  Future<bool> updateUpload(int uploaded) {
    return _stateFile.updateUploaded(uploaded);
  }

  void _subPieceReadComplete(int pieceIndex, int begin, List<int> block) {
    _subPieceReadHandles.forEach((h) {
      Timer.run(() => h(pieceIndex, begin, block));
    });
  }

  void _initFileMap(String directory) {
    for (var i = 0; i < metainfo.files.length; i++) {
      var file = metainfo.files[i];
      var df = DownloadFile(directory + file.path, file.offset, file.length);
      df.onFileDownloadCompleteHandle(_fileWriteComplete);
      var fs = df.start;
      var fe = df.end;
      var startPiece = fs ~/ metainfo.pieceLength;
      var endPiece = fe ~/ metainfo.pieceLength;
      if (fe.remainder(metainfo.pieceLength) == 0) endPiece--;
      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var l = _piece2fileMap[pieceIndex];
        if (l == null) {
          l = <DownloadFile>[];
          _piece2fileMap[pieceIndex] = l;
        }
        l.add(df);
      }
    }
  }

  void _fileWriteComplete(String path) {
    _fileWriteCompleteHandles.forEach((handle) {
      Timer.run(() => handle(path));
    });
  }

  void onFileWriteComplete(void Function(String path) handle) {
    _fileWriteCompleteHandles.add(handle);
  }

  void offFileWriteComplete(void Function(String path) handle) {
    _fileWriteCompleteHandles.remove(handle);
  }

  void onAllComplete(void Function() handle) {
    _allCompleteHandles.add(handle);
  }

  void offAllComplete(void Function() handle) {
    _allCompleteHandles.remove(handle);
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

  void readFile(int pieceIndex, int begin, int length) {
    var tempFiles = _piece2fileMap[pieceIndex];
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var pe = ps + length;
    if (tempFiles == null || tempFiles.isEmpty) return;
    var futures = <Future>[];
    for (var i = 0; i < tempFiles.length; i++) {
      var tempFile = tempFiles[i];
      var re = _mapTempFilePosition(ps, pe, length, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures
          .add(tempFile.requestRead(position, subend - substart, pieceIndex));
    }
    Stream.fromFutures(futures).fold<List<int>>(<int>[], (previous, element) {
      if (element != null && element is List<int>) previous.addAll(element);
      return previous;
    }).then((re) => _subPieceReadComplete(pieceIndex, begin, re));
    return;
  }

  ///
  /// 将`Sub Piece`的内容写入文件中。
  ///
  /// 该`Sub Piece`是来自于[pieceIndex]对应的`Piece`，内容为[block],起始位置是[begin]。
  /// 该类不会去验证写入的Sub Piece是否重复，重复内容直接覆盖之前内容
  void writeFile(int pieceIndex, int begin, List<int> block) {
    var tempFiles = _piece2fileMap[pieceIndex];
    var ps = pieceIndex * metainfo.pieceLength + begin;
    var pe = ps + block.length;
    if (tempFiles == null || tempFiles.isEmpty) return;
    var futures = <Future>[];
    for (var i = 0; i < tempFiles.length; i++) {
      var tempFile = tempFiles[i];
      var re = _mapTempFilePosition(ps, pe, block.length, tempFile);
      if (re == null) continue;
      var substart = re['begin'];
      var position = re['position'];
      var subend = re['end'];
      futures.add(
          tempFile.requestWrite(position, block, substart, subend, pieceIndex));
    }
    Stream.fromFutures(futures).toList().then(
        (values) => _subPieceWriteComplete(pieceIndex, begin, block.length));
    return;
  }

  Map _mapTempFilePosition(
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

  Future<List> close() {
    var l = <Future>[];
    l.add(_stateFile?.close());
    _piece2fileMap.forEach((key, value) {
      value.forEach((DownloadFile downloadFile) {
        l.add(downloadFile?.close());
      });
    });
    _fileWriteCompleteHandles.clear();
    _subPieceCompleteHandles.clear();
    _subPieceReadHandles.clear();
    _allCompleteHandles.clear();
    return Stream.fromFutures(l).toList();
  }

  Future delete() {
    var l = <Future>[];
    l.add(close());
    _stateFile?.delete();
    _piece2fileMap.forEach((key, value) {
      value.forEach((DownloadFile downloadFile) {
        l.add(downloadFile?.delete());
      });
    });
    return Stream.fromFutures(l).toList();
  }
}
