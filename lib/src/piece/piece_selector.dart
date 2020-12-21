import 'piece.dart';
import 'piece_provider.dart';

/// Piece选择器。
///
/// 当客户端开始下载前，通过这个类选择出恰当的Piece来下载
abstract class PieceSelector {
  /// 选择恰当的Piece应该Peer下载.
  ///
  /// [remotePeerId]是即将下载的`Peer`的标识，这个标识并**不一定**是协议中的`peer_id`，
  /// 而是`Piece`类中区分`Peer`的标识。
  /// 该方法通过[provider]以及[piecesIndexList]获取对应的`Piece`对象，并在[piecesIndexList]
  /// 集合中进行筛选。
  ///
  Piece selectPiece(
      String remotePeerId, List<int> piecesIndexList, PieceProvider provider,
      [bool first = false]);
}
