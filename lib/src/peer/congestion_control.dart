import 'dart:async';
import 'dart:math';

/// 100 ms
const CCONTROL_TARGET = 1000000;

const RECORD_TIME = 5000000;

/// 最大每次增加的request为3
const MAX_CWND_INCREASE_REQUESTS_PER_RTT = 3;

/// LEDBAT拥塞控制
///
/// 注意，所有时间单位都是微秒
mixin CongestionControl {
  // 初始是10秒
  double _rto = 10000000;

  double _srtt;

  double _rttvar;

  Timer _timeout;

  int _currentDownloaded = 0;

  final List<List<dynamic>> _downloadedHistory = <List<dynamic>>[];

  final Set<void Function(dynamic source, List<List<int>> requests)> _handles =
      <void Function(dynamic source, List<List<int>> requests)>{};

  /// Add `request timeout` event handler
  bool onRequestTimeout(
      void Function(dynamic source, List<List<int>> requests) handle) {
    return _handles.add(handle);
  }

  /// Remove `request timeout` event handler
  bool offRequestTimeout(
      void Function(dynamic source, List<List<int>> requests) handle) {
    return _handles.remove(handle);
  }

  /// 更新超时时间
  void updateRTO(int rtt) {
    if (rtt == 0) return;
    if (_srtt == null) {
      _srtt = rtt.toDouble();
      _rttvar = rtt / 2;
    } else {
      _rttvar = (1 - 0.25) * _rttvar + 0.25 * (_srtt - rtt).abs();
      _srtt = (1 - 0.125) * _srtt + 0.125 * rtt;
    }
    _rto = _srtt + max(100000, 4 * _rttvar);
    // 不到1秒，就设置为1秒
    _rto = max(_rto, 1000000);
  }

  void fireRequestTimeoutEvent(List<List<int>> requests) {
    if (requests == null || requests.isEmpty) return;
    _handles.forEach((f) {
      Timer.run(() => f(this, requests));
    });
  }

  List<List<int>> get currentRequestBuffer;

  void timeOutErrorHappen();

  void orderResendRequest(int index, int begin, int length, int rensed);

  void startRequestDataTimeout([int times = 0]) {
    _timeout?.cancel();
    var requests = currentRequestBuffer;
    if (requests == null || requests.isEmpty) return;
    _timeout = Timer(Duration(microseconds: _rto.toInt()), () {
      if (times + 1 >= 5) {
        timeOutErrorHappen();
        return;
      }

      var now = DateTime.now().microsecondsSinceEpoch;
      var first = requests.first;
      var timeoutR = <List<int>>[];
      while ((now - first[3]) > _rto) {
        var request = requests.removeAt(0);
        timeoutR.add(request);
        if (requests.isEmpty) break;
        first = requests.first;
      }
      timeoutR.forEach((request) {
        orderResendRequest(request[0], request[1], request[2], request[4]);
      });

      times++;
      _rto *= 2;
      fireRequestTimeoutEvent(timeoutR);
      startRequestDataTimeout(times);
    });
  }

  void ackRequest(List<int> request) {
    // 重发后收到的不管
    if (request == null || request[4] != 0) return;
    var now = DateTime.now().microsecondsSinceEpoch;
    var rtt = now - request[3];
    updateRTO(rtt);

    _downloadedHistory.add([request[2], DateTime.now().microsecondsSinceEpoch]);
    _currentDownloaded += request[2];
  }

  void _updateDownloaded() {
    if (_downloadedHistory.isEmpty) return;
    var now = DateTime.now().microsecondsSinceEpoch;
    var first = _downloadedHistory.first;
    while ((now - first[1]) > RECORD_TIME) {
      var d = _downloadedHistory.removeAt(0);
      _currentDownloaded -= d[0];
      if (_downloadedHistory.isEmpty) break;
      first = _downloadedHistory.first;
    }
  }

  /// 当前下载速度。
  ///
  /// 5秒钟内的平均速度
  double get currentSpeed {
    _updateDownloaded();
    if (_downloadedHistory.isEmpty) return 0.0;
    var now = DateTime.now().microsecondsSinceEpoch;
    var start = _downloadedHistory.first[1];
    var passed = now - start;
    if (passed == 0) return 0.0;
    return _currentDownloaded / (passed / 1000);
  }

  void clearCC() {
    _timeout?.cancel();
    _handles.clear();
    _downloadedHistory.clear();
  }
}
