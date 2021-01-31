import 'dart:async';
import 'dart:io';

import 'package:bencode_dart/bencode_dart.dart';
import 'package:dartorrent_common/dartorrent_common.dart';
import 'package:torrent_task/src/peer/peer.dart';

const pex_flag_prefers_encryption = 0x01;

const pex_flag_upload_only = 0x02;

const pex_flag_supports_uTP = 0x04;

const pex_flag_supports_holepunch = 0x08;

const pex_flag_reachable = 0x10;

mixin PEX {
  Timer _timer;

  final Set<CompactAddress> _lastUTPEX = <CompactAddress>{};

  void startPEX() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 60), (timer) {
      _sendUt_pex_peers();
    });
  }

  Iterable<Peer> get activePeers;

  void _sendUt_pex_peers() {
    var dropped = <CompactAddress>[];
    var added = <CompactAddress>[];
    activePeers.forEach((p) {
      if (!_lastUTPEX.remove(p.address)) {
        added.add(p.address);
      }
    });
    _lastUTPEX.forEach((element) {
      dropped.add(element);
    });
    _lastUTPEX.clear();

    var data = {};
    data['added'] = [];
    added.forEach((element) {
      _lastUTPEX.add(element);
      data['added'].addAll(element.toBytes());
    });
    data['dropped'] = [];
    dropped.forEach((element) {
      data['dropped'].addAll(element.toBytes());
    });
    if (data['added'].isEmpty && data['dropped'].isEmpty) return;
    var message = encode(data);
    activePeers.forEach((peer) {
      peer.sendExtendMessage('ut_pex', message);
    });
  }

  dynamic parsePEXDatas(dynamic source, List<int> message) {
    var datas = decode(message);
    _parseAdded(source, datas);
    _parseAdded(source, datas, 'added6', InternetAddressType.IPv6);
  }

  dynamic _parseAdded(dynamic source, Map datas,
      [String keyStr = 'added',
      InternetAddressType type = InternetAddressType.IPv4]) {
    var added = datas[keyStr];
    if (added != null && added is List && added.isNotEmpty) {
      if (added is! List<int>) {
        added = _convert(added);
      }
      List ips;
      try {
        if (type == InternetAddressType.IPv4) {
          ips = CompactAddress.parseIPv4Addresses(added);
        }
        if (type == InternetAddressType.IPv6) {
          ips = CompactAddress.parseIPv6Addresses(added);
        }
      } catch (e) {
        // do nothing
      }
      var flag = datas['$keyStr.f'];
      if (flag != null && flag is List && flag.isNotEmpty) {
        if (flag is! List<int>) {
          flag = _convert(flag);
        }
        if (ips != null && ips.isNotEmpty) {
          for (var i = 0; i < ips.length; i++) {
            var f = flag[i];
            var opts = {};
            if (f & pex_flag_prefers_encryption ==
                pex_flag_prefers_encryption) {
              opts['e'] = true;
            }
            if (f & pex_flag_upload_only == pex_flag_upload_only) {
              opts['uploadonly'] = true;
            }
            if (f & pex_flag_supports_uTP == pex_flag_supports_uTP) {
              opts['utp'] = true;
            }
            if (f & pex_flag_supports_holepunch ==
                pex_flag_supports_holepunch) {
              opts['holepunch'] = true;
            }
            if (f & pex_flag_reachable == pex_flag_reachable) {
              opts['reachable'] = true;
            }
            Timer.run(() => addPEXPeer(source, ips[i], opts));
          }
        }
      }
    }
  }

  void addPEXPeer(dynamic source, CompactAddress address, Map options);

  List<int> _convert(List added) {
    var intList = <int>[];
    for (var i = 0; i < added.length; i++) {
      var n = added[i];
      if (n is int && n >= 0 && n < 256) {
        intList.add(n);
      } else {
        return null;
      }
    }
    return intList;
  }

  void clearPEX() {
    _timer?.cancel();
    _lastUTPEX.clear();
  }
}
