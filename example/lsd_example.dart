import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/src/lsd/lsd.dart';

void main(List<String> args) async {
  var torrentFile = 'example/12.torrent';
  var savePath = 'g:/bttest';
  var model = await Torrent.parse(torrentFile);
  var infoHash = model.infoHash;
  var lsd = LSD(infoHash, 'daa231dfa');
  lsd.port = 61111;
  lsd.start();
}
