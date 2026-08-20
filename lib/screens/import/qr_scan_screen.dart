import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/password_item.dart';
import '../../services/import_merger.dart';
import '../../services/qr_payload_parser.dart';
import '../../services/password_repository.dart';
import '../../utils/import_validation.dart';
import '../../utils/theme_config.dart';

/// 二维码扫描导入页面。
///
/// 扫到内容后用 [QrPayloadParser] 解析，经 [ImportValidator] 过滤无效条目，
/// 再用 [ImportMerger] 做 newer-wins 合并，最后把结果描述字符串 pop 回上一页。
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  late final MobileScannerController _controller;
  final QrPayloadParser _parser = const QrPayloadParser();
  bool _processing = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final String? raw = barcodes.first.rawValue;
    if (raw == null || raw.isEmpty) return;

    setState(() => _processing = true);
    await _controller.stop();

    final QrParseResult result = _parser.parse(raw);
    String message;
    if (result is QrItemsResult) {
      message = await _mergeAndSummarize(result.items);
    } else if (result is QrUnrecognizedResult) {
      message = result.reason;
    } else {
      message = '无法识别的二维码内容';
    }

    if (!mounted) return;
    Navigator.of(context).pop(message);
  }

  Future<String> _mergeAndSummarize(List<PasswordItem> items) async {
    final (:valid, :invalid) = const ImportValidator().filter(items);
    if (valid.isEmpty) {
      return '二维码内无有效条目（无效 $invalid 条）';
    }
    final ImportSummary summary =
        await ImportMerger(widget.repository).merge(valid);
    // 合并器不知道 invalid，补回去展示。
    final ImportSummary full = ImportSummary(
      added: summary.added,
      updated: summary.updated,
      skipped: summary.skipped,
      invalid: invalid,
    );
    return '导入完成：$full';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描二维码'),
        backgroundColor: Colors.black,
        actions: <Widget>[
          IconButton(
            tooltip: _torchOn ? '关闭手电筒' : '开启手电筒',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () {
              _controller.toggleTorch();
              setState(() => _torchOn = !_torchOn);
            },
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          // 取景框装饰。
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(
                  color: ThemeConfig.primaryColor.withValues(alpha: 0.8),
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
              ),
            ),
          ),
          if (_processing)
            Container(
              color: Colors.black54,
              alignment: Alignment.center,
              child: const CircularProgressIndicator(
                color: ThemeConfig.primaryColor,
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Center(
              child: Text(
                _processing ? '正在处理…' : '将二维码对准取景框',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: ThemeConfig.fontSizeCaption,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
