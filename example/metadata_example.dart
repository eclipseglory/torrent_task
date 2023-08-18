import 'dart:async';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task/src/metadata/metadata_downloader.dart';
import 'package:dtorrent_task/dtorrent_task.dart';
import 'package:dtorrent_tracker/dtorrent_tracker.dart';

void main(List<String> args) async {
  var infohashString = '217bddb5816f2abc56ce1d9fe430711542b109cc';
  var metadata = MetadataDownloader(infohashString);
  // Metadata download contains a DHT , it will search the peer via DHT,
  // but it's too slow , sometimes DHT can not find any peers
  metadata.startDownload();
  // so for this example , I use the public trackers to help MetaData download to search Peer nodes:
  var tracker = TorrentAnnounceTracker(metadata);

  // When metadata contents download complete , it will send this event and stop itself:
  metadata.onDownloadComplete((data) async {
    tracker.stop(true);
    var msg = decode(Uint8List.fromList(data));
    Map<String, dynamic> torrent = {};
    torrent['info'] = msg;
    var torrentModel = parseTorrentFileContent(torrent);
    if (torrentModel != null) {
      print('complete , info : ${torrentModel.name}');
      var startTime = DateTime.now().millisecondsSinceEpoch;
      var task = TorrentTask.newTask(torrentModel, 'tmp');
      Timer? timer;
      task.onTaskComplete(() {
        print(
            'Complete! spend time : ${((DateTime.now().millisecondsSinceEpoch - startTime) / 60000).toStringAsFixed(2)} minutes');
        timer?.cancel();
        task.stop();
      });
      task.onStop(() async {
        print('Task Stopped');
      });
      timer = Timer.periodic(Duration(seconds: 2), (timer) async {
        var progress = '${(task.progress * 100).toStringAsFixed(2)}%';
        var ads =
            ((task.averageDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
        var aps = ((task.averageUploadSpeed) * 1000 / 1024).toStringAsFixed(2);
        var ds = ((task.currentDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
        var ps = ((task.uploadSpeed) * 1000 / 1024).toStringAsFixed(2);

        var utpd = ((task.utpDownloadSpeed) * 1000 / 1024).toStringAsFixed(2);
        var utpu = ((task.utpUploadSpeed) * 1000 / 1024).toStringAsFixed(2);
        var utpc = task.utpPeerCount;

        var active = task.connectedPeersNumber;
        var seeders = task.seederNumber;
        var all = task.allPeersNumber;
        print(
            'Progress : $progress , Peers:($active/$seeders/$all)($utpc) . Download speed : ($utpd)($ads/$ds)kb/s , upload speed : ($utpu)($aps/$ps)kb/s');
      });
      await task.start();
    }
  });

  var u8List = Uint8List.fromList(metadata.infoHashBuffer);

  tracker.onPeerEvent((source, event) {
    if (event == null) return;
    var peers = event.peers;
    for (var element in peers) {
      metadata.addNewPeerAddress(element, PeerSource.tracker);
    }
  });
  // ignore: unawaited_futures
  findPublicTrackers().listen((alist) {
    for (var element in alist) {
      tracker.runTracker(element, u8List);
    }
  });
}
