import 'dart:async';

import 'package:torrent_client/src/torrent_task.dart';
import 'package:torrent_model/torrent_model.dart';

var peers = <Uri>{};
void main() async {
  var model = await Torrent.parse('example/test4.torrent');
  var task = TorrentTask.newTask(model, 'g:/bttest2/');
  print(await task.start());

  Timer.periodic(Duration(seconds: 10), (timer) {
    print(
        'download speed : ${task.downloadSpeed * 1000 / 1024} , upload speed : ${task.uploadSpeed * 1000 / 1024}');
  });
}
