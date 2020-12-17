import 'dart:async';
import 'dart:developer';
import 'dart:io';

const ONE_M = 1024 * 1024;

const READ = 'read';
const WRITE = 'write';

typedef FileDownloadCompleteHandle = void Function(String filePath);

class DownloadFile {
  final String filePath;

  final int start;

  final int length;

  int _bufferSize = 0;

  RandomAccessFile _randomAccess;

  RandomAccessFile _readAccess;

  int _totalDownloaded = 0;

  int _totalUploaded = 0;

  final List<FileDownloadCompleteHandle> _fileDownloadCompleteHandle = [];

  StreamController _sc;

  StreamSubscription _ss;

  DownloadFile(this.filePath, this.start, this.length);

  int get end => start + length;

  /// Notify this class write the [block] (from [start] to [end]) into the downloading file ,
  /// content start position is [position]
  ///
  /// **NOTE** :
  ///
  /// Invoke this method does not mean this class should write content immeditelly , it will wait for other
  /// `READ`/`WRITE` which first come in the operation stack completing.
  ///
  Future<bool> requestWrite(
      int position, List<int> block, int start, int end, int pieceIndex) async {
    _randomAccess ??= await _getRandomAccessFile(WRITE);
    var completer = Completer<bool>();
    _sc.add({
      'type': WRITE,
      'position': position,
      'block': block,
      'start': start,
      'end': end,
      'completer': completer
    });
    return completer.future;
  }

  Future<List<int>> requestRead(
      int position, int length, int pieceIndex) async {
    _readAccess ??= await _getRandomAccessFile(READ);
    var completer = Completer<List<int>>();
    _sc.add({
      'type': READ,
      'position': position,
      'length': length,
      'completer': completer
    });
    return completer.future;
  }

  /// 处理读写请求
  ///
  /// 每次只处理一个请求。`Stream`在进入该方法后通过`StreamSubscription`暂停通道信息读取，直到处理完一条请求后才恢复
  void _processRequest(event) async {
    _ss.pause();
    if (event['type'] == WRITE) {
      await _write(event);
    } else {
      if (event['type'] == READ) {
        await _read(event);
      }
    }
    _ss.resume();
  }

  void onFileDownloadCompleteHandle(FileDownloadCompleteHandle handle) {
    _fileDownloadCompleteHandle.add(handle);
  }

  void offFileDownloadCompleteHandle(FileDownloadCompleteHandle handle) {
    _fileDownloadCompleteHandle.remove(handle);
  }

  void _write(event) async {
    Completer completer = event['completer'];
    try {
      int position = event['position'];
      int start = event['start'];
      int end = event['end'];
      List<int> block = event['block'];

      _randomAccess = await _getRandomAccessFile(WRITE);
      _randomAccess = await _randomAccess.setPosition(position);
      _randomAccess = await _randomAccess.writeFrom(block, start, end);
      _bufferSize += block.length;
      _totalDownloaded += block.length;
      if (_bufferSize >= ONE_M) {
        await _randomAccess.flush();
        _bufferSize = 0;
      }
      if (_totalDownloaded >= length) {
        _fileDownloadCompleteHandle.forEach((handle) {
          Timer.run(() => handle(filePath));
        });
      }
      completer.complete(true);
    } catch (e) {
      log('Write file error:', error: e, name: runtimeType.toString());
      completer.complete(false);
    }
  }

  void _read(event) async {
    Completer completer = event['completer'];
    try {
      int position = event['position'];
      int length = event['length'];

      var access = await _getRandomAccessFile(READ);
      access = await access.setPosition(position);
      var contents = await access.read(length);
      _totalUploaded += length;
      completer.complete(contents);
    } catch (e) {
      log('Read file error:', error: e, name: runtimeType.toString());
      completer.complete(<int>[]);
    }
  }

  Future<RandomAccessFile> _getRandomAccessFile(String type) async {
    var file = File(filePath);
    var exists = await file.exists();
    if (!exists) {
      file = await file.create(recursive: true);
    }
    var access;
    if (type == WRITE) {
      _randomAccess ??= await file.open(mode: FileMode.write);
      access = _randomAccess;
    } else if (type == READ) {
      _readAccess ??= await file.open(mode: FileMode.read);
      access = _readAccess;
    }
    if (_sc == null) {
      _sc = StreamController();
      _ss = _sc.stream.listen(_processRequest);
    }
    return access;
  }

  Future close() async {
    try {
      await _ss?.cancel();
      await _sc?.close();
      await _randomAccess?.flush();
      await _randomAccess?.close();
      await _readAccess?.flush();
      await _readAccess?.close();
    } catch (e) {
      log('Close file error:', error: e, name: runtimeType.toString());
    } finally {
      _randomAccess = null;
      _readAccess = null;
      _ss = null;
      _sc = null;
    }
    return;
  }

  Future delete() async {
    await close();
    var file = File(filePath);
    var exists = await file.exists();
    if (exists) return file.delete();
  }
}
