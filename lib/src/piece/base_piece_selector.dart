import '../utils.dart';
import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

///
/// `Piece`基础选择器。
///
/// 基本策略为：
///
/// - `Piece`可用`Peer`数量最多
/// - 在可用`Peer`数量都相同的情况下，选用`Sub Piece`数量最少的
class BasePieceSelector implements PieceSelector {
  @override
  Piece selectPiece(
      String remotePeerId, List<int> piecesIndexList, PieceProvider provider,
      [bool random = false]) {
    // random = true;
    var maxList = <Piece>[];
    var a;
    var startIndex;
    for (var i = 0; i < piecesIndexList.length; i++) {
      var p = provider[piecesIndexList[i]];
      if (p != null && p.haveAvalidateSubPiece() && p.haveAvalidatePeers()) {
        a = p;
        startIndex = i;
        break;
      }
    }
    if (startIndex == null) return null;
    maxList.add(a);
    for (var i = startIndex; i < piecesIndexList.length; i++) {
      var p = provider[piecesIndexList[i]];
      if (p == null || !p.haveAvalidateSubPiece() || !p.haveAvalidatePeers()) {
        continue;
      }
      // 选择稀有piece
      if (a.avalidatePeersCount > p.avalidatePeersCount) {
        if (!random) return p;
        maxList.clear();
        a = p;
        maxList.add(a);
      } else {
        if (a.avalidatePeersCount == p.avalidatePeersCount) {
          // 如果同样数量可用下载peer的piece所具有的sub piece少，优先处理
          if (p.avalidateSubPieceCount < a.avalidateSubPieceCount) {
            if (!random) return p;
            maxList.clear();
            a = p;
            maxList.add(a);
          } else {
            if (p.avalidateSubPieceCount == a.avalidateSubPieceCount) {
              if (!random) return p;
              maxList.add(p);
              a = p;
            }
          }
        }
      }
    }
    if (random) {
      return maxList[randomInt(maxList.length)];
    }
    return a;
  }
}
