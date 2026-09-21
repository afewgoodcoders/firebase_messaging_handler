import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TokenDebugOverlay extends StatelessWidget {
  const TokenDebugOverlay({super.key, required this.token, this.onRefresh});

  final String? token;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'copy_token_fab',
            onPressed: token == null
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: token!));
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('FCM token copied')),
                    );
                  },
            icon: const Icon(Icons.copy),
            label: const Text('Copy token'),
          ),
          const SizedBox(height: 8),
          if (onRefresh != null)
            FloatingActionButton(
              heroTag: 'refresh_token_fab',
              mini: true,
              onPressed: onRefresh,
              child: const Icon(Icons.refresh),
            ),
        ],
      ),
    );
  }
}
