import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_model/torrent_model.dart';
import 'package:torrent_task/torrent_task.dart';

void main() async {
  try {
    var torrentFile = 'example${Platform.pathSeparator}test4.torrent';
    var savePath = 'tmp${Platform.pathSeparator}test';
    var model = await Torrent.parse(torrentFile);
    // model.announces.clear();
    var task = TorrentTask.newTask(model, savePath);
    Timer? timer;
    Timer? timer1;
    var startTime = DateTime.now().millisecondsSinceEpoch;
    task.onTaskComplete(() {
      print(
          'Complete! spend time : ${((DateTime.now().millisecondsSinceEpoch - startTime) / 60000).toStringAsFixed(2)} minutes');
      timer?.cancel();
      timer1?.cancel();
      task.stop();
    });
    task.onStop(() async {
      print('Task Stopped');
    });
    var map = await task.start();

    // ignore: unawaited_futures
    findPublicTrackers().listen((alist) {
      alist.forEach((element) {
        task.startAnnounceUrl(element, model.infoHashBuffer);
      });
    });
    log('Adding dht nodes');
    model.nodes.forEach((element) {
      log('dht node $element');
      task.addDHTNode(element);
    });
    print(map);

    timer = Timer.periodic(Duration(seconds: 2), (timer) async {
      var progress = '${(task.progress * 100).toStringAsFixed(2)}%';
      var ads =
          '${((task.averageDownloadSpeed) * 1000 / 1024).toStringAsFixed(2)}';
      var aps =
          '${((task.averageUploadSpeed) * 1000 / 1024).toStringAsFixed(2)}';
      var ds =
          '${((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2)}';
      var ps = '${((task.uploadSpeed) * 1000 / 1024).toStringAsFixed(2)}';

      var utpd =
          '${((task.utpDownloadSpeed) * 1000 / 1024).toStringAsFixed(2)}';
      var utpu = '${((task.utpUploadSpeed) * 1000 / 1024).toStringAsFixed(2)}';
      var utpc = task.utpPeerCount;

      var active = task.connectedPeersNumber;
      var seeders = task.seederNumber;
      var all = task.allPeersNumber;
      print(
          'Progress : $progress , Peers:($active/$seeders/$all)($utpc) . Download speed : ($utpd)($ads/$ds)kb/s , upload speed : ($utpu)($aps/$ps)kb/s');
    });
  } catch (e) {
    print(e);
  }
}
