import 'dart:io';

import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/src/lsd/lsd.dart';
import 'package:dtorrent_task/dtorrent_task.dart';

void main(List<String> args) async {
  print(await getTorrenTaskVersion());
  var torrentFile = 'example${Platform.pathSeparator}test4.torrent';
  var model = await Torrent.parse(torrentFile);
  var infoHash = model.infoHash;
  var lsd = LSD(infoHash, 'daa231dfa');
  lsd.port = 61111;
  lsd.start();
}
