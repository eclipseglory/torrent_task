import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';
import 'package:bencode_dart/bencode_dart.dart';
import 'package:torrent_task/src/peer/extended_proccessor.dart';
import 'package:dartorrent_common/dartorrent_common.dart';

import '../utils.dart';
import 'bitfield.dart';
import 'peer_event_dispatcher.dart';

const KEEP_ALIVE_MESSAGE = [0, 0, 0, 0];
const RESERVED = [0, 0, 0, 0, 0, 0, 0, 0];
const HAND_SHAKE_HEAD = [
  19,
  66,
  105,
  116,
  84,
  111,
  114,
  114,
  101,
  110,
  116,
  32,
  112,
  114,
  111,
  116,
  111,
  99,
  111,
  108
];

const ID_CHOKE = 0;
const ID_UNCHOKE = 1;
const ID_INTERESTED = 2;
const ID_NOT_INTERESTED = 3;
const ID_HAVE = 4;
const ID_BITFIELD = 5;
const ID_REQUEST = 6;
const ID_PIECE = 7;
const ID_CANCEL = 8;
const ID_PORT = 9;
const ID_EXTENDED = 20;

const OP_HAVE_ALL = 0x0e;
const OP_HAVE_NONE = 0x0f;
const OP_SUGGEST_PIECE = 0x0d;
const OP_REJECT_REQUEST = 0x10;
const OP_ALLOW_FAST = 0x11;

enum PeerType { TCP, uTP }

/// 30 Seconds
const DEFAULT_CONNECT_TIMEOUT = 30;

/// 带有 [index],[begin],[length]参数的方法
typedef PieceConfigHandle = void Function(
    Peer peer, int index, int begin, int length);
typedef NoneParamHandle = void Function(Peer peer);

typedef BoolHandle = void Function(Peer peer, bool value);

typedef SingleIntHandle = void Function(Peer peer, int value);

abstract class Peer with PeerEventDispatcher, ExtendedProcessor {
  /// Countdown time , when peer don't receive or send any message from/to remote ,
  /// this class will invoke close.
  /// 单位:秒
  int countdownTime = 150;

  String get id {
    return address?.toContactEncodingString();
  }

  /// 下载项目的piece总数
  final int _piecesNum;

  /// 远程的Bitfield
  Bitfield _remoteBitfield;

  /// 该peer是否已经disposed
  bool _disposed = false;

  /// 倒计时关闭Timer
  Timer _countdownTimer;

  /// 对方是否choke了我，初始默认true
  bool _chokeMe = true;

  /// 我是否choke了对方，默认true
  bool chokeRemote = true;

  /// 对方是否对我的资源感兴趣，默认false
  bool _interestedMe = false;

  /// 我是否对对方的资源感兴趣，默认false
  bool interestedRemote = false;

  /// Debug 使用
  // ignore: unused_field
  dynamic _disposeReason;

  /// 远程Peer的地址和端口
  final CompactAddress address;

  /// Torrent infohash buffer
  final List<int> _infoHashBuffer;

  /// Local Peer Id
  final String _localPeerId; // 本机的peer id。发送消息会用到

  String _remotePeerId;

  /// has this peer send handshake message already?
  bool _handShaked = false;

  /// has this peer send local bitfield to remote?
  bool _bitfieldSended = false;

  /// 远程数据接受，监听subcription
  StreamSubscription _streamChunk;

  /// 从通道中获取数据的buffer
  List<int> _cacheBuffer = [];

  // /// 所有事件回调方法Map
  // final _handleFunctions = <String, Set<Function>>{};

  /// 本地发送请求buffer。格式位：[index,begin,length]
  final _requestBuffer = <List<int>>[];

  /// 远程发送请求buffer。格式位：[index,begin,length]
  final _remoteRequestBuffer = <List<int>>[];

  /// Every request timeout timer. The key format is `<index>-<begin>`
  final _requestTimeoutMap = <String, Timer>{};

  /// Max request count in one piple ,5
  static const MAX_REQUEST_COUNT = 5;

  /// single request timeout time, 30 seconds
  static const REQUEST_TIME_OUT = 30;

  int _downloaded = 0;

  int _uploaded = 0;

  int _endTime;

  int _startTime;

  int get livingTime {
    if (_startTime == null) {
      return 0;
    }
    var passed = DateTime.now().millisecondsSinceEpoch - _startTime;
    if (_endTime != null) {
      passed = _endTime - _startTime;
    }
    return passed;
  }

  double get downloadSpeed {
    var lt = livingTime;
    if (lt == 0) return 0.0;
    return _downloaded / lt;
  }

  double get uploadSpeed {
    var lt = livingTime;
    if (lt == 0) return 0.0;
    return _uploaded / lt;
  }

  bool remoteEnableFastPeer = false;

  bool localEnableFastPeer = true;

  bool remoteEnableExtended = false;

  bool localEnableExtended = true;

  /// 本地的Allow Fast pieces
  final Set<int> _allowFastPieces = <int>{};

  /// 远程发送的Allow Fast pieces
  final Set<int> _remoteAllowFastPieces = <int>{};

  /// 远程发送的Suggest pieces
  final Set<int> _remoteSuggestPieces = <int>{};

  final PeerType type;

  ///
  /// [_id] 是用于区分不同Peer的Id，和[_localPeerId]不同，[_localPeerId]是bt协议中的Peer_id。
  /// [address]是远程peer的地址和端口，子类在实现的时候可以利用该值进行远程连接。[_infoHashBuffer]
  /// 是torrent文件中的infohash值，[_piecesNum]是下载项目的总piece数目，用于构建远程`Bitfield`数据
  /// 使用。可选项[localEnableFastPeer]默认位`true`，表示本地是否开启[Fast Extension(BEP 0006)](http://www.bittorrent.org/beps/bep_0006.html),
  /// [localEnableExtended]表示本地是否可以使用[Extension Protocol](http://www.bittorrent.org/beps/bep_0010.html)
  Peer(this._localPeerId, this.address, this._infoHashBuffer, this._piecesNum,
      {this.type = PeerType.TCP,
      this.localEnableFastPeer = true,
      this.localEnableExtended = true}) {
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
  }

  factory Peer.newTCPPeer(String localPeerId, CompactAddress address,
      List<int> infoHashBuffer, int piecesNum, Socket socket,
      {bool enableExtend = true, bool enableFast = true}) {
    return _TCPPeer(localPeerId, address, infoHashBuffer, piecesNum, socket,
        enableExtend: enableExtend, enableFast: enableFast);
  }

  factory Peer.newUTPPeer() {
    // TODO IMPLEMENT THIS!
    throw '还没实现';
  }

  /// 远程的Bitfield
  Bitfield get remoteBitfield => _remoteBitfield;

  /// 是否已经发送local bitfield给对方
  bool get bitfieldSended => _bitfieldSended;

  /// 从远程下载的总数据量，单位bytes
  int get downloaded => _downloaded;

  /// 上传到远程的总数据量，单位bytes
  int get uploaded => _uploaded;

  bool get isLeecher => !isSeeder;

  /// 如果具备完整的torrent文件，那它就是一个seeder
  bool get isSeeder {
    if (_remoteBitfield == null) return false;
    if (_remoteBitfield.haveAll()) return true;
    return false;
  }

  String get remotePeerId => _remotePeerId;

  String get localPeerId => _localPeerId;

  /// 远程发送的Request请求
  List<List<int>> get remoteRequestbuffer => _remoteRequestBuffer;

  /// 本地发送给远程的Request请求
  List<List<int>> get requestBuffer => _requestBuffer;

  Set<int> get remoteSuggestPieces => _remoteSuggestPieces;

  bool get isDisposed => _disposed;

  bool get chokeMe => _chokeMe;

  set chokeMe(bool c) {
    if (c != _chokeMe) {
      _chokeMe = c;
      fireChokeChangeEvent(_chokeMe);
    }
  }

  bool remoteHave(int index) {
    return _remoteBitfield.getBit(index);
  }

  bool get interestedMe => _interestedMe;

  set interestedMe(bool i) {
    if (i != _interestedMe) {
      _interestedMe = i;
      fireInterestedChangeEvent(_interestedMe);
    }
  }

  /// 远程所有的已完成Piece
  List<int> get remoteCompletePieces {
    if (_remoteBitfield == null) return [];
    return _remoteBitfield.completedPieces;
  }

  /// Connect remote peer
  Future connect([int timeout = DEFAULT_CONNECT_TIMEOUT]) async {
    try {
      _init();
      var _stream = await connectRemote(timeout);
      _startTime = DateTime.now().millisecondsSinceEpoch;
      _endTime = null;
      _streamChunk = _stream.listen(_processReceiveData, onDone: () {
        _log('Connection is closed $address');
        dispose(BadException('远程关闭了连接'));
      }, onError: (e) {
        _log('Error happen: $address', e);
        dispose(e);
      });
      fireConnectEvent();
    } catch (e) {
      return dispose(BadException(e));
    }
  }

  /// 初始化一些基本数据
  void _init() {
    // 初始化数据
    _disposeReason = null;
    _disposed = false;
    _handShaked = false;
    // 清空通道数据缓存：
    _cacheBuffer.clear();
    // 清空请求缓存
    _requestBuffer.clear();
    _requestTimeoutMap.clear();
    _remoteRequestBuffer.clear();
    // 重置fast pieces
    _remoteAllowFastPieces.clear();
    _allowFastPieces.clear();
    // 重置suggest pieces
    _remoteSuggestPieces.clear();
    // 重置远程fast extension标识
    remoteEnableFastPeer = false;
  }

  List<int> removeRequest(int index, int begin, int length) {
    var request = _removeRequestFromBuffer(index, begin, length);
    if (request != null) {
      var timer = _requestTimeoutMap.remove('$index-$begin');
      timer?.cancel();
    }
    return request;
  }

  bool addRequest(int index, int begin, int length,
      [int timeout = REQUEST_TIME_OUT]) {
    if (_requestBuffer.length >= MAX_REQUEST_COUNT) return false;
    _requestBuffer.add([index, begin, length]);
    var t = Timer(Duration(seconds: timeout), () {
      _requestTimeout(index, begin, length);
    });
    _requestTimeoutMap['$index-$begin'] = t;
    return true;
  }

  void _processReceiveData(dynamic data) {
    // 不管收到什么消息，只要不是空的，重置倒计时:
    if (data.isNotEmpty) _startToCountdown();
    // if (data.isNotEmpty) log('收到数据 $data');
    _cacheBuffer.addAll(data); // 接受remote发送数据。缓冲到一处
    if (_cacheBuffer.isEmpty) return;
    // 查看是不是handshake头
    if (_cacheBuffer[0] == 19 && _cacheBuffer.length >= 68) {
      if (_isHandShakeHead(_cacheBuffer)) {
        if (_validateInfoHash(_cacheBuffer)) {
          var temp = _cacheBuffer.sublist(0, 68);
          _cacheBuffer = _cacheBuffer.sublist(68);
          _processHandShake(temp);
          if (_cacheBuffer.isNotEmpty) {
            Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
          }
          return;
        } else {
          // If infohash buffer is incorret , dispose this peer
          dispose('Infohash is incorret');
          return;
        }
      }
    }
    if (_cacheBuffer.length >= 4) {
      var length =
          ByteData.sublistView(Uint8List.fromList(_cacheBuffer.sublist(0, 4)))
              .getUint32(0, Endian.big);
      if (length == 0) {
        _cacheBuffer = _cacheBuffer.sublist(4);
        _processMessage(<int>[]);
        if (_cacheBuffer.isNotEmpty) {
          Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
        }
      } else {
        if (_cacheBuffer.length - 4 >= length) {
          var temp = _cacheBuffer.sublist(4, length + 4);
          _cacheBuffer = _cacheBuffer.sublist(length + 4);
          // print('receive $length datas : $temp , ${temp.length}');
          _processMessage(temp);
          if (_cacheBuffer.isNotEmpty) {
            Future.delayed(Duration.zero, () => _processReceiveData(<int>[]));
          }
        }
      }
    }
  }

  bool _isHandShakeHead(buffer) {
    if (buffer.length < 68) return false;
    for (var i = 0; i < 20; i++) {
      if (buffer[i] != HAND_SHAKE_HEAD[i]) return false;
    }
    return true;
  }

  bool _validateInfoHash(buffer) {
    for (var i = 28; i < 48; i++) {
      if (buffer[i] != _infoHashBuffer[i - 28]) return false;
    }
    return true;
  }

  void _processMessage(List<int> message) {
    if (message.isEmpty) {
      _log('process keep alive $address');
      fireKeepAlive();
      return;
    } else {
      switch (message[0]) {
        case ID_CHOKE:
          _log('remote choke me : $address');
          chokeMe = true; // choke message
          return;
        case ID_UNCHOKE:
          _log('remote unchoke me : $address');
          chokeMe = false; // unchoke message
          return;
        case ID_INTERESTED:
          _log('remote interested me : $address');
          interestedMe = true;
          return; // interested message
        case ID_NOT_INTERESTED:
          _log('remote not interseted me : $address');
          interestedMe = false;
          return; // not interseted message
        case ID_HAVE:
          _log('process have from : $address');
          var index = ByteData.sublistView(
                  Uint8List.fromList(message), 1, message.length)
              .getUint32(0);
          _processHave(index);
          return; // have message
        case ID_BITFIELD:
          // log('process bitfield from $address');
          initRemoteBitfield(message);
          return; // bitfield message
        case ID_REQUEST:
          _log('process request from ${address}');
          _processRemoteRequest(message);
          return; // request message
        case ID_PIECE:
          _log('process pices : $address');
          _processReceivePiece(Uint8List.fromList(message));
          return; // pices message
        case ID_CANCEL:
          _log('process cancel : $address');
          _processCancel(message);
          return; // cancel message
        case ID_PORT:
          _log('process port : $address');
          var port = ByteData.sublistView(
              Uint8List.fromList(message), 1, message.length);
          _processPortChange(port.getUint32(0));
          return; // port message
        case OP_HAVE_ALL:
          _log('process have all : $address');
          _processHaveAll();
          return;
        case OP_HAVE_NONE:
          _log('process have none : $address');
          _processHaveNone();
          return;
        case OP_SUGGEST_PIECE:
          _log('process suggest pieces : $address');
          _processSuggestPiece(message);
          return;
        case OP_REJECT_REQUEST:
          _log('process reject request : $address');
          _processRejectRequest(message);
          return;
        case OP_ALLOW_FAST:
          _log('process allow fast : $address');
          _processAllowFast(message);
          return;
        case ID_EXTENDED:
          _processExtendedMessage(message);
          return;
      }
    }
    _log('Cannot process the message', 'Unknown message : ${message}');
  }

  /// 从requestbuffer中将request删除
  ///
  /// 每当得到了piece回应或者request超时，都会调用此方法
  List<int> _removeRequestFromBuffer(int index, int begin, int length) {
    var i = _findRequestIndexFromBuffer(index, begin, length);
    if (i != -1) {
      return _requestBuffer.removeAt(i);
    }
    return null;
  }

  int _findRequestIndexFromBuffer(int index, int begin, int length) {
    for (var i = 0; i < _requestBuffer.length; i++) {
      var r = _requestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        return i;
      }
    }
    return -1;
  }

  void _processExtendedMessage(List<int> message) {
    var id = message[1];
    var m = message.sublist(2);
    processExtendMessage(id, m);
  }

  void sendExtendMessage(String name, dynamic data) {
    var id = getExtendedEventId(name);
    if (id != null) {
      var message = <int>[];
      message.add(id);
      var m = encode(data);
      message.addAll(m);
      sendMessage(ID_EXTENDED, message);
    }
  }

  void _processCancel(List<int> message, [int offset = 1]) {
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    var requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex != null) {
      _remoteRequestBuffer.removeAt(requestIndex);
      fireCancel(index, begin, length);
    }
  }

  void _processPortChange(int port) {
    if (address.port == port) return;
    firePortChange(port);
  }

  void _processHaveAll() {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'have all\'');
      return;
    }
    for (var i = 0; i < _remoteBitfield.buffer.length - 1; i++) {
      _remoteBitfield.buffer[i] = 255;
    }
    var index = _remoteBitfield.buffer.length - 1;
    index = index * 8;
    for (var i = index; i < _remoteBitfield.piecesNum; i++) {
      _remoteBitfield.setBit(i, true);
    }
    fireRemoteHaveAll();
  }

  void _processHaveNone() {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'have none\'');
      return;
    }
    _remoteBitfield = Bitfield.createEmptyBitfield(_piecesNum);
    fireRemoteHaveNone();
  }

  ///
  /// When the fast extension is disabled, if a peer receives a Suggest Piece message,
  /// the peer MUST close the connection.
  void _processSuggestPiece(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'suggest piece\'');
      return;
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    if (_remoteSuggestPieces.add(index)) fireSuggestPiece(index);
  }

  void _processRejectRequest(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'reject request\'');
      return;
    }

    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    if (removeRequest(index, begin, length) != null) {
      fireRejectRequest(index, begin, length);
    } else {
      dispose('Never send request ($index,$begin) but recieve a rejection');
      return;
    }
  }

  void _processAllowFast(List<int> message, [int offset = 1]) {
    if (!remoteEnableFastPeer) {
      dispose('Remote disabled fast extension but receive \'allow fast\'');
      return;
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    if (_remoteAllowFastPieces.add(index)) {
      fireAllowFast(index);
    }
  }

  /// When the fast extension is enabled:
  ///
  /// - If a peer receives a request from a peer its choking, the peer receiving the
  /// request SHOULD send a reject unless the piece is in the allowed fast set.
  /// - If a peer receives an excessive number of requests from a peer it is choking,
  /// the peer receiving the requests MAY close the connection rather than reject the request.
  /// However, consider that it can take several seconds for buffers to drain and messages to propagate once a peer is choked.
  void _processRemoteRequest(List<int> message, [int offset = 1]) {
    if (_remoteRequestBuffer.length >= MAX_REQUEST_COUNT) {
      dev.log('Request Error:',
          error: 'Too many requests from ${address}',
          name: runtimeType.toString());
      dispose(BadException('Too many requests from ${address}'));
      return;
    }
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    var length = view.getUint32(offset + 8);
    if (length > MAX_REQUEST_LENGTH) {
      dev.log('TOO LARGEt BLOCK',
          error: 'BLOCK $length', name: runtimeType.toString());
      dispose(BadException(
          '${address} : request block length larger than limit : $length > $MAX_REQUEST_LENGTH'));
      return;
    }
    // 重复的不管？
    // for (var i = 0; i < _remoteRequestBuffer.length; i++) {
    //   var re = _remoteRequestBuffer[i];
    //   if (re[0] == index && re[1] == begin && re[2] == length) return;
    // }
    if (chokeRemote) {
      if (_allowFastPieces.contains(index)) {
        _remoteRequestBuffer.add([index, begin, length]);
        fireRequest(index, begin, length);
        return;
      } else {
        // choke对方我不需要应答
        // sendRejectRequest(index, begin, length);
        return;
      }
    }
    _remoteRequestBuffer.add([index, begin, length]);
    fireRequest(index, begin, length);
  }

  void _processReceivePiece(List<int> message, [int offset = 1]) {
    var view = ByteData.view(Uint8List.fromList(message).buffer);
    var index = view.getUint32(offset);
    var begin = view.getUint32(offset + 4);
    removeRequest(index, begin, message.length);
    var contentLength = message.length - offset - 8;
    _downloaded += contentLength;
    _log('收到请求Piece ($index,$begin) 内容, 从当前Peer已下载 $downloaded bytes ');
    firePiece(index, begin, message.sublist(offset + 8));
  }

  void _processHave(int index) {
    updateRemoteBitfield(index, true);
    fireHave(index);
  }

  /// 更新远程Bitfield
  void updateRemoteBitfield(int index, bool have) {
    _remoteBitfield.setBit(index, have);
  }

  void initRemoteBitfield(List<int> bitfield) {
    _remoteBitfield = Bitfield.copyFrom(_piecesNum, bitfield, 1);
    fireBitfield(_remoteBitfield);
  }

  void _processHandShake(List<int> data) {
    _remotePeerId = _parseRemotePeerId(data);
    var reseverd = data.getRange(20, 28);
    var fast = reseverd.elementAt(7) & 0x04;
    remoteEnableFastPeer = (fast == 0x04);
    var extented = reseverd.elementAt(5);
    remoteEnableExtended = ((extented & 0x10) == 0x10);
    _sendExtendedHandshake();
    fireHandshakeEvent(_remotePeerId, data);
  }

  void _sendExtendedHandshake() {
    if (localEnableExtended && remoteEnableExtended) {
      var m = _createExtenedHandshakeMessage();
      sendMessage(ID_EXTENDED, m);
    }
  }

  String _parseRemotePeerId(dynamic data) {
    if (data is List<int>) {
      return String.fromCharCodes(data.sublist(48, 68));
    }
    return null;
  }

  /// Connect remote peer and return a [Stream] future
  ///
  /// [timeout] defaul value is 30 seconds
  /// Different type peer use different protocol , such as TCP,uTP,
  /// so this method should be implemented by sub-class
  Future<Stream> connectRemote(int timeout);

  /// Send message to remote
  ///
  /// this method will transform the [message] and id to be the peer protocol message bytes
  void sendMessage(int id, [List<int> message]) {
    if (isDisposed) return;
    if (id == null) {
      // it's keep alive
      sendByteMessage(KEEP_ALIVE_MESSAGE);
      _startToCountdown();
      return;
    }
    var m = _createByteMessage(id, message);
    sendByteMessage(m);
    _startToCountdown();
  }

  List<int> _createByteMessage(int id, List<int> message) {
    var m = <int>[];
    var l = Uint8List(4);
    var length = 0;
    if (message != null) length = message.length;
    length = length + 1;
    var view = ByteData.view(l.buffer);
    view.setUint32(0, length, Endian.big);
    m.addAll(l);
    m.add(id);
    if (message != null && message.isNotEmpty) {
      m.addAll(message);
    }
    return m;
  }

  /// Send the message buffer to remote
  ///
  /// See : [Peer protocol message](https://wiki.theory.org/BitTorrentSpecification#Messages)
  void sendByteMessage(List<int> bytes);

  /// 发送handshake消息。
  ///
  /// 在发送handshake后，会主动发送bitfield和have消息给对方
  void sendHandShake() {
    if (_handShaked) return;
    var message = <int>[];
    message.addAll(HAND_SHAKE_HEAD);
    var reseverd = List<int>.from(RESERVED);
    if (localEnableFastPeer) {
      reseverd[7] |= 0x04;
    }
    if (localEnableExtended) {
      reseverd[5] |= 0x10;
    }
    message.addAll(reseverd);
    message.addAll(_infoHashBuffer);
    message.addAll(utf8.encode(_localPeerId));
    sendByteMessage(message);
    _startToCountdown();
    _handShaked = true;
  }

  List<int> _createExtenedHandshakeMessage() {
    var message = <int>[];
    message.add(0);
    var d = <String, dynamic>{};
    d['yourip'] = address.address.rawAddress;
    d['v'] = 'Dart BT v0.1.0';
    d['m'] = localExtened;
    var m = encode(d);
    message.addAll(m);
    return message;
  }

  /// `keep-alive: <len=0000>`
  ///
  /// The `keep-alive` message is a message with zero bytes, specified with the length prefix set to zero.
  /// There is no message ID and no payload. Peers may close a connection if they receive no messages
  /// (keep-alive or any other message) for a certain period of time, so a keep-alive message must be
  /// sent to maintain the connection alive if no command have been sent for a given amount of time.
  /// This amount of time is generally two minutes.
  void sendKeeplive() {
    sendMessage(null);
  }

  /// `piece: <len=0009+X><id=7><index><begin><block>`
  ///
  /// The `piece` message is variable length, where X is the length of the block. The payload contains the following information:
  ///
  /// - index: integer specifying the zero-based piece index
  /// - begin: integer specifying the zero-based byte offset within the piece
  /// - block: block of data, which is a subset of the piece specified by index.
  bool sendPiece(int index, int begin, List<int> block) {
    if (chokeRemote) {
      if (!remoteEnableFastPeer || !_allowFastPieces.contains(index)) {
        return false;
      }
    }
    int requestIndex;
    for (var i = 0; i < _remoteRequestBuffer.length; i++) {
      var r = _remoteRequestBuffer[i];
      if (r[0] == index && r[1] == begin) {
        requestIndex = i;
        break;
      }
    }
    if (requestIndex == null) return false;
    _remoteRequestBuffer.removeAt(requestIndex);
    var bytes = <int>[];
    var messageHead = Uint8List(8);
    var view = ByteData.view(messageHead.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    bytes.addAll(messageHead);
    bytes.addAll(block);
    sendMessage(ID_PIECE, bytes);
    _uploaded += bytes.length;
    return true;
  }

  /// `request: <len=0013><id=6><index><begin><length>`
  ///
  /// The `request` message is fixed length, and is used to request a block.
  /// The payload contains the following information:
  ///
  /// - [index]: integer specifying the zero-based piece index
  /// - [begin]: integer specifying the zero-based byte offset within the piece
  /// - [length]: integer specifying the requested length.
  /// - [timeout]: when send request to remote , after [timeout] dont get response,
  /// it will fire [requestTimeout] event
  bool sendRequest(int index, int begin,
      [int length = DEFAULT_REQUEST_LENGTH, int timeout = REQUEST_TIME_OUT]) {
    if (_chokeMe) {
      if (!remoteEnableFastPeer || !_remoteAllowFastPieces.contains(index)) {
        return false;
      }
    }

    if (!addRequest(index, begin, length, timeout)) {
      return false;
    }
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    sendMessage(ID_REQUEST, bytes);
    return true;
  }

  void _requestTimeout(int index, int begin, int length) {
    var timer = _requestTimeoutMap.remove('$index-$begin');
    timer?.cancel();
    fireRequestTimeoutEvent(index, begin, length);
  }

  /// `bitfield: <len=0001+X><id=5><bitfield>`
  ///
  /// The `bitfield` message may only be sent immediately after the handshaking sequence is completed,
  /// and before any other messages are sent. It is optional, and need not be sent if a client has no pieces.
  /// However,if no pieces to send and remote peer enable fast extension, it will send `Have None` message,
  /// and if have all pieces, it will send `Have All` message instead of bitfield buffer.
  ///
  /// The `bitfield` message is variable length, where X is the length of the bitfield. The payload is a
  /// bitfield representing the pieces that have been successfully downloaded. The high bit in the first byte
  /// corresponds to piece index 0. Bits that are cleared indicated a missing piece, and set bits indicate a
  /// valid and available piece. Spare bits at the end are set to zero.
  ///
  void sendBitfield(Bitfield bitfield) {
    _log('发送bitfile信息给对方 : ${bitfield.buffer}');
    if (_bitfieldSended) return;
    _bitfieldSended = true;
    if (remoteEnableFastPeer && localEnableFastPeer) {
      if (bitfield.haveNone()) {
        sendHaveNone();
      } else if (bitfield.haveAll()) {
        sendHaveAll();
      } else {
        sendMessage(ID_BITFIELD, bitfield.buffer);
      }
    } else if (bitfield.haveCompletePiece()) {
      sendMessage(ID_BITFIELD, bitfield.buffer);
    }
  }

  /// `have: <len=0005><id=4><piece index>`
  ///
  /// The `have` message is fixed length. The payload is the zero-based
  /// index of a piece that has just been successfully downloaded and verified via the hash.
  void sendHave(int index) {
    var bytes = Uint8List(4);
    _log('发送have信息给对方 : ${bytes},$index');
    ByteData.view(bytes.buffer).setUint32(0, index, Endian.big);
    sendMessage(ID_HAVE, bytes);
  }

  /// - `choke: <len=0001><id=0>`
  /// - `unchoke: <len=0001><id=1>`
  ///
  /// The `choke`/`unchoke` message is fixed-length and has no payload.
  void sendChoke(bool ichokeu) {
    if (chokeRemote == ichokeu) {
      return;
    }
    chokeRemote = ichokeu;
    var id = ID_CHOKE;
    if (!ichokeu) id = ID_UNCHOKE;
    sendMessage(id);
  }

  /// 发送`interested` 或 `not interested` 到 对方，表明自己是否对它拥有资源感兴趣
  ///
  /// - `interested: <len=0001><id=2>`
  /// - `not interested: <len=0001><id=3>`
  ///
  /// The `interested`/`not interested` message is fixed-length and has no payload.
  void sendInterested(bool iamInterested) {
    if (interestedRemote == iamInterested) {
      return;
    }
    interestedRemote = iamInterested;
    var id = ID_INTERESTED;
    if (!iamInterested) id = ID_NOT_INTERESTED;
    sendMessage(id);
  }

  /// `cancel: <len=0013><id=8><index><begin><length>`
  ///
  /// The `cancel` message is fixed length, and is used to cancel block requests.
  /// The payload is identical to that of the "request" message. It is typically used during "End Game"
  void sendCancel(int index, int begin, int length) {
    var bytes = Uint8List(12);
    var view = ByteData.view(bytes.buffer);
    view.setUint32(0, index, Endian.big);
    view.setUint32(4, begin, Endian.big);
    view.setUint32(8, length, Endian.big);
    sendMessage(ID_CANCEL, bytes);
  }

  /// `port: <len=0003><id=9><listen-port>`
  ///
  /// The [port] message is sent by newer versions of the Mainline that implements a DHT tracker.
  /// The listen port is the port this peer's DHT node is listening on. This peer should be
  /// inserted in the local routing table (if DHT tracker is supported).
  void sendPortChange(int port) {
    var bytes = Uint8List(8);
    ByteData.view(bytes.buffer).setUint32(0, port);
    sendMessage(ID_PORT, bytes);
  }

  /// BEP 0006
  ///
  /// Have all message
  void sendHaveAll() {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      sendMessage(OP_HAVE_ALL);
    }
  }

  /// BEP 0006
  ///
  /// Have none message
  void sendHaveNone() {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      sendMessage(OP_HAVE_NONE);
    }
  }

  /// BEP 0006
  /// `*Suggest Piece*: <len=0x0005><op=0x0D><index>`
  ///
  /// `Suggest Piece` is an advisory message meaning "you might like to download this piece."
  /// The intended usage is for 'super-seeding' without throughput reduction, to avoid redundant
  /// downloads, and so that a seed which is disk I/O bound can upload continguous or identical
  /// pieces to avoid excessive disk seeks.
  ///
  /// In all cases, the seed SHOULD operate to maintain a roughly equal number of copies of each
  /// piece in the network. A peer MAY send more than one suggest piece message at any given time.
  /// A peer receiving multiple suggest piece messages MAY interpret this as meaning that all of
  /// the suggested pieces are equally appropriate.
  ///
  void sendSuggestPiece(int index) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      var bytes = Uint8List(4);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      sendMessage(OP_SUGGEST_PIECE, bytes);
    }
  }

  /// BEP 0006
  ///
  /// `*Reject Request*: <len=0x000D><op=0x10><index><begin><length>`
  ///
  /// Reject Request notifies a requesting peer that its request will not be satisfied.
  ///
  void sendRejectRequest(int index, int begin, int length) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      var bytes = Uint8List(12);
      var view = ByteData.view(bytes.buffer);
      view.setUint32(0, index, Endian.big);
      view.setUint32(4, begin, Endian.big);
      view.setUint32(8, length, Endian.big);
      sendMessage(OP_REJECT_REQUEST, bytes);
    }
  }

  /// BEP 0006
  ///
  /// `*Allowed Fast*: <len=0x0005><op=0x11><index>`
  ///
  /// `Allowed Fast` is an advisory message which means "if you ask for this piece,
  /// I'll give it to you even if you're choked."
  ///
  /// `Allowed Fast` thus shortens the awkward stage during which the peer obtains occasional
  ///  optimistic unchokes but cannot sufficiently reciprocate to remain unchoked.
  ///
  void sendAllowFast(int index) {
    if (remoteEnableFastPeer && localEnableFastPeer) {
      if (_allowFastPieces.add(index)) {
        var bytes = Uint8List(4);
        var view = ByteData.view(bytes.buffer);
        view.setUint32(0, index, Endian.big);
        sendMessage(OP_ALLOW_FAST, bytes);
      }
    }
  }

  /// 开始倒计时。
  ///
  /// Over `countdownTime` seconds , peer will close to disconnect the remote.
  /// but if peer send or receive any message from/to remote during countdown,
  /// it will re-countdown.
  void _startToCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer(Duration(seconds: countdownTime), () {
      dispose('Over ${countdownTime} seconds no communication, close');
    });
  }

  /// 该Peer被dispose。
  ///
  /// 被dispose后的peer将无法再发送或监听数据，状态数据也恢复到初始状态，并且之前添加的事件监听
  /// 器都会被移除。
  Future dispose([dynamic reason]) async {
    if (_disposed) return;
    _disposeReason = reason;
    _disposed = true;
    _handShaked = false;
    _bitfieldSended = false;
    _endTime = DateTime.now().millisecondsSinceEpoch;
    fireDisposeEvent(reason);
    clearEventHandles();
    clearExtendedProcessors();
    var re = _streamChunk?.cancel();
    _streamChunk = null;
    _requestTimeoutMap.forEach((key, value) {
      value?.cancel();
    });
    _requestTimeoutMap.clear();
    _countdownTimer?.cancel();
    _countdownTimer = null;
    return re;
  }

  void _log(String message, [dynamic error]) {
    if (error != null) {
      // dev.log(message, error: error, name: runtimeType.toString());
    } else {
      // log(message, name: runtimeType.toString());
    }
  }

  @override
  int get hashCode => address.address.address.hashCode;

  @override
  bool operator ==(b) {
    if (b is Peer) {
      return b.address.address.address == address.address.address;
    }
    return false;
  }
}

class BadException implements Exception {
  final dynamic e;
  BadException(this.e);
  @override
  String toString() {
    return '不需重连错误 : $e';
  }
}

class _TCPPeer extends Peer {
  Socket _socket;
  _TCPPeer(String localPeerId, CompactAddress address, List<int> infoHashBuffer,
      int piecesNum, this._socket,
      {bool enableExtend = true, bool enableFast = true})
      : super(localPeerId, address, infoHashBuffer, piecesNum,
            type: PeerType.TCP,
            localEnableExtended: enableExtend,
            localEnableFastPeer: enableFast);

  @override
  Future<Stream> connectRemote(int timeout) async {
    timeout ??= 30;
    _socket ??= await Socket.connect(address.address, address.port,
        timeout: Duration(seconds: timeout));
    return _socket;
  }

  @override
  void sendByteMessage(List<int> bytes) {
    try {
      _socket?.add(bytes);
    } catch (e) {
      dispose(e);
    }
  }

  @override
  Future dispose([reason]) async {
    try {
      await _socket?.close();
      _socket = null;
    } catch (e) {
      // do nothing
    } finally {
      return super.dispose(reason);
    }
  }
}
