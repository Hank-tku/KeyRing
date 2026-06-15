import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class TestDialogScreen extends StatefulWidget {
  const TestDialogScreen({super.key});

  @override
  State<TestDialogScreen> createState() => _TestDialogScreenState();
}

class _TestDialogScreenState extends State<TestDialogScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Test Dialog')),
      body: Center(
        child: ElevatedButton(
          onPressed: _showTestDialog,
          child: const Text('Show Test Dialog'),
        ),
      ),
    );
  }

  Future<void> _showTestDialog() async {
    if (kDebugMode) {
      debugPrint('📱 Showing test dialog');
    }

    // Add a delay to ensure UI is ready
    await Future.delayed(const Duration(milliseconds: 500));

    if (kDebugMode) {
      debugPrint('📱 Context mounted: $mounted');
    }

    // Use post-frame callback to ensure we show the dialog at the right time
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (kDebugMode) {
          debugPrint('📱 In post-frame callback, showing test dialog');
          debugPrint('📱 Context in post-frame callback: $context');
          debugPrint('📱 Context mounted in post-frame callback: $mounted');
        }

        final String? result = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true, // Force use of root navigator
          builder: (BuildContext context) {
            if (kDebugMode) {
              debugPrint(
                '📱 Building AlertDialog for test dialog in post-frame callback',
              );
              debugPrint('📱 Builder context: $context');
            }
            return AlertDialog(
              title: const Text('Test Dialog'),
              content: const Text(
                'This is a test dialog to verify dialog functionality',
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop('OK');
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );

        if (kDebugMode) {
          debugPrint('📱 Test dialog closed with result: $result');
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          debugPrint('📱 Error showing test dialog in post-frame callback');
          debugPrint('📱 Error: $e');
          debugPrint('📱 Stack trace: $stackTrace');
        }
      }
    });
  }
}
