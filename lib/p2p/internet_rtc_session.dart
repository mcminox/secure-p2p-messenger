import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class InternetRtcSession {
  InternetRtcSession._();

  static Map<String, dynamic> _iceConfig() => {
        'sdpSemantics': 'unified-plan',
        'iceServers': [
          {'urls': 'stun:stun.l.google.com:19302'},
          {'urls': 'stun:stun1.l.google.com:19302'},
        ],
      };

  RTCPeerConnection? _pc;
  RTCDataChannel? _dc;
  final StreamController<Uint8List> _incoming = StreamController<Uint8List>.broadcast();

  Stream<Uint8List> get incoming => _incoming.stream;

  VoidCallback? onDisconnected;

  bool get isChannelOpen => _dc?.state == RTCDataChannelState.RTCDataChannelOpen;

  static Future<void> _untilIceGatheringDone(RTCPeerConnection pc) async {
    final cur = await pc.getIceGatheringState();
    if (cur == RTCIceGatheringState.RTCIceGatheringStateComplete) return;
    final done = Completer<void>();
    pc.onIceGatheringState = (RTCIceGatheringState s) {
      if (s == RTCIceGatheringState.RTCIceGatheringStateComplete && !done.isCompleted) {
        done.complete();
      }
    };
    try {
      await done.future.timeout(const Duration(seconds: 25));
    } catch (_) {}
    pc.onIceGatheringState = null;
  }

  void _bindPc(RTCPeerConnection pc) {
    pc.onConnectionState = (RTCPeerConnectionState s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          s == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        onDisconnected?.call();
      }
    };
  }

  void _bindDc(RTCDataChannel dc) {
    dc.onMessage = (RTCDataChannelMessage m) {
      if (m.isBinary) {
        _incoming.add(Uint8List.fromList(m.binary));
      }
    };
  }

  static Future<({InternetRtcSession session, String offerSdp})> createCaller() async {
    final session = InternetRtcSession._();
    session._pc = await createPeerConnection(_iceConfig());
    session._bindPc(session._pc!);
    final init = RTCDataChannelInit()..ordered = true;
    session._dc = await session._pc!.createDataChannel('dart_aut_sync_v1', init);
    session._bindDc(session._dc!);
    final offer = await session._pc!.createOffer({});
    await session._pc!.setLocalDescription(offer);
    await _untilIceGatheringDone(session._pc!);
    final loc = await session._pc!.getLocalDescription();
    final sdp = loc?.sdp;
    if (sdp == null || sdp.isEmpty) {
      await session.dispose();
      throw StateError('Не удалось получить SDP offer');
    }
    return (session: session, offerSdp: sdp);
  }

  static Future<({InternetRtcSession session, String answerSdp})> acceptCallee({
    required String offerSdp,
  }) async {
    final session = InternetRtcSession._();
    session._pc = await createPeerConnection(_iceConfig());
    session._bindPc(session._pc!);
    session._pc!.onDataChannel = (RTCDataChannel ch) {
      session._dc = ch;
      session._bindDc(ch);
    };
    await session._pc!.setRemoteDescription(RTCSessionDescription(offerSdp, 'offer'));
    final answer = await session._pc!.createAnswer({});
    await session._pc!.setLocalDescription(answer);
    await _untilIceGatheringDone(session._pc!);
    final loc = await session._pc!.getLocalDescription();
    final sdp = loc?.sdp;
    if (sdp == null || sdp.isEmpty) {
      await session.dispose();
      throw StateError('Не удалось получить SDP answer');
    }
    return (session: session, answerSdp: sdp);
  }

  Future<void> applyAnswerSdp(String answerSdp) async {
    final pc = _pc;
    if (pc == null) throw StateError('Нет PeerConnection');
    await pc.setRemoteDescription(RTCSessionDescription(answerSdp, 'answer'));
  }

  Future<void> sendBytes(Uint8List data) async {
    final ch = _dc;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) {
      throw StateError('Канал ещё не открыт');
    }
    await ch.send(RTCDataChannelMessage.fromBinary(data));
  }

  bool _closed = false;

  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      await _dc?.close();
    } catch (_) {}
    try {
      await _pc?.close();
    } catch (_) {}
    _dc = null;
    _pc = null;
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}
