## About
Dart library for implementing BitTorrent client.

## Support:
- [BEP 0003 The BitTorrent Protocol Specification](http://www.bittorrent.org/beps/bep_0003.html)
- [BEP 0005 DHT Protocal](http://www.bittorrent.org/beps/bep_0005.html)
- [BEP 0006 Fast Extension](http://www.bittorrent.org/beps/bep_0006.html)
- [BEP 0010	Extension Protocol](http://www.bittorrent.org/beps/bep_0010.html)
- [BEP 0011	Peer Exchange (PEX)](http://www.bittorrent.org/beps/bep_0011.html)
- [BEP 0015 UDP Tracker Protocal](http://www.bittorrent.org/beps/bep_0015.html)

Developing:
- [BEP 0029 uTorrent transport protocol](https://www.bittorrent.org/beps/bep_0029.html)
- [BEP 0014 Local Service Discovery](https://www.bittorrent.org/beps/bep_0014.html)
- [BEP 0055 Holepunch extension](https://www.bittorrent.org/beps/bep_0055.html)
- [BEP 0009	Extension for Peers to Send Metadata Files](http://www.bittorrent.org/beps/bep_0009.html)

Other support will come soon.

## How to use

Add package dependencies: `torrent_model` and `torrent_task`:
```
dependencies:
  torrent_model : ^1.0.1
  torrent_task : ^0.0.1
```

First , create a `Torrent` model via .torrent file:

```dart
  var model = await Torrent.parse('some.torrent');
```

Second, create a `Torrent Task` and start it:
```dart
  var task = TorrentTask.newTask(model,'savepath');
  task.start();
```

User can add some listener to monitor `TorrentTask` running:
```dart
  task.onTaskComplete(() => .....);
  task.onFileComplete((String filePath) => .....);
```

and there is some method to control the `TorrentTask`:

```dart
   // Stop task:
   task.stop();
   // Pause task:
   task.pause();
   // Resume task:
   task.resume();
```
