import 'dart:async';

import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/torrent_task_all.dart';

var peers = <Uri>{};
void main() async {
  var model = await Torrent.parse('example/test8.torrent');
  var task = TorrentTask.newTask(model, 'g:/bttest/');
  Timer timer;
  Timer timer1;
  task.onTaskComplete(() {
    print('Complete!');
    timer?.cancel();
    timer1?.cancel();
    task.stop();
  });
  task.onStop(() async {
    print('Task Stopped');
  });

  var map = await task.start();
  print(map);

  timer = Timer.periodic(Duration(seconds: 10), (timer) async {
    print(
        'download speed : ${(await task.downloadSpeed) * 1000 / 1024} , upload speed : ${task.uploadSpeed * 1000 / 1024}');
  });
  timer1 = Timer.periodic(Duration(seconds: randomInt(21)), (timer) async {
    task.pause();
    await Future.delayed(Duration(seconds: randomInt(121)));
    task.resume();
  });
}
