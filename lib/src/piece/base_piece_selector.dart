import 'package:dartorrent_common/dartorrent_common.dart';

import 'piece.dart';
import 'piece_provider.dart';
import 'piece_selector.dart';

///
/// Basic piece selector.
///
/// The basic strategy is:
///
/// - Choose the Piece with the highest number of available Peers.
/// - If multiple Pieces have the same number of available Peers, choose the one with the fewest Sub Pieces remaining.
class BasePieceSelector implements PieceSelector {
  @override
  Piece? selectPiece(
      String remotePeerId, List<int> piecesIndexList, PieceProvider provider,
      [bool random = false]) {
    // random = true;
    var maxList = <Piece>[];
    Piece? a;
    int? startIndex;
    for (var i = 0; i < piecesIndexList.length; i++) {
      var p = provider[piecesIndexList[i]];
      if (p != null &&
          p.haveAvalidateSubPiece() &&
          p.containsAvalidatePeer(remotePeerId)) {
        a = p;
        startIndex = i;
        break;
      }
    }
    if (startIndex == null) return null;
    maxList.add(a!);
    for (var i = startIndex; i < piecesIndexList.length; i++) {
      var p = provider[piecesIndexList[i]];
      if (p == null ||
          !p.haveAvalidateSubPiece() ||
          !p.containsAvalidatePeer(remotePeerId)) {
        continue;
      }
      // Select rare pieces
      if (a!.avalidatePeersCount > p.avalidatePeersCount) {
        if (!random) return p;
        maxList.clear();
        a = p;
        maxList.add(a);
      } else {
        if (a.avalidatePeersCount == p.avalidatePeersCount) {
          // If multiple Pieces have the same number of available downloading Peers, prioritize the one with the fewest remaining Sub Pieces.
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
