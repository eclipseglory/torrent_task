import 'dart:typed_data';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_task/src/metadata/metadata_downloader.dart';
import 'package:torrent_tracker/torrent_tracker.dart';

void main(List<String> args) async {
  var infohashString = '217bddb5816f2abc56ce1d9fe430711542b109cc';
  var metadata = MetadataDownloader(infohashString);
  // Metadata download contains a DHT , it will search the peer via DHT,
  // but it's too slow , sometimes DHT can not find any peers
  metadata.startDownload();
  // so for this example , I use the public trackers to help MetaData download to search Peer nodes:
  var tracker = TorrentAnnounceTracker(metadata);

  // When metadata contents download complete , it will send this event and stop itself:
  metadata.onDownloadComplete((data) {
    var msg = decode(Uint8List.fromList(data));
    print('complete , info : $msg');
    tracker?.stop(true);
  });

  var u8List = Uint8List.fromList(metadata.infoHashBuffer);

  tracker.onPeerEvent((source, event) {
    if (event == null) return;
    var peers = event.peers;
    peers.forEach((element) {
      metadata.addNewPeerAddress(element);
    });
  });
  // ignore: unawaited_futures
  findPublicTrackers().listen((alist) {
    alist.forEach((element) {
      tracker.runTracker(element, u8List);
    });
  });
}
