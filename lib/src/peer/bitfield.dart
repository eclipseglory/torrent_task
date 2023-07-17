import 'dart:typed_data';

/// 用来于的基础数字，靠右移动获取要`&`和`|`的数
///
/// 即：10000000
const BASE_NUM = 128;

class Bitfield {
  final int piecesNum;
  final Uint8List buffer;

  List<int>? _completedIndex;
  Bitfield(this.piecesNum, this.buffer);

  bool getBit(int index) {
    if (index < 0 || index >= piecesNum) return false;
    var i = index ~/ 8; // 表示第几个数字
    var b = index.remainder(8); // 这表示该数字的第几位bit
    var andNum = BASE_NUM >> b;
    return ((andNum & buffer[i]) != 0); // 等于0说明该位上的数字为0，即false
  }

  ///
  /// [index] 如果不在 [0 - piecesNum]范围内，不会报错，直接返回
  void setBit(int index, bool bit) {
    if (index < 0 || index >= piecesNum) return;
    if (getBit(index) == bit) return;
    var i = index ~/ 8; // 表示第几个数字
    var b = index.remainder(8); // 这表示该数字的第几位bit
    var orNum = BASE_NUM >> b;
    if (bit) {
      _completedIndex = completedPieces;
      _completedIndex?.add(index);
      buffer[i] = buffer[i] | orNum;
    } else {
      _completedIndex?.remove(index);
      buffer[i] = buffer[i] & (~orNum);
    }
  }

  /// 如果有完成的piece就返回ture，不一定会全部检索
  bool haveCompletePiece() {
    for (var i = 0; i < buffer.length; i++) {
      var a = buffer[i];
      if (a != 0) {
        for (var j = 0; j < 8; j++) {
          var index = i * 8 + j;
          if (getBit(index)) return true;
        }
      }
    }
    return false;
  }

  bool haveAll() {
    for (var i = 0; i < buffer.length - 1; i++) {
      var a = buffer[i];
      if (a != 255) {
        return false;
      }
    }
    var last = buffer.length - 1;
    for (var j = 0; j < 8; j++) {
      var index = last * 8 + j;
      if (index >= piecesNum) break;
      if (!getBit(index)) return false;
    }
    return true;
  }

  bool haveNone() {
    return !haveCompletePiece();
  }

  List<int> get completedPieces {
    if (_completedIndex == null) {
      _completedIndex = <int>[];
      for (var i = 0; i < buffer.length; i++) {
        var a = buffer[i];
        if (a != 0) {
          for (var j = 0; j < 8; j++) {
            var index = i * 8 + j;
            if (getBit(index)) {
              _completedIndex?.add(index);
            }
          }
        }
      }
    }
    return _completedIndex!;
  }

  int get length => buffer.length;

  @override
  String toString() {
    return buffer.fold('Bitfield : ', (previousValue, element) {
      var str = element.toRadixString(2);
      var l = str.length;
      for (var i = 0; i < 8 - l; i++) {
        str = '0$str';
      }
      return '$previousValue$str-';
    });
  }

  static Bitfield copyFrom(int piecesNum, List<int> list,
      [int offset = 0, int? end]) {
    var b = piecesNum ~/ 8;
    if (b * 8 != piecesNum) b++;
    var mybuffer = Uint8List(b);
    end ??= mybuffer.length;
    var index = 0;
    for (var i = offset; i < end; i++, index++) {
      mybuffer[index] = list[i];
    }
    return Bitfield(piecesNum, mybuffer);
  }

  static Bitfield createEmptyBitfield(int piecesNum) {
    var b = piecesNum ~/ 8;
    if (b * 8 != piecesNum) b++;
    return Bitfield(piecesNum, Uint8List(b));
  }
}
