import 'dart:math';

/// 5 seconds
const RECORD_TIME = 5000000;

/// 上传下载速度计算器
mixin SpeedCalculator {
  final List<List<int>> _downloadedHistory = <List<int>>[];

  /// 当前5秒内的平均下载速度
  double get currentDownloadSpeed {
    if (_downloadedHistory.isEmpty) return 0.0;
    var now = DateTime.now().microsecondsSinceEpoch;
    var d = 0;
    int? s;
    for (var i = 0; i < _downloadedHistory.length;) {
      var dd = _downloadedHistory[i];
      if ((now - dd[1]) > RECORD_TIME) {
        _downloadedHistory.removeAt(i);
      } else {
        d += dd[0];
        s ??= dd[1];
        s = min(dd[1], s);
        i++;
      }
    }
    if (d == 0) return 0.0;
    var passed = now - s!;
    if (passed == 0) return 0.0;
    return (d / 1024) / (passed / 1000000);
  }

  /// 从Peer连接开始到当前的平均下载速度
  double get averageDownloadSpeed {
    var passed = livingTime;
    if (passed == null || passed == 0) return 0.0;
    return (_downloaded / 1024) / (passed / 1000000);
  }

  /// 从Peer连接开始到当前的平均上传速度
  double get averageUploadSpeed {
    var passed = livingTime;
    if (passed == null || passed == 0) return 0.0;
    return (_uploaded / 1024) / (passed / 1000000);
  }

  /// 从连接开始，直到peer销毁之前所持续时间
  int? get livingTime {
    if (_startTime == null) return null;
    var e = _endTime;
    e ??= DateTime.now().microsecondsSinceEpoch;
    return e - _startTime!;
  }

  int? _startTime;

  int? _endTime;

  int _downloaded = 0;

  /// 从远程下载的总数据量，单位bytes
  int get downloaded => _downloaded;

  int _uploaded = 0;

  /// 上传到远程的总数据量，单位bytes
  int get uploaded => _uploaded;

  /// 更新下载
  void updateDownload(List<List<int>> requests) {
    if (requests.isEmpty) return;
    var downloaded = 0;
    for (var request in requests) {
      if (request[4] != 0) continue; // 重新计时的不算
      downloaded += request[2];
    }
    _downloadedHistory.add([downloaded, DateTime.now().microsecondsSinceEpoch]);
    _downloaded += downloaded;
  }

  void updateUpload(int uploaded) {
    _uploaded += uploaded;
  }

  /// 速度计算开始计时
  void startSpeedCalculator() {
    _startTime = DateTime.now().microsecondsSinceEpoch;
  }

  /// 速度计算停止计时
  void stopSpeedCalculator() {
    _endTime = DateTime.now().microsecondsSinceEpoch;
    _downloadedHistory.clear();
  }
}
