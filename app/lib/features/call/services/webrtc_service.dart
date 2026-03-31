import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'signaling_client.dart';
import 'sdp_utils.dart';

/// WebRTC service for P2P audio/video calls
class WebRTCService {
  final SignalingClient signaling;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _localVideoStream;
  String? _sessionId;
  bool _isMuted = false;
  bool _isVideoEnabled = false;

  final _remoteStreamController = StreamController<MediaStream?>.broadcast();
  final _iceStateController =
      StreamController<RTCIceConnectionState>.broadcast();
  final _videoStateController = StreamController<bool>.broadcast();

  WebRTCService({required this.signaling}) {
    _listenToSignaling();
  }

  /// Remote media stream
  Stream<MediaStream?> get onRemoteStream => _remoteStreamController.stream;

  /// ICE connection state changes
  Stream<RTCIceConnectionState> get onIceStateChange =>
      _iceStateController.stream;

  /// Current session ID
  String? get sessionId => _sessionId;

  /// Whether local audio is muted
  bool get isMuted => _isMuted;

  /// Whether video is currently enabled
  bool get isVideoEnabled => _isVideoEnabled;

  /// Stream of video state changes
  Stream<bool> get onVideoStateChange => _videoStateController.stream;

  /// Local media stream
  MediaStream? get localStream => _localStream;

  /// Local video stream (separate from audio)
  MediaStream? get localVideoStream => _localVideoStream;

  static final Map<String, dynamic> _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[],
    // No STUN/TURN needed — Tailscale handles NAT traversal
    'sdpSemantics': 'unified-plan',
  };

  void _listenToSignaling() {
    signaling.messages.listen((msg) async {
      switch (msg['type']) {
        case 'auth_result':
          _handleAuthResult(msg);
          break;
        case 'call_initiate':
        case 'call_initiated':
          _handleCallInitiate(msg);
          break;
        case 'sdp_offer':
          await _handleSdpOffer(msg);
          break;
        case 'sdp_answer':
          await _handleSdpAnswer(msg);
          break;
        case 'ice_candidate':
          await _handleIceCandidate(msg);
          break;
        case 'video_request':
          await _handleVideoRequest(msg);
          break;
        case 'call_end':
          await hangUp(fromRemote: true);
          break;
      }
    });
  }

  void _handleAuthResult(Map<String, dynamic> msg) {
    if (msg['success'] == true) {
      debugPrint('WebRTC: auth successful');
      if (msg['session_resumed'] == true) {
        _sessionId = msg['session_id'] as String?;
        debugPrint('WebRTC: session resumed: $_sessionId');
      }
    } else {
      debugPrint('WebRTC: auth failed: ${msg['error']}');
    }
  }

  void _handleCallInitiate(Map<String, dynamic> msg) {
    _sessionId = msg['session_id'] as String?;
    signaling.sessionResumeId = _sessionId;
    debugPrint('WebRTC: call initiated, session: $_sessionId');
  }

  Future<void> _handleSdpOffer(Map<String, dynamic> msg) async {
    _sessionId = msg['session_id'] as String?;
    signaling.sessionResumeId = _sessionId;

    await _ensurePeerConnection();
    await _ensureLocalStream();

    final sdp = msg['sdp'] as String;
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );

    final answer = await _peerConnection!.createAnswer();
    final optimizedSdp =
        SdpUtils.applyOpusOptimizations(answer.sdp!, bitrate: 24000);
    final optimizedAnswer = RTCSessionDescription(optimizedSdp, 'answer');

    await _peerConnection!.setLocalDescription(optimizedAnswer);
    signaling.sendAnswer(_sessionId!, optimizedSdp);
  }

  Future<void> _handleSdpAnswer(Map<String, dynamic> msg) async {
    final sdp = msg['sdp'] as String;
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> msg) async {
    final candidateMap = msg['candidate'] as Map<String, dynamic>;
    final candidate = RTCIceCandidate(
      candidateMap['candidate'] as String,
      candidateMap['sdpMid'] as String,
      candidateMap['sdpMLineIndex'] as int,
    );
    await _peerConnection?.addCandidate(candidate);
  }

  Future<void> _ensurePeerConnection() async {
    if (_peerConnection != null) return;

    _peerConnection = await createPeerConnection(_rtcConfig);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_sessionId != null && candidate.candidate != null) {
        signaling.sendIceCandidate(
          _sessionId!,
          candidate.candidate!,
          candidate.sdpMid ?? '0',
          candidate.sdpMLineIndex ?? 0,
        );
      }
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('WebRTC: ICE state: $state');
      _iceStateController.add(state);
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStreamController.add(event.streams[0]);
      }
    };
  }

  Future<void> _ensureLocalStream() async {
    if (_localStream != null) return;

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (final track in _localStream!.getTracks()) {
      await _peerConnection!.addTrack(track, _localStream!);
    }
  }

  /// Start a call as the initiator (operator)
  Future<void> startCall(String fromIp, String toIp) async {
    signaling.initiateCall(fromIp, toIp);

    // Wait for call_initiated response with session_id
    await signaling.messages
        .firstWhere((msg) =>
            msg['type'] == 'call_initiated' || msg['type'] == 'error')
        .timeout(const Duration(seconds: 10));

    if (_sessionId == null) {
      throw Exception('Failed to get session ID');
    }

    await _ensurePeerConnection();
    await _ensureLocalStream();

    final offer = await _peerConnection!.createOffer();
    final optimizedSdp =
        SdpUtils.applyOpusOptimizations(offer.sdp!, bitrate: 24000);
    final optimizedOffer = RTCSessionDescription(optimizedSdp, 'offer');

    await _peerConnection!.setLocalDescription(optimizedOffer);
    signaling.sendOffer(_sessionId!, optimizedSdp);
  }

  /// Toggle mute
  void toggleMute() {
    _isMuted = !_isMuted;
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !_isMuted;
    });
  }

  /// Enable video (operator requests, driver auto-accepts)
  Future<void> enableVideo() async {
    if (_isVideoEnabled || _peerConnection == null) return;

    try {
      _localVideoStream = await navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          'width': {'ideal': 480},
          'height': {'ideal': 640},
        },
      });

      for (final track in _localVideoStream!.getVideoTracks()) {
        await _peerConnection!.addTrack(track, _localVideoStream!);
      }

      _isVideoEnabled = true;
      _videoStateController.add(true);
      debugPrint('WebRTC: video enabled');

      // Renegotiate SDP
      if (_sessionId != null) {
        final offer = await _peerConnection!.createOffer();
        final sdp =
            SdpUtils.applyOpusOptimizations(offer.sdp!, bitrate: 24000);
        await _peerConnection!
            .setLocalDescription(RTCSessionDescription(sdp, 'offer'));
        signaling.sendOffer(_sessionId!, sdp);
      }
    } catch (e) {
      debugPrint('WebRTC: failed to enable video: $e');
    }
  }

  /// Disable video (return to audio-only)
  Future<void> disableVideo() async {
    if (!_isVideoEnabled) return;

    try {
      // Remove video tracks from PeerConnection
      final senders = await _peerConnection?.senders ?? [];
      for (final sender in senders) {
        if (sender.track?.kind == 'video') {
          await _peerConnection?.removeTrack(sender);
        }
      }

      // Stop local video
      _localVideoStream?.getVideoTracks().forEach((track) {
        track.stop();
      });
      await _localVideoStream?.dispose();
      _localVideoStream = null;

      _isVideoEnabled = false;
      _videoStateController.add(false);
      debugPrint('WebRTC: video disabled');

      // Renegotiate SDP
      if (_sessionId != null) {
        final offer = await _peerConnection!.createOffer();
        final sdp =
            SdpUtils.applyOpusOptimizations(offer.sdp!, bitrate: 24000);
        await _peerConnection!
            .setLocalDescription(RTCSessionDescription(sdp, 'offer'));
        signaling.sendOffer(_sessionId!, sdp);
      }
    } catch (e) {
      debugPrint('WebRTC: failed to disable video: $e');
    }
  }

  /// Handle video_request from peer (auto-accept for driver)
  Future<void> _handleVideoRequest(Map<String, dynamic> msg) async {
    final action = msg['action'] as String?;
    if (action == 'enable') {
      await enableVideo();
    } else if (action == 'disable') {
      await disableVideo();
    }
  }

  /// Request video toggle via signaling (operator sends to driver)
  void requestVideoToggle(bool enable) {
    if (_sessionId == null) return;
    signaling.send({
      'type': 'video_request',
      'session_id': _sessionId,
      'action': enable ? 'enable' : 'disable',
      'requested_by': 'operator',
    });
    // Operator also toggles own video
    if (enable) {
      enableVideo();
    } else {
      disableVideo();
    }
  }

  /// Hang up the call
  Future<void> hangUp({bool fromRemote = false}) async {
    if (!fromRemote && _sessionId != null) {
      signaling.endCall(_sessionId!);
    }

    await _localVideoStream?.dispose();
    _localVideoStream = null;
    _isVideoEnabled = false;

    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;

    _remoteStreamController.add(null);
    _videoStateController.add(false);
    _sessionId = null;
    signaling.sessionResumeId = null;
  }

  /// Get the PeerConnection (for quality monitoring etc.)
  RTCPeerConnection? get peerConnection => _peerConnection;

  /// Dispose all resources
  Future<void> dispose() async {
    await hangUp();
    _remoteStreamController.close();
    _iceStateController.close();
    _videoStateController.close();
  }
}
