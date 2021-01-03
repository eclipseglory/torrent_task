import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/torrent_task.dart';

var peers = <Uri>{};
void main() async {
  // https://newtrackon.com/api/stable
  var alist = <Uri>[];
  try {
    var url = Uri.parse('http://newtrackon.com/api/stable');
    var client = HttpClient();
    var request = await client.getUrl(url);
    var response = await request.close();
    print(response.statusCode);
    var stream = await utf8.decoder.bind(response);
    await stream.forEach((element) {
      try {
        var r = Uri.parse(element);
        alist.add(r);
      } catch (e) {
        //
      }
    });
  } catch (e) {
    print(e);
  }
  var torrentFile = 'example/test11.torrent';
  var savePath = 'g:/bttest/';
  var model = await Torrent.parse(torrentFile);
  var task = TorrentTask.newTask(model, savePath);
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

  alist.forEach((element) {
    task.startAnnounceUrl(element, model.infoHashBuffer);
  });

  model.nodes?.forEach((element) {
    task.addDHTNode(element);
  });

  print(map);

  timer = Timer.periodic(Duration(seconds: 2), (timer) async {
    print(
        'Progress : ${(task.progress * 100).toStringAsFixed(2)}% , Peers: ${task.connectedPeersNumber}(${task.seederNumber}/${task.allPeersNumber}). Download speed : ${((task.downloadSpeed) * 1000 / 1024).toStringAsFixed(2)} KB/S , upload speed : ${((task.uploadSpeed) * 1000 / 1024).toStringAsFixed(2)} KB/S');
  });
  // timer1 = Timer.periodic(Duration(seconds: randomInt(21)), (timer) async {
  //   task.pause();
  //   await Future.delayed(Duration(seconds: randomInt(121)));
  //   task.resume();
  // });
}
