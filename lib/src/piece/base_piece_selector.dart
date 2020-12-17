import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

///
/// `Piece`基础选择器。
///
/// 基本策略为：
///
/// - `Piece`可用`Peer`数量最多
/// - 在可用`Peer`数量都相同的情况下，选用子`Piece`数量最少的
class BasePieceSelector implements PieceSelector {
  @override
  List<Piece> selectPiece(
      String remotePeerId, List<int> piecesIndexList, PieceProvider provider) {
    var maxList = <Piece>[];
    var a;
    var startIndex;
    for (var i = 0; i < piecesIndexList.length; i++) {
      if (provider[piecesIndexList[i]] != null) {
        a = provider[piecesIndexList[i]];
        startIndex = i;
        break;
      }
    }
    if (startIndex == null) return maxList;
    for (var i = startIndex; i < piecesIndexList.length; i++) {
      var p = provider[piecesIndexList[i]];
      if (p == null || !p.haveAvalidateSubPiece() || !p.haveAvalidatePeers()) {
        continue;
      }
      if (a.avalidatePeersCount < p.avalidatePeersCount) {
        maxList.clear();
        a = p;
        maxList.add(a);
      } else {
        if (a.avalidatePeersCount == p.avalidatePeersCount) {
          // 如果同样数量可用下载peer的piece所具有的sub piece少，优先处理
          if (p.avalidateSubPieceCount < a.avalidateSubPieceCount) {
            maxList.clear();
            a = p;
            maxList.add(a);
          } else {
            if (p.avalidateSubPieceCount == a.avalidateSubPieceCount) {
              maxList.add(p);
              a = p;
            }
          }
        }
      }
    }
    return maxList;
  }
}
