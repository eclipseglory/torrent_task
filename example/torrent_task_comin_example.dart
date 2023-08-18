import 'dart:async';
import 'dart:io';

import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/dtorrent_task.dart';

/// This example is for connect local
Future<void> main() async {
  var model =
      await Torrent.parse('example${Platform.pathSeparator}test4.torrent');
  // No peers retrieval
  model.announces.clear();
  var task = TorrentTask.newTask(model, 'tmp${Platform.pathSeparator}test');
  Timer? timer;
  Timer? timer1;
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
          'Downloaed: ${task.downloaded ?? 0 / (1024 * 1024)} mb , ${((task.downloaded ?? 0 / model.length) * 100).toStringAsFixed(2)}%');
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
  // download from yourself
  task.addPeer(CompactAddress(InternetAddress.tryParse('192.168.0.24')!, 57331),
      PeerSource.manual);
}
