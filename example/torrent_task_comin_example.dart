import 'package:torrent_client/src/torrent_task.dart';
import 'package:torrent_model/torrent_model.dart';

Future<void> main() async {
  var model = await Torrent.parse('example/test8.torrent');
  // 不去获取peers
  model.announces.clear();
  var task = TorrentTask.newTask(model, 'g:/bttest5/');
  // task.addPeer(Uri(host:'127.0.0.1'));
  await task.start();
  // 自己下载自己
  task.addPeer(
      Uri(host: '127.0.0.1', port: 64739), Uri(host: '127.0.0.1', port: 64739));
}
