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
      print('📱 Showing test dialog');
    }

    // Add a delay to ensure UI is ready
    await Future.delayed(const Duration(milliseconds: 500));

    if (kDebugMode) {
      print('📱 About to show dialog, context valid: ${context != null}');
      print('📱 Context mounted: $mounted');
    }

    // Use post-frame callback to ensure we show the dialog at the right time
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (kDebugMode) {
          print('📱 In post-frame callback, showing test dialog');
          print('📱 Context in post-frame callback: $context');
          print('📱 Context mounted in post-frame callback: $mounted');
        }

        final String? result = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          useRootNavigator: true, // Force use of root navigator
          builder: (BuildContext context) {
            if (kDebugMode) {
              print(
                '📱 Building AlertDialog for test dialog in post-frame callback',
              );
              print('📱 Builder context: $context');
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
          print('📱 Test dialog closed with result: $result');
        }
      } catch (e, stackTrace) {
        if (kDebugMode) {
          print('📱 Error showing test dialog in post-frame callback');
          print('📱 Error: $e');
          print('📱 Stack trace: $stackTrace');
        }
      }
    });
  }
}
