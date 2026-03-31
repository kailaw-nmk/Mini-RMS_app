import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/call/providers/call_provider.dart';
import '../features/call/models/call_state.dart' as app;
import '../features/call/widgets/call_status_bar.dart';
import '../features/call/widgets/quality_indicator.dart';
import '../features/call/widgets/emergency_end_button.dart';
import '../features/metrics/media_metrics.dart';
import '../services/foreground_service.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key});

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen> {
  final _serverUrlController =
      TextEditingController(text: 'ws://100.64.0.50:8080');
  final _peerIpController = TextEditingController();
  final _deviceIdController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _isOperator = true;

  @override
  void initState() {
    super.initState();
    _checkBatteryOptimization();
  }

  Future<void> _checkBatteryOptimization() async {
    if (!Platform.isAndroid) return;
    final excluded = await ForegroundServiceManager.isBatteryOptimizationExcluded();
    if (!excluded && mounted) {
      _showBatteryOptimizationDialog();
    }
  }

  void _showBatteryOptimizationDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('バッテリー最適化の除外'),
        content: const Text(
          'TailCallが通話をバックグラウンドで維持するには、'
          'バッテリー最適化の除外設定が必要です。\n\n'
          '設定しない場合、画面OFF時に通話が切断される可能性があります。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('後で'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ForegroundServiceManager.requestBatteryOptimizationExclusion();
            },
            child: const Text('設定する'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _serverUrlController.dispose();
    _peerIpController.dispose();
    _deviceIdController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    final notifier = ref.read(callProvider.notifier);
    await notifier.connect(
      serverUrl: _serverUrlController.text,
      deviceToken: _tokenController.text,
      deviceId: _deviceIdController.text,
    );
  }

  Future<void> _startCall() async {
    final notifier = ref.read(callProvider.notifier);
    await notifier.startCall('0.0.0.0', _peerIpController.text);
  }

  @override
  Widget build(BuildContext context) {
    final callState = ref.watch(callProvider);
    final notifier = ref.read(callProvider.notifier);
    final session = callState.session;

    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      appBar: AppBar(
        title: const Text('TailCall'),
        backgroundColor: const Color(0xFF16213E),
        foregroundColor: Colors.white,
      ),
      body: session != null ? _buildCallView(callState, notifier) : _buildSetupView(callState),
    );
  }

  Widget _buildSetupView(CallState callState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'TailCall Setup',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 24),

          _buildTextField('サーバーURL', _serverUrlController, Icons.dns),
          const SizedBox(height: 12),
          _buildTextField('デバイスID', _deviceIdController, Icons.phone_android),
          const SizedBox(height: 12),
          _buildTextField('JWTトークン', _tokenController, Icons.key),
          const SizedBox(height: 12),
          _buildTextField('相手のIP', _peerIpController, Icons.person),
          const SizedBox(height: 12),

          SwitchListTile(
            title: const Text('管制オペレーター', style: TextStyle(color: Colors.white)),
            subtitle: Text(
              _isOperator ? '通話を開始できます' : 'ドライバーモード（着信のみ）',
              style: const TextStyle(color: Colors.white70),
            ),
            value: _isOperator,
            onChanged: (v) => setState(() => _isOperator = v),
            activeColor: const Color(0xFF4CAF50),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _connect,
            icon: const Icon(Icons.wifi),
            label: const Text('サーバーに接続'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F3460),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 12),

          if (_isOperator)
            ElevatedButton.icon(
              onPressed: callState.isConnecting ? null : _startCall,
              icon: const Icon(Icons.call),
              label: Text(callState.isConnecting ? '接続中...' : '通話を開始'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4CAF50),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

          if (callState.error != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                callState.error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField(
      String label, TextEditingController controller, IconData icon) {
    return TextField(
      controller: controller,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.white54),
        filled: true,
        fillColor: const Color(0xFF16213E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildCallView(CallState callState, CallNotifier notifier) {
    final session = callState.session!;
    final duration = notifier.callDuration;

    return Column(
      children: [
        CallStatusBar(
          connectionState: session.connectionState,
          callDuration: duration,
        ),
        if (session.connectionState == app.ConnectionState.connected)
          const QualityIndicator(metrics: MediaMetrics()),

        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  session.connectionState == app.ConnectionState.connected
                      ? Icons.person
                      : session.connectionState == app.ConnectionState.suspended
                          ? Icons.bedtime
                          : Icons.signal_cellular_connected_no_internet_0_bar,
                  size: 80,
                  color: Colors.white54,
                ),
                const SizedBox(height: 16),
                Text(
                  _getStatusMessage(session.connectionState),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  session.peerIp,
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white38,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Controls: different for operator vs driver
        Padding(
          padding: const EdgeInsets.all(32),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Mute button (both roles)
              _buildControlButton(
                icon: callState.isMuted ? Icons.mic_off : Icons.mic,
                label: callState.isMuted ? 'ミュート中' : 'ミュート',
                color: callState.isMuted ? Colors.red : Colors.white54,
                onTap: notifier.toggleMute,
              ),

              // Video toggle (operator only)
              if (_isOperator)
                _buildControlButton(
                  icon: callState.isVideoEnabled
                      ? Icons.videocam
                      : Icons.videocam_off,
                  label: callState.isVideoEnabled ? 'ビデオON' : 'ビデオ',
                  color: callState.isVideoEnabled
                      ? const Color(0xFF2196F3)
                      : Colors.white54,
                  onTap: notifier.toggleVideo,
                ),

              // End call: operator = normal button, driver = 3s long press
              if (_isOperator)
                _buildControlButton(
                  icon: Icons.call_end,
                  label: '終了',
                  color: Colors.red,
                  onTap: notifier.endCall,
                  large: true,
                )
              else
                EmergencyEndButton(onConfirmedEnd: notifier.endCall),
            ],
          ),
        ),
      ],
    );
  }

  String _getStatusMessage(app.ConnectionState state) {
    switch (state) {
      case app.ConnectionState.connected:
        return '管制と接続中';
      case app.ConnectionState.reconnectingNetwork:
        return '電波を探しています...\n電波が届き次第\n自動的につながります';
      case app.ConnectionState.reconnectingPeer:
        return '相手の接続を\n待っています...';
      case app.ConnectionState.suspended:
        return '接続待機中\n復帰次第自動で\nつながります';
      case app.ConnectionState.disconnected:
        return '切断されました';
    }
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool large = false,
  }) {
    final size = large ? 72.0 : 56.0;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.2),
              border: Border.all(color: color, width: 2),
            ),
            child: Icon(icon, color: color, size: size * 0.45),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: color, fontSize: 12)),
      ],
    );
  }
}
