import 'dart:io';

import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/src/lsd/lsd.dart';
import 'package:torrent_task/torrent_task.dart';

void main(List<String> args) async {
  print(await getTorrenTaskVersion());
  var torrentFile = 'example${Platform.pathSeparator}test4.torrent';
  var model = await Torrent.parse(torrentFile);
  var infoHash = model.infoHash;
  var lsd = LSD(infoHash, 'daa231dfa');
  lsd.port = 61111;
  lsd.start();
}
