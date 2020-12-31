import 'dart:async';

import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/torrent_task.dart';

var peers = <Uri>{};
void main() async {
  var model = await Torrent.parse('example/sample3.torrent');
  var task = TorrentTask.newTask(model, 'g:/bttest1/');
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
  model.nodes?.forEach((element) {
    task.addDHTNode(element);
  });

  print(map);

  timer = Timer.periodic(Duration(seconds: 2), (timer) async {
    print(
        'Progress : ${(task.progress * 100).toStringAsFixed(2)}% , Connect num : ${task.peersNumber}. Download speed : ${((task.downloadSpeed) * 1000 / 1024).toStringAsFixed(2)} KB/S , upload speed : ${((task.uploadSpeed) * 1000 / 1024).toStringAsFixed(2)} KB/S');
  });
  // timer1 = Timer.periodic(Duration(seconds: randomInt(21)), (timer) async {
  //   task.pause();
  //   await Future.delayed(Duration(seconds: randomInt(121)));
  //   task.resume();
  // });
}
