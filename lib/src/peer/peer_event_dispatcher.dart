import 'dart:async';

import 'bitfield.dart';

/// 带有 [index],[begin],[length]参数的方法
typedef PieceConfigHandle = void Function(
    dynamic source, int index, int begin, int length);
typedef NoneParamHandle = void Function(dynamic source);

typedef BoolHandle = void Function(dynamic source, bool value);

typedef SingleIntHandle = void Function(dynamic source, int value);

const PEER_EVENT_CONNECTED = 'connected';
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

  void fireDisposeEvent([dynamic reason]) {
    var fSet = _handleFunctions[PEER_EVENT_DISPOSE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, reason));
    });
  }

  void fireHandshakeEvent(String? remotePeerId, dynamic data) {
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

  void fireBitfield(final Bitfield? bitfield) {
    var fSet = _handleFunctions[PEER_EVENT_BITFIELD];
    fSet?.forEach((f) {
      Timer.run(() => f(this, bitfield));
    });
  }

  void firePiece(int index, int begin, List<int> block) {
    var fSet = _handleFunctions[PEER_EVENT_PIECE];
    fSet?.forEach((f) {
      Timer.run(() => f(this, index, begin, block));
    });
  }

  void fireHave(List<int> index) {
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

  /// Add `reject request`  event handler
  bool onRejectRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REJECT_REQUEST);
  }

  /// Remove `reject request`  event handler
  bool offRejectRequest(PieceConfigHandle handle) {
    return _offPieceConfigCallback(handle, PEER_EVENT_REJECT_REQUEST);
  }

  /// Add `allow fast`  event handler
  bool onAllowFast(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_ALLOW_FAST);
  }

  /// Remove `allow fast`  event handler
  bool offAllowFast(SingleIntHandle handle) {
    return _offSingleIntCallback(handle, PEER_EVENT_ALLOW_FAST);
  }

  /// Add `suggest piece`  event handler
  bool onSuggestPiece(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_SUGGEST_PIECE);
  }

  /// Remove `suggest piece`  event handler
  bool offSuggestPiece(SingleIntHandle handle) {
    return _offSingleIntCallback(handle, PEER_EVENT_SUGGEST_PIECE);
  }

  /// Add `have all`  event handler
  bool onHaveAll(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_ALL);
  }

  /// Remove `have all`  event handler
  bool offHaveAll(NoneParamHandle handle) {
    return _offNoneParamCallback(handle, PEER_EVENT_HAVE_ALL);
  }

  /// Add `have none`  event handler
  bool onHaveNone(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_HAVE_NONE);
  }

  /// Remove `have none`  event handler
  bool offHaveNone(NoneParamHandle handle) {
    return _offNoneParamCallback(handle, PEER_EVENT_HAVE_NONE);
  }

  /// Add `cancel`  event handler
  bool onCancel(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_CANCEL);
  }

  /// Add `cancel`  event handler
  bool offCancel(PieceConfigHandle handle) {
    return _offPieceConfigCallback(handle, PEER_EVENT_CANCEL);
  }

  /// Add `port`  event handler
  bool onPortChange(SingleIntHandle handle) {
    return _onSingleIntCallback(handle, PEER_EVENT_PORT);
  }

  /// Add `port`  event handler
  bool offPortChange(SingleIntHandle handle) {
    return _offSingleIntCallback(handle, PEER_EVENT_PORT);
  }

  /// Add `remote have`  event handler
  bool onHave(void Function(dynamic source, List<int> indices) handle) {
    var list = _getFunctionSet(PEER_EVENT_HAVE);
    return list.add(handle);
  }

  /// Remove `remote have`  event handler
  bool offHave(void Function(dynamic source, List<int> indices) handle) {
    var list = _getFunctionSet(PEER_EVENT_HAVE);
    return list.remove(handle);
  }

  /// Add `receive remote piece`  event handler
  bool onPiece(
      Function(dynamic source, int index, int begin, List<int> block) handle) {
    var list = _getFunctionSet(PEER_EVENT_PIECE);
    return list.add(handle);
  }

  /// Remove `receive remote piece`  event handler
  bool offPiece(
      Function(dynamic source, int index, int begin, List<int> block) handle) {
    var list = _getFunctionSet(PEER_EVENT_PIECE);
    return list.remove(handle);
  }

  /// Add `remote bitfield`  event handler
  bool onBitfield(Function(dynamic source, Bitfield bitfield) handle) {
    var list = _getFunctionSet(PEER_EVENT_BITFIELD);
    return list.add(handle);
  }

  /// Remove `remote bitfield`  event handler
  bool offBitfield(Function(dynamic source, Bitfield bitfield) handle) {
    var list = _getFunctionSet(PEER_EVENT_BITFIELD);
    return list.remove(handle);
  }

  /// Add `remote keep alive`  event handler
  bool onKeepalive(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_KEEPALIVE);
  }

  /// Remove `remote keep alive`  event handler
  bool offKeepalive(NoneParamHandle handle) {
    return _offNoneParamCallback(handle, PEER_EVENT_KEEPALIVE);
  }

  /// Add `choke` ,`unchoke`  event handler
  bool onChokeChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_CHOKE_CHANGE);
  }

  /// Remove `choke` ,`unchoke`  event handler
  bool offChokeChange(BoolHandle handle) {
    return _offBoolCallback(handle, PEER_EVENT_CHOKE_CHANGE);
  }

  /// Add `interested` ,`not interested`  event handler
  bool onInterestedChange(BoolHandle handle) {
    return _onBoolCallback(handle, PEER_EVENT_INTERESTED_CHANGE);
  }

  /// Remove `interested` ,`not interested`  event handler
  bool offInterestedChange(BoolHandle handle) {
    return _offBoolCallback(handle, PEER_EVENT_INTERESTED_CHANGE);
  }

  /// Add `remote request` event handler
  bool onRequest(PieceConfigHandle handle) {
    return _onPieceConfigCallback(handle, PEER_EVENT_REQUEST);
  }

  /// Remove `remote request` event handler
  bool offRequest(PieceConfigHandle handle) {
    return _offPieceConfigCallback(handle, PEER_EVENT_REQUEST);
  }

  /// Add `handshake` event handler
  bool onHandShake(
      void Function(dynamic source, String remotePeerId, dynamic data) handle) {
    var list = _getFunctionSet(PEER_EVENT_HANDSHAKE);
    return list.add(handle);
  }

  /// Remove `handshake` event handler
  bool offHandShake(
      void Function(dynamic source, String remotePeerId, dynamic data) handle) {
    var list = _getFunctionSet(PEER_EVENT_HANDSHAKE);
    return list.remove(handle);
  }

  /// Add `connect` event handler
  bool onConnect(NoneParamHandle handle) {
    return _onNoneParamCallback(handle, PEER_EVENT_CONNECTED);
  }

  /// Remove `connect` event handler
  bool offConnect(NoneParamHandle handle) {
    return _offNoneParamCallback(handle, PEER_EVENT_CONNECTED);
  }

  /// Add `dispose` event handler
  bool onDispose(Function(dynamic source, [dynamic reason]) handle) {
    var list = _getFunctionSet(PEER_EVENT_DISPOSE);
    return list.add(handle);
  }

  /// Remove `dispose` event handler
  bool offDispose(Function(dynamic source, [dynamic reason]) handle) {
    var list = _getFunctionSet(PEER_EVENT_DISPOSE);
    return list.remove(handle);
  }

  bool _onNoneParamCallback(NoneParamHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _offNoneParamCallback(NoneParamHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.remove(handle);
  }

  bool _onPieceConfigCallback(PieceConfigHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _offPieceConfigCallback(PieceConfigHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.remove(handle);
  }

  bool _onBoolCallback(BoolHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _offBoolCallback(BoolHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.remove(handle);
  }

  bool _onSingleIntCallback(SingleIntHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.add(handle);
  }

  bool _offSingleIntCallback(SingleIntHandle handle, String type) {
    var list = _getFunctionSet(type);
    return list.remove(handle);
  }

  void clearEventHandles() {
    _handleFunctions.clear();
  }
}
