## About
Dart library for implementing BitTorrent client. 

Whole Dart Torrent client contains serival parts :
- [Bencode](https://pub.dev/packages/bencode_dart) 
- [Tracker](https://pub.dev/packages/torrent_tracker)
- [DHT](https://pub.dev/packages/dht_dart)
- [Torrent model](https://pub.dev/packages/torrent_model)
- [Common library](https://pub.dev/packages/dartorrent_common)
- [UTP](https://pub.dev/packages/utp)

This package implements regular BitTorrent Protocol and manage above packages to work together for downloading.

## BEP Support:
- [BEP 0003 The BitTorrent Protocol Specification]
- [BEP 0005 DHT Protocal]
- [BEP 0006 Fast Extension]
- [BEP 0010	Extension Protocol]
- [BEP 0011	Peer Exchange (PEX)]
- [BEP 0014 Local Service Discovery]
- [BEP 0015 UDP Tracker Protocal]
- [BEP 0029 uTorrent transport protocol]
- [BEP 0055 Holepunch extension]

Developing:
- [BEP 0009	Extension for Peers to Send Metadata Files]

Other support will come soon.

## How to use

This package need to dependency [`torrent_model`](https://pub.dev/packages/torrent_model):
```
dependencies:
  torrent_model : ^1.0.3
  torrent_task : ^0.1.2
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
