import 'dart:async';
import 'dart:io';

import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/torrent_task.dart';

/// This example is for connect local
Future<void> main() async {
  var model = await Torrent.parse('example/test8.torrent');
  // 不获取peers
  model.announces.clear();
  var task = TorrentTask.newTask(model, 'g:/bttest5/');
  Timer timer;
  Timer timer1;
  task.onFileComplete((filepath) {
    print('$filepath downloaded complete');
  });

  task.onTaskComplete(() {
    print('Complete!');
    timer?.cancel();
    timer1?.cancel();
    task.stop();
  });
  task.onStop(() async {
    print('Task Stopped');
  });
  await task.start();

  timer = Timer.periodic(Duration(seconds: 2), (timer) {
    try {
      print(
          'Downloaed: ${task.downloaded / (1024 * 1024)} mb , ${((task.downloaded / model.length) * 100).toStringAsFixed(2)}%');
    } finally {}
  });

  // timer = Timer.periodic(Duration(seconds: 10), (timer) async {
  //   print(
  //       'download speed : ${(await task.downloadSpeed) * 1000 / 1024} , upload speed : ${task.uploadSpeed * 1000 / 1024}');
  // });
  // timer1 = Timer.periodic(Duration(seconds: randomInt(21)), (timer) async {
  //   task.pause();
  //   await Future.delayed(Duration(seconds: randomInt(121)));
  //   task.resume();
  // });

  // Timer(Duration(seconds: 20), () async {
  //   task.pause();
  //   await Future.delayed(Duration(seconds: 120));
  //   task.resume();
  // });
  // 自己下载自己
  task.addPeer(CompactAddress(InternetAddress.tryParse('192.168.0.24'), 58617));
}
