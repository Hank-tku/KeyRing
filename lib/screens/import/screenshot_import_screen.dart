import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../models/password_item.dart';
import '../../services/import_merger.dart';
import '../../services/ocr_field_extractor.dart';
import '../../services/password_repository.dart';
import '../../utils/theme_config.dart';
import '../../widgets/shared/form_field_row.dart';

/// 截图 OCR 导入页面。
///
/// 流程：选择图片 → ML Kit 识别 → 启发式抽取字段 → 可编辑确认表单 → 合并导入。
/// 由于 OCR 准确率有限，必须让用户在确认表单复核后再写入。
class ScreenshotImportScreen extends StatefulWidget {
  const ScreenshotImportScreen({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<ScreenshotImportScreen> createState() => _ScreenshotImportScreenState();
}

class _ScreenshotImportScreenState extends State<ScreenshotImportScreen> {
  static const OcrFieldExtractor _extractor = OcrFieldExtractor();

  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _usernameCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _loading = false;
  bool _hasResult = false;
  double _confidence = 0;
  String? _errorMsg;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _urlCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickAndRecognize() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });

    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: false,
      );
      if (picked == null || picked.files.single.path == null) {
        setState(() => _loading = false);
        return;
      }

      final String path = picked.files.single.path!;
      final InputImage inputImage = InputImage.fromFilePath(path);

      // 简单使用 Latin 识别器（脚本识别更准但配置复杂，后续可按需升级）。
      final TextRecognizer recognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognized =
          await recognizer.processImage(inputImage);
      await recognizer.close();

      final OcrExtraction ext = _extractor.extract(recognized.text);

      _titleCtrl.text = ext.title;
      _usernameCtrl.text = ext.username;
      _passwordCtrl.text = ext.password;
      _urlCtrl.text = ext.url ?? '';
      _notesCtrl.text = ext.notes ?? '';

      setState(() {
        _hasResult = true;
        _confidence = ext.confidence;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _errorMsg = '识别失败：$e';
      });
    }
  }

  Future<void> _confirmImport() async {
    final PasswordItem item = PasswordItem(
      title: _titleCtrl.text.trim(),
      username: _usernameCtrl.text.trim(),
      password: _passwordCtrl.text.trim(),
      url: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    );

    if (item.title.isEmpty && item.password.isEmpty) {
      setState(() => _errorMsg = '标题和密码至少填写一个');
      return;
    }

    final ImportSummary summary =
        await ImportMerger(widget.repository).merge(<PasswordItem>[item]);

    if (!mounted) return;
    Navigator.of(context).pop('截图导入：$summary');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('从截图识别')),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: ThemeConfig.primaryColor),
            )
          : _hasResult
              ? _buildConfirmForm()
              : _buildPicker(),
    );
  }

  Widget _buildPicker() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(ThemeConfig.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.image_search_outlined,
              size: 64,
              color: ThemeConfig.secondaryTextColor,
            ),
            const SizedBox(height: ThemeConfig.space16),
            const Text(
              '选择一张含账号密码的截图\n系统会尝试识别其中的字段',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ThemeConfig.secondaryTextColor,
                fontSize: ThemeConfig.fontSizeBody,
                height: 1.6,
              ),
            ),
            const SizedBox(height: ThemeConfig.space20),
            FilledButton.icon(
              onPressed: _pickAndRecognize,
              icon: const Icon(Icons.photo_outlined),
              label: const Text('选择图片'),
            ),
            if (_errorMsg != null) ...<Widget>[
              const SizedBox(height: ThemeConfig.space12),
              Text(
                _errorMsg!,
                style: const TextStyle(
                  color: ThemeConfig.dangerColor,
                  fontSize: ThemeConfig.fontSizeCaption,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmForm() {
    return ListView(
      padding: const EdgeInsets.all(ThemeConfig.space16),
      children: <Widget>[
        // 置信度提示。
        Container(
          padding: const EdgeInsets.all(ThemeConfig.space12),
          decoration: BoxDecoration(
            color: ThemeConfig.warningColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
            border: Border.all(
              color: ThemeConfig.warningColor.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: <Widget>[
              const Icon(
                Icons.warning_amber_rounded,
                color: ThemeConfig.warningColor,
                size: 20,
              ),
              const SizedBox(width: ThemeConfig.space8),
              Expanded(
                child: Text(
                  _confidence > 0.6
                      ? '已识别主要字段，请复核后导入'
                      : '识别结果不确定，请仔细核对字段',
                  style: const TextStyle(
                    color: ThemeConfig.warningColor,
                    fontSize: ThemeConfig.fontSizeCaption,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: ThemeConfig.space16),
        FormFieldRow(
          label: '标题',
          child: TextField(
            controller: _titleCtrl,
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: const InputDecoration(hintText: '账号名称'),
          ),
        ),
        FormFieldRow(
          label: '用户名',
          child: TextField(
            controller: _usernameCtrl,
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: const InputDecoration(hintText: '账号 / 邮箱'),
          ),
        ),
        FormFieldRow(
          label: '密码',
          child: TextField(
            controller: _passwordCtrl,
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: const InputDecoration(hintText: '密码'),
          ),
        ),
        FormFieldRow(
          label: '网址',
          child: TextField(
            controller: _urlCtrl,
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: const InputDecoration(hintText: 'https://'),
          ),
        ),
        FormFieldRow(
          label: '备注',
          alignWithField: true,
          child: TextField(
            controller: _notesCtrl,
            style: const TextStyle(color: ThemeConfig.textColor),
            maxLines: 4,
            decoration: const InputDecoration(hintText: '其它信息'),
          ),
        ),
        const SizedBox(height: ThemeConfig.space16),
        Row(
          children: <Widget>[
            OutlinedButton(
              onPressed: _pickAndRecognize,
              child: const Text('重新选图'),
            ),
            const SizedBox(width: ThemeConfig.space12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _confirmImport,
                icon: const Icon(Icons.download_done_outlined, size: 18),
                label: const Text('确认导入'),
              ),
            ),
          ],
        ),
        if (_errorMsg != null) ...<Widget>[
          const SizedBox(height: ThemeConfig.space12),
          Text(
            _errorMsg!,
            style: const TextStyle(
              color: ThemeConfig.dangerColor,
              fontSize: ThemeConfig.fontSizeCaption,
            ),
          ),
        ],
      ],
    );
  }
}
