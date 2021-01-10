import 'dart:async';
import 'dart:typed_data';

import 'package:bencode_dart/bencode_dart.dart';

mixin ExtendedProcessor {
  final Map<int, String> _extendedEventMap = {};
  int _id = 1;
  Map _rawMap;
  final Map<String, int> _localExtended = <String, int>{};

  Map<String, int> get localExtened => _localExtended;

  final Set<void Function(dynamic source, String eventName, dynamic data)>
      _eventHandler = {};

  bool onExtendedEvent(
      void Function(dynamic source, String eventName, dynamic data) handler) {
    return _eventHandler.add(handler);
  }

  bool offExtendedEvent(
      void Function(dynamic source, String eventName, dynamic data) handler) {
    return _eventHandler.remove(handler);
  }

  void registerExtened(String name) {
    _localExtended[name] = _id;
    _id++;
  }

  int getExtendedEventId(String name) {
    if (_rawMap != null) {
      return _rawMap[name];
    }
    return null;
  }

  void processExtendMessage(int id, List<int> message,
      [int start = 0, int end]) {
    end ??= message.length;
    var m = message;
    if (start != 0 || end != message.length) {
      m = message.sublist(start, end);
    }
    var data = decode(Uint8List.fromList(m));
    if (id == 0) {
      processExtendHandshake(data);
    } else {
      var name = _extendedEventMap[id];
      if (name != null) {
        _fireExtendedEvent(name, data);
      }
    }
  }

  void _fireExtendedEvent(String name, dynamic data) {
    _eventHandler.forEach((element) {
      Timer.run(() => element(this, name, data));
    });
  }

  void processExtendHandshake(dynamic data) {
    var m = data['m'] as Map;
    _rawMap = m;
    if (m != null) {
      m.forEach((key, value) {
        if (value == 0) return;
        _extendedEventMap[value] = key;
      });
    }
    _fireExtendedEvent('handshake', data);
  }

  void clearExtendedProcessors() {
    _extendedEventMap.clear();
    _eventHandler.clear();
    _rawMap?.clear();
    _localExtended.clear();
    _id = 1;
  }
}
