import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:torrent_client/src/file/download_file.dart';
import 'package:torrent_client/src/peer/bitfield.dart';
import 'package:torrent_client/src/file/state_file.dart';
import 'package:torrent_client/src/piece/piece.dart';
import 'package:torrent_client/src/utils.dart';
import 'package:torrent_model/torrent_model.dart';

void main() {
  group('Bitfield test - ', () {
    Bitfield bitfield;
    var pieces = 123; // 不要给8的倍数
    setUp(() {
      bitfield = Bitfield.createEmptyBitfield(pieces);
    });

    test('Init bitfield', () {
      var c = pieces ~/ 8;
      if (c * 8 != pieces) c++;
      print('check buffer length');
      assert(bitfield.buffer.length == c);
      bitfield.buffer.forEach((element) {
        assert(element == 0);
      });
    });

    test('random set/get test, and check the complete index ', () {
      var t = Random(); //放大范围
      var randomIndex = <int>{};
      for (var i = 0; i < pieces; i++) {
        var index = t.nextInt(pieces * 2);
        if (index >= pieces) {
          bitfield.setBit(index, true);
          assert(bitfield.getBit(index) == false);
          bitfield.setBit(index, false);
          assert(bitfield.getBit(index) == false);
        } else {
          randomIndex.add(index);
          bitfield.setBit(index, true);
          assert(bitfield.getBit(index) == true);
        }
      }
      var indexList = randomIndex.toList();
      indexList.sort((a, b) => a - b);
      print('check toString...:');

      var list = bitfield.completedPieces;
      print('Check completed index list...');
      for (var i = 0; i < indexList.length; i++) {
        assert(indexList[i] == list[i]);
      }

      assert(bitfield.haveCompletePiece());
      print('Check bitfield value...');
      list.forEach((index) {
        assert(bitfield.getBit(index));
      });
      var tempList = [];
      tempList.addAll(list);
      tempList.forEach((index) {
        bitfield.setBit(index, false);
      });
      print('Clean all bitfield...');
      bitfield.buffer.forEach((element) {
        assert(element == 0);
      });
    });

    test('add/remote complete list', () {
      var t = Random(); //放大范围
      var randomIndex = <int>{};
      for (var i = 0; i < pieces; i++) {
        var index = t.nextInt(pieces * 2);
        if (index >= pieces) {
          bitfield.setBit(index, true);
          assert(bitfield.getBit(index) == false);
          bitfield.setBit(index, false);
          assert(bitfield.getBit(index) == false);
        } else {
          randomIndex.add(index);
          bitfield.setBit(index, true);
          assert(bitfield.getBit(index) == true);
        }
      }

      bitfield.completedPieces;
      bitfield.setBit(t.nextInt(pieces * 2), true);
      var length = bitfield.completedPieces.length;
      bitfield.setBit(bitfield.completedPieces.last, true);
      assert(length == bitfield.completedPieces.length);
      bitfield.setBit(bitfield.completedPieces.first, true);
      assert(length == bitfield.completedPieces.length);
      var first = bitfield.completedPieces.first;
      bitfield.setBit(bitfield.completedPieces.first, false);
      assert(!bitfield.completedPieces.contains(first));
    });
  });

  group('Piece test - ', () {
    test('create sub-pieces', () {
      // 能整除的
      var totalsize = 163840;
      var remain = Random().nextInt(100);
      totalsize = totalsize + remain;
      var p = Piece('aaaaaaa', 0, totalsize);
      var size = DEFAULT_REQUEST_LENGTH;
      var subIndex = p.popSubPiece();
      subIndex = p.popLastSubPiece();
      var begin = subIndex * size;
      if ((begin + size) > p.byteLength) {
        size = p.byteLength - begin;
        assert(remain == size);
      }
    });

    test('piece length less than 16kb', () {
      var p = Piece('aaaaaaa', 0, DEFAULT_REQUEST_LENGTH - 100);
      var l = p.avalidateSubPieceCount;
      assert(l == 1);
      var sp = p.popSubPiece();
      assert(sp == 0);
      assert(!p.haveAvalidateSubPiece());
    });
  });

  group('test same piece find - ', () {
    var pieces = 123; // 不要给8的倍数
    var bitfieldList = List<Bitfield>(10);
    // 模拟多个peer的bitfield：
    setUp(() {
      for (var i = 0; i < bitfieldList.length; i++) {
        bitfieldList[i] = Bitfield.createEmptyBitfield(pieces);
      }

      bitfieldList.forEach((bitfield) {
        var t = Random();
        var randomIndex = <int>{};
        for (var i = 0; i < pieces; i++) {
          var index = t.nextInt(pieces);
          if (index >= pieces) {
            bitfield.setBit(index, true);
            assert(bitfield.getBit(index) == false);
            bitfield.setBit(index, false);
            assert(bitfield.getBit(index) == false);
          } else {
            randomIndex.add(index);
            bitfield.setBit(index, true);
            assert(bitfield.getBit(index) == true);
          }
        }
      });
    });

    test('ramdon pieces', () {
      bitfieldList.forEach((element) => print(element.toString()));
    });
  });

  group('StateFile Test - ', () {
    var directory = 'test';
    // var torrent = await Torrent.parse('$directory/sample3.torrent');
    Torrent torrent;
    setUpAll(() async {
      torrent = await Torrent.parse('$directory/test4.torrent');
      var f = File('$directory/${torrent.infoHash}.bt.state');
      if (await f.exists()) await f.delete();
    });
    test('Write/Read StateFile', () async {
      var stateFile = await StateFile.getStateFile(directory, torrent);
      var b = torrent.pieces.length ~/ 8;
      if (b * 8 != torrent.pieces.length) b++;
      assert(stateFile.bitfield.length == b);
      assert(stateFile.bitfield.piecesNum == torrent.pieces.length);
      assert(!stateFile.bitfield.haveCompletePiece());

      await stateFile.close();
      // 测试建立空文件后读取内容
      stateFile = await StateFile.getStateFile(directory, torrent);
      b = torrent.pieces.length ~/ 8;
      if (b * 8 != torrent.pieces.length) b++;
      assert(stateFile.bitfield.length == b);
      assert(stateFile.bitfield.piecesNum == torrent.pieces.length);
      assert(!stateFile.bitfield.haveCompletePiece());
      assert(stateFile.downloaded == 0);
      assert(stateFile.uploaded == 0);

      var updatePiece = <int>{};
      for (var i = 0; i < stateFile.bitfield.piecesNum ~/ 4; i++) {
        var index = randomInt(stateFile.bitfield.piecesNum);
        updatePiece.add(index);
        await stateFile.updateBitfield(index, true);
      }
      await stateFile.updateBitfield(stateFile.bitfield.piecesNum - 1);
      updatePiece.add(stateFile.bitfield.piecesNum - 1);
      var updateList = updatePiece.toList();
      updateList.sort((a, b) => a - b);
      var list = stateFile.bitfield.completedPieces;
      assert(list.length == updateList.length);
      await stateFile.updateUploaded(987654321);
      assert(stateFile.uploaded == 987654321);

      await stateFile.close();
      // await stateFile.close(); //关闭两次会怎样？
      var f = File('$directory/${torrent.infoHash}.bt.state');
      var locker = Completer();
      var data = <int>[];
      f.openRead().listen((event) {
        data.addAll(event);
      }, onDone: () {
        var nb = Bitfield.copyFrom(
            stateFile.bitfield.piecesNum, stateFile.bitfield.buffer);
        for (var i = 0; i < nb.completedPieces.length; i++) {
          assert(nb.completedPieces[i] == updateList[i]);
        }
        var v = ByteData.view(Uint8List.fromList(data).buffer);
        var offset = stateFile.bitfield.buffer.length;
        var re = v.getUint64(offset);
        assert(re == stateFile.uploaded);
        locker.complete();
      }, onError: (e) => locker.complete());
      await locker.future;

      stateFile = await StateFile.getStateFile(directory, torrent);
      b = torrent.pieces.length ~/ 8;
      if (b * 8 != torrent.pieces.length) b++;
      assert(stateFile.bitfield.length == b);
      var sd = stateFile.bitfield.completedPieces.length * torrent.pieceLength;
      sd = sd - (torrent.pieceLength - torrent.lastPriceLength);
      assert(stateFile.downloaded == sd);
      print('download: $sd');
      assert(stateFile.uploaded == 987654321);

      for (var i = 0; i < stateFile.bitfield.completedPieces.length; i++) {
        assert(stateFile.bitfield.completedPieces[i] == updateList[i]);
      }
    });

    test('Delete StateFile', () async {
      var stateFile = await StateFile.getStateFile(directory, torrent);
      var t = File('$directory/${torrent.infoHash}.bt.state');
      assert(await t.exists());
      await stateFile.delete();
      assert(!await t.exists());
    });
  });

  group('Temp file access - ', () {
    test('Create/Read/Write/Delete', () async {
      var content = 'DART-TORRENT-CLIENT';
      var buffer = utf8.encode(content);
      var file = DownloadFile('test/test.txt', 0, buffer.length);
      assert(await file.requestWrite(0, buffer, 0, buffer.length));
      var bytes = await file.requestRead(0, buffer.length);
      var result = String.fromCharCodes(bytes);
      assert(result == content, '验证读取内容错误');
      await file.close();
      var file1 = File('test/test.txt');
      assert(await file1.exists());
      var b = <int>[];
      var lock = Completer();
      file1.openRead().listen((data) {
        b.addAll(data);
      }, onDone: () {
        var result = String.fromCharCodes(b);
        assert(result == content, '验证文件内容错误');
        lock.complete();
      });
      await lock.future;
      await file.delete();
      file1 = File('test/test.txt');
      assert(!await file1.exists(), '文件删除错误');
    });
  });
}
