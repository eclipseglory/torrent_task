import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';
import 'package:torrent_model/torrent_model.dart';
import '../peer/bitfield.dart';

const BITFIELD_TYPE = 'bitfield';
const DOWNLOADED_TYPE = 'downloaded';
const UPLOADED_TYPE = 'uploaded';

///
/// 下载状态保存文件
///
/// 文件内容：`<bitfield><download>`,其中`<download>`是一个64位整数，
/// 文件名：`<infohash>.bt.state`
class StateFile {
  Bitfield _bitfield;

  bool _closed = false;

  int _uploaded = 0;

  final Torrent metainfo;

  StateFile(this.metainfo);

  RandomAccessFile _access;

  File _bitfieldFile;

  StreamSubscription _ss;

  StreamController _sc;

  bool get isClosed => _closed;

  static Future<StateFile> getStateFile(
      String directoryPath, Torrent metainfo) async {
    var stateFile = StateFile(metainfo);
    await stateFile.init(directoryPath, metainfo);
    return stateFile;
  }

  Bitfield get bitfield => _bitfield;

  int get downloaded {
    var _downloaded = bitfield.completedPieces.length * metainfo.pieceLength;
    if (bitfield.completedPieces.contains(bitfield.piecesNum - 1)) {
      _downloaded -= metainfo.pieceLength - metainfo.lastPriceLength;
    }
    return _downloaded;
  }

  int get uploaded => _uploaded;

  Future<File> init(String directoryPath, Torrent metainfo) async {
    var lastc = directoryPath.substring(directoryPath.length - 1);
    if (lastc != '\\' || lastc != '/') {
      directoryPath = directoryPath + '\\\\';
    }

    _bitfieldFile = File('${directoryPath}${metainfo.infoHash}.bt.state');
    var exists = await _bitfieldFile.exists();
    if (!exists) {
      _bitfieldFile = await _bitfieldFile.create(recursive: true);
      _bitfield = Bitfield.createEmptyBitfield(metainfo.pieces.length);
      _uploaded = 0;
      var acc = await _bitfieldFile.open(mode: FileMode.writeOnly);
      acc = await acc.truncate(_bitfield.length + 8);
      await acc.close();
    } else {
      var bytes = await _bitfieldFile.readAsBytes();
      var piecesNum = metainfo.pieces.length;
      var bitfieldBufferLength = piecesNum ~/ 8;
      if (bitfieldBufferLength * 8 != piecesNum) bitfieldBufferLength++;
      _bitfield = Bitfield.copyFrom(piecesNum, bytes, 0, bitfieldBufferLength);
      var view = ByteData.view(bytes.buffer);
      _uploaded = view.getUint64(_bitfield.length);
    }

    return _bitfieldFile;
  }

  Future<bool> update(int index, {bool have = true, int uploaded = 0}) async {
    _access = await getAccess();
    var completer = Completer<bool>();
    _sc.add({
      'type': 'single',
      'index': index,
      'uploaded': uploaded,
      'have': have,
      'completer': completer
    });
    return completer.future;
  }

  Future<bool> updateAll(List<int> indices,
      {List<bool> have, int uploaded = 0}) async {
    _access = await getAccess();
    var completer = Completer<bool>();
    _sc.add({
      'type': 'all',
      'indices': indices,
      'uploaded': uploaded,
      'have': have,
      'completer': completer
    });
    return completer.future;
  }

  @Deprecated('dont use this method , I dont test it')
  Future<void> _updateAll(event) async {
    List<int> indices = event['indices'];
    int uploaded = event['uploaded'];
    List<bool> haves = event['have'];
    Completer c = event['completer'];
    for (var i = 0; i < indices.length; i++) {
      if (haves == null) {
        _bitfield.setBit(indices[i], true);
      } else {
        _bitfield.setBit(indices[i], haves[i]);
      }
    }
    _uploaded = uploaded;
    try {
      var access = await getAccess();
      await access.setPosition(0);
      await access.writeFrom(_bitfield.buffer);
      await access.setPosition(_bitfield.buffer.length);
      var data = Uint8List(8);
      var d = ByteData.view(data.buffer);
      d.setUint64(0, uploaded);
      access = await access.writeFrom(data);
      await access.flush();
      c.complete(true);
    } catch (e) {
      c.complete(false);
    }
    return;
  }

  Future<void> _update(event) async {
    int index = event['index'];
    int uploaded = event['uploaded'];
    bool have = event['have'];
    Completer c = event['completer'];
    if (index != -1) {
      if (_bitfield.getBit(index) == have && _uploaded == uploaded) {
        c.complete(false);
        return;
      }
      _bitfield.setBit(index, have);
    } else {
      if (_uploaded == uploaded) return false;
    }
    _uploaded = uploaded;
    try {
      var access = await getAccess();
      if (index != -1) {
        var i = index ~/ 8;
        await access.setPosition(i);
        await access.writeByte(_bitfield.buffer[i]);
      }
      await access.setPosition(_bitfield.buffer.length);
      var data = Uint8List(8);
      var d = ByteData.view(data.buffer);
      d.setUint64(0, uploaded);
      access = await access.writeFrom(data);
      await access.flush();
      c.complete(true);
    } catch (e) {
      log('Update bitfield piece:[$index],uploaded:$uploaded error :',
          error: e, name: runtimeType.toString());
      c.complete(false);
    }
    return;
  }

  Future<bool> updateBitfield(int index, [bool have = true]) async {
    if (_bitfield.getBit(index) == have) return false;
    return update(index, have: have, uploaded: _uploaded);
  }

  // Future<bool> updateBitfields(List<int> indices, [List<bool> haves]) async {
  //   return updateAll(indices, have: haves, uploaded: _uploaded);
  // }

  Future<bool> updateUploaded(int uploaded) async {
    if (_uploaded == uploaded) return false;
    return update(-1, uploaded: uploaded);
  }

  void _processRequest(event) async {
    _ss.pause();
    // if (event['type'] == 'all') {
    //   await _updateAll(event);
    // }
    if (event['type'] == 'single') {
      await _update(event);
    }
    _ss.resume();
  }

  Future<RandomAccessFile> getAccess() async {
    if (_access == null) {
      _access = await _bitfieldFile.open(mode: FileMode.writeOnlyAppend);
      _sc = StreamController();
      _ss = _sc.stream.listen(_processRequest, onError: (e) => print(e));
    }
    return _access;
  }

  Future<void> close() async {
    if (isClosed) return;
    _closed = true;
    try {
      await _ss?.cancel();
      await _sc?.close();
      await _access?.flush();
      await _access?.close();
    } catch (e) {
      log('关闭状态文件出错：', error: e, name: runtimeType.toString());
    } finally {
      _access = null;
      _ss = null;
      _sc = null;
    }
  }

  Future<FileSystemEntity> delete() async {
    await close();
    var r = _bitfieldFile?.delete();
    _bitfieldFile = null;
    return r;
  }
}
