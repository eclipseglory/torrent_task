import 'dart:async';

import 'bitfield.dart';

/// 带有 [index],[begin],[length]参数的方法
typedef PieceConfigHandle = void Function(
    dynamic source, int index, int begin, int length);
typedef NoneParamHandle = void Function(dynamic source);

typedef BoolHandle = void Function(dynamic source, bool value);

typedef SingleIntHandle = void Function(dynamic source, int value);

const PEER_EVENT_CONNECTED = 'connected';
const PEER_EVENT_REQUEST_TIMEOUT = 'request_timeout';
const PEER_EVENT_DISPOSE = 'close';
const PEER_EVENT_HANDSHAKE = 'handshake';
const PEER_EVENT_CHOKE_CHANGE = 'choke_change';
const PEER_EVENT_REQUEST = 'request';
const PEER_EVENT_BITFIELD = 'bitfield';
const PEER_EVENT_HAVE = 'have';
const PEER_EVENT_INTERESTED_CHANGE = 'interested_change';
const PEER_EVENT_PIECE = 'piece';
const PEER_EVENT_CANCEL = 'cancel';
const PEER_EVENT_PORT = 'port';
const PEER_EVENT_KEEPALIVE = 'keep_alive';
const PEER_EVENT_HAVE_ALL = 'have_all';
const PEER_EVENT_HAVE_NONE = 'have_none';
const PEER_EVENT_SUGGEST_PIECE = 'suggest_piece';
const PEER_EVENT_ALLOW_FAST = 'allow_fast';
const PEER_EVENT_REJECT_REQUEST = 'reject_request';

/// 专门负责添加、删除Peer事件回调方法的 `mixin`
mixin PeerEventDispatcher {
  /// 所有事件回调方法Map
  final _handleFunctions = <String, Set<Function>>{};

  Set<Function> _getFunctionSet(String key) {
    var fSet = _handleFunctions[key];
    if (fSet == null) {
      fSet = <Function>{};
      _handleFunctions[key] = fSet;
    }
    return fSet;
  }

  void fireConnectEvent() {
    var fSet = _handleFunctions[PEER_EVENT_CONNECTED];
    fSet?.forEach((f) {
      Timer.run(() => f(this));
    });
  }

  void fireRequestTimeoutEvent(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REQUEST_TIMEOUT];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void fireDisposeEvent([dynamic reason]) {
    var fSet = _handleFunctions[PEER_EVENT_DISPOSE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, reason));
    });
  }

  void fireHandshakeEvent(String remotePeerId, dynamic data) {
    var fSet = _handleFunctions[PEER_EVENT_HANDSHAKE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, remotePeerId, data));
    });
  }

  void fireChokeChangeEvent(bool choke) {
    var fSet = _handleFunctions[PEER_EVENT_CHOKE_CHANGE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, choke));
    });
  }

  void fireInterestedChangeEvent(bool interested) {
    var fSet = _handleFunctions[PEER_EVENT_INTERESTED_CHANGE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, interested));
    });
  }

  void fireKeepAlive() {
    var fSet = _handleFunctions[PEER_EVENT_KEEPALIVE];
    fSet?.forEach((f) {
      Timer.run(() => f(this));
    });
  }

  void fireRequest(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REQUEST];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void fireBitfield(final Bitfield bitfield) {
    var fSet = _handleFunctions[PEER_EVENT_BITFIELD];
    fSet?.forEach((f) {
      Timer.run(() => f(this, bitfield));
    });
  }

  void firePiece(int index, int begin, List<int> block,
      [bool afterTimeout = false]) {
    var fSet = _handleFunctions[PEER_EVENT_PIECE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, block, afterTimeout));
    });
  }

  void fireHave(dynamic index) {
    var fSet = _handleFunctions[PEER_EVENT_HAVE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index));
    });
  }

  void fireCancel(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_CANCEL];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, length));
    });
  }

  void firePortChange(int port) {
    var fSet = _handleFunctions[PEER_EVENT_PORT];
    fSet?.forEach((f) {
      f(this, port);
    });
  }

  void fireRemoteHaveAll() {
    var fSet = _handleFunctions[PEER_EVENT_HAVE_ALL];
    fSet?.forEach((f) {
      f(this);
    });
  }

  void fireRemoteHaveNone() {
    var fSet = _handleFunctions[PEER_EVENT_HAVE_NONE];
    fSet?.forEach((f) {
      f(this);
    });
  }

  void fireSuggestPiece(int index) {
    var fSet = _handleFunctions[PEER_EVENT_SUGGEST_PIECE];
    fSet?.forEach((f) {
      f(this, index);
    });
  }

  void fireAllowFast(int index) {
    var fSet = _handleFunctions[PEER_EVENT_ALLOW_FAST];
    fSet?.forEach((f) {
      f(this, index);
    });
  }

  void fireRejectRequest(int index, int begin, int length) {
    var fSet = _handleFunctions[PEER_EVENT_REJECT_REQUEST];
    fSet?.forEach((f) {
      f(this, index, begin, length);
    });
  }

  bool onRejectRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REJECT_REQUEST);
  }

  bool onAllowFast(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_ALLOW_FAST);
  }

  bool onSuggestPiece(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_SUGGEST_PIECE);
  }

  bool onHaveAll(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_ALL);
  }

  bool onHaveNone(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_NONE);
  }

  bool onCancel(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_CANCEL);
  }

  bool onPortChange(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_PORT);
  }

  bool onHave(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_HAVE);
  }

  bool onPiece(
      Function(dynamic source, int index, int begin, List<int> block,
              bool afterTimeout)
          handle) {
    var list = _getFunctionSet(PEER_EVENT_PIECE);
    return list.add(handle);
  }

  bool onBitfield(Function(dynamic source, Bitfield bitfield) handle) {
    var list = _getFunctionSet(PEER_EVENT_BITFIELD);
    return list.add(handle);
  }

  bool onKeepalive(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_KEEPALIVE);
  }

  bool onChokeChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_CHOKE_CHANGE);
  }

  bool onInterestedChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_INTERESTED_CHANGE);
  }

  bool onRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REQUEST);
  }

  bool onRequestTimeout(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REQUEST_TIMEOUT);
  }

  bool onHandShake(
      void Function(dynamic source, String remotePeerId, dynamic data) handle) {
    var list = _getFunctionSet(PEER_EVENT_HANDSHAKE);
    return list.add(handle);
  }

  bool onConnect(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_CONNECTED);
  }

  bool onDispose(Function(dynamic source, [dynamic reason]) handle) {
    var list = _getFunctionSet(PEER_EVENT_DISPOSE);
    return list.add(handle);
  }

  bool _onNoneParamCallback(NoneParamHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onPieceConfigCallback(PieceConfigHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onBoolCallback(BoolHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _onSingleIntCallback(SingleIntHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  void clearEventHandles() {
    _handleFunctions.clear();
  }
}
