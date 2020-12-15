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

  int _downloaded = 0;

  int _uploaded = 0;

  StateFile();

  RandomAccessFile _access;

  File _bitfieldFile;

  StreamSubscription _ss;

  StreamController _sc;

  static Future<StateFile> getStateFile(
      String directoryPath, Torrent metainfo) async {
    var stateFile = StateFile();
    await stateFile.init(directoryPath, metainfo);
    return stateFile;
  }

  Bitfield get bitfield => _bitfield;

  int get downloaded => _downloaded;

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
      _access = await _bitfieldFile.open(mode: FileMode.write);
      _bitfield = Bitfield.createEmptyBitfield(metainfo.pieces.length);
      _access = await _access.writeFrom(_bitfield.buffer);
      // 不必写入，写入0，不会增加文件长度
      // _access = await _access.setPosition(_bitfield.buffer.length - 1);
      // var d = Uint8List(16);
      // _access = await _access.writeFrom(d);
      await _access.close();
      _access = null;
    } else {
      // 注意，如果上传和下载都是0，会导致整个文件长度仅有bitfield的buffer长度
      var bytes = await _bitfieldFile.readAsBytes();
      var piecesNum = metainfo.pieces.length;
      var bitfieldBufferLength = piecesNum ~/ 8;
      if (bitfieldBufferLength * 8 != piecesNum) bitfieldBufferLength++;
      _bitfield = Bitfield.copyFrom(piecesNum, bytes, 0, bitfieldBufferLength);
      var view = ByteData.view(bytes.buffer);
      try {
        _downloaded = view.getUint64(_bitfield.length);
      } catch (e) {
        _downloaded = 0;
      }
      try {
        _uploaded = view.getUint64(_bitfield.length + 8);
      } catch (e) {
        _uploaded = 0;
        ;
      }
    }

    return _bitfieldFile;
  }

  Future<bool> updateBitfield(int index, [bool have = true]) async {
    if (_bitfield.getBit(index) == have) return false;
    _access = await getAccess();
    var completer = Completer<bool>();
    _sc.add({
      'type': BITFIELD_TYPE,
      'index': index,
      'have': have,
      'completer': completer
    });
    return completer.future;
  }

  Future<void> _updateBitfield(event) async {
    int index = event['index'];
    bool have = event['have'];
    Completer c = event['completer'];
    _bitfield.setBit(index, have);
    try {
      var access = await getAccess();
      await access.setPosition(0);
      await access.writeFrom(_bitfield.buffer);
      await access.flush();
      c.complete(true);
    } catch (e) {
      log('Record bitfield [$index] error :',
          error: e, name: runtimeType.toString());
      c.complete(false);
    }
    return;
  }

  Future<bool> updateDownloaded(int downloaded) async {
    if (_downloaded == downloaded) return false;
    _downloaded = downloaded;
    _access = await getAccess();
    var completer = Completer<bool>();
    _sc.add({
      'type': DOWNLOADED_TYPE,
      'downloaded': downloaded,
      'completer': completer
    });
    return completer.future;
  }

  Future<bool> updateUploaded(int uploaded) async {
    if (_uploaded == uploaded) return false;
    _uploaded = uploaded;
    _access = await getAccess();
    var completer = Completer<bool>();
    _sc.add(
        {'type': UPLOADED_TYPE, 'uploaded': uploaded, 'completer': completer});
    return completer.future;
  }

  Future<void> _updateUploaded(event) async {
    int uploaded = event['uploaded'];
    Completer c = event['completer'];
    try {
      _uploaded = uploaded;
      var access = await getAccess();
      access = await access.setPosition(_bitfield.buffer.length + 8);
      var data = Uint8List(8);
      var d = ByteData.view(data.buffer);
      d.setUint64(0, _uploaded);
      access = await access.writeFrom(data);
      await access.flush();
      c.complete(true);
    } catch (e) {
      log('Record uploaded error :', error: e, name: runtimeType.toString());
      c.complete(false);
    }
    return;
  }

  Future<void> _updateDownloaded(event) async {
    int downloaded = event['downloaded'];
    Completer c = event['completer'];
    try {
      var access = await getAccess();
      access = await access.setPosition(_bitfield.buffer.length);
      var data = Uint8List(8);
      var d = ByteData.view(data.buffer);
      d.setUint64(0, downloaded);
      access = await access.writeFrom(data);
      await access.flush();
      c.complete(true);
    } catch (e) {
      log('Record downloaded error :', error: e, name: runtimeType.toString());
      c.complete(false);
    }
    return;
  }

  void _processRequest(event) async {
    _ss.pause();
    if (event['type'] == BITFIELD_TYPE) {
      await _updateBitfield(event);
    }
    if (event['type'] == DOWNLOADED_TYPE) {
      await _updateDownloaded(event);
    }
    if (event['type'] == UPLOADED_TYPE) {
      await _updateUploaded(event);
    }
    _ss.resume();
  }

  Future<RandomAccessFile> getAccess() async {
    if (_access == null) {
      _access = await _bitfieldFile.open(mode: FileMode.write);
      _sc = StreamController();
      _ss = _sc.stream.listen(_processRequest, onError: (e) => print(e));
    }
    return _access;
  }

  Future<void> close() async {
    try {
      await _ss?.cancel();
      await _sc?.close();
      await _access?.close();
    } catch (e) {
      print(e);
    } finally {
      _access = null;
      _ss = null;
      _sc = null;
    }
  }

  Future<FileSystemEntity> delete() async {
    await close();
    return _bitfieldFile?.delete();
  }
}
