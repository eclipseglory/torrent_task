import 'piece.dart';
import 'piece_provider.dart';

/// Piece selector.
///
/// When the client starts downloading, this class selects appropriate Pieces to download.
abstract class PieceSelector {
  /// Selects the appropriate Piece for the Peer to download.
  ///
  /// [remotePeerId] is the identifier of the Peer that is about to download. This identifier may not necessarily be the peer_id in the protocol, but rather a unique identifier used by the Piece class to distinguish Peers.
  /// This method retrieves the corresponding Piece object using [provider] and [piecesIndexList], and filters it within the [piecesIndexList] collection.
  ///
  Piece? selectPiece(
      String remotePeerId, List<int> piecesIndexList, PieceProvider provider,
      [bool first = false]);
}
