import 'package:flutter/material.dart';

/// Emergency call end button requiring 3-second long press + confirmation dialog
class EmergencyEndButton extends StatefulWidget {
  final VoidCallback onConfirmedEnd;

  const EmergencyEndButton({super.key, required this.onConfirmedEnd});

  @override
  State<EmergencyEndButton> createState() => _EmergencyEndButtonState();
}

class _EmergencyEndButtonState extends State<EmergencyEndButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  bool _isHolding = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _showConfirmDialog();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails _) {
    setState(() => _isHolding = true);
    _controller.forward(from: 0);
  }

  void _onLongPressEnd(LongPressEndDetails _) {
    setState(() => _isHolding = false);
    if (_controller.status != AnimationStatus.completed) {
      _controller.reset();
    }
  }

  void _showConfirmDialog() {
    _controller.reset();
    setState(() => _isHolding = false);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text('通話を終了しますか？', style: TextStyle(color: Colors.white)),
        content: const Text(
          'この操作で通話が切断されます。',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onConfirmedEnd();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('終了する'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onLongPressStart: _onLongPressStart,
          onLongPressEnd: _onLongPressEnd,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return SizedBox(
                width: 72,
                height: 72,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Progress ring
                    CircularProgressIndicator(
                      value: _controller.value,
                      strokeWidth: 3,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.red),
                      backgroundColor: Colors.red.withValues(alpha: 0.2),
                    ),
                    // Button
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _isHolding
                            ? Colors.red.withValues(alpha: 0.5)
                            : Colors.red.withValues(alpha: 0.2),
                        border: Border.all(color: Colors.red, width: 2),
                      ),
                      child: const Icon(Icons.call_end, color: Colors.red, size: 28),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isHolding ? '長押し中...' : '終了（3秒長押し）',
          style: TextStyle(
            color: _isHolding ? Colors.red : Colors.red.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
