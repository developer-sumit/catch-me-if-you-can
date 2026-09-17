import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';
import '../settings/settings_controller.dart';
import 'food_recognition_service.dart';
import 'recognition_history.dart';

class CameraScreen extends ConsumerStatefulWidget {
  /// [embedded] renders the pane inside the app shell's scaffold; the default
  /// adds its own toolbar for when the screen is pushed as a route.
  const CameraScreen({this.embedded = false, super.key});
  final bool embedded;

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _camera;
  FoodRecognitionService? _recognizer;
  Uint8List? _imageBytes;
  List<FoodRecognition> _results = const [];
  String? _error;
  bool _initializing = true;
  bool _processing = false;
  CameraPreference _mode = CameraPreference.capture;
  final _historyStore = RecognitionHistoryStore();
  List<RecognitionRecord> _history = const [];
  Timer? _realtimeTimer;
  String? _lastSignature;
  DateTime? _lastRecordedAt;

  bool get _isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _loadPreferencesAndHistory();
  }

  Future<void> _loadPreferencesAndHistory() async {
    final settings = await ref.read(settingsProvider.future);
    final history = await _historyStore.load();
    if (!mounted) return;
    setState(() {
      _mode = settings.cameraPreference;
      _history = history;
    });
    _syncRealtimeMode();
  }

  Future<void> _initialize() async {
    if (!_isSupported) {
      setState(() => _initializing = false);
      return;
    }
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera was found on this device.');
      }
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      _recognizer ??= FoodRecognitionService();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initializing = false;
      });
      _syncRealtimeMode();
    } on CameraException catch (error) {
      _setError(_cameraMessage(error));
    } catch (error) {
      _setError(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _error = message;
      _initializing = false;
      _processing = false;
    });
  }

  Future<void> _captureAndRecognize({bool realtime = false}) async {
    final camera = _camera;
    final recognizer = _recognizer;
    if (camera == null || recognizer == null || _processing) return;
    setState(() {
      _processing = true;
      _error = null;
      _results = const [];
    });
    try {
      final image = await camera.takePicture();
      final bytes = await image.readAsBytes();
      final results = await recognizer.recognize(image.path);
      await _recordResults(results, realtime: realtime);
      if (!mounted) return;
      setState(() {
        _imageBytes = realtime ? null : bytes;
        _results = results;
        _processing = false;
      });
    } catch (error) {
      _setError('Recognition failed. Hold the camera steady and try again.');
    }
  }

  void _retake() => setState(() {
        _imageBytes = null;
        _results = const [];
        _error = null;
      });

  void _setMode(CameraPreference mode) {
    setState(() {
      _mode = mode;
      _imageBytes = null;
      _error = null;
    });
    _syncRealtimeMode();
  }

  void _syncRealtimeMode() {
    _realtimeTimer?.cancel();
    _realtimeTimer = null;
    if (_mode != CameraPreference.realtime ||
        _camera == null ||
        !_camera!.value.isInitialized) {
      return;
    }
    _captureAndRecognize(realtime: true);
    _realtimeTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _captureAndRecognize(realtime: true),
    );
  }

  Future<void> _recordResults(
    List<FoodRecognition> results, {
    required bool realtime,
  }) async {
    if (results.isEmpty) return;
    final selected = [
      ...results.where((result) => result.isFood),
      ...results.where((result) => !result.isFood),
    ].take(5).toList();
    final signature = selected.map((result) => result.label).join('|');
    final now = DateTime.now();
    if (realtime &&
        signature == _lastSignature &&
        _lastRecordedAt != null &&
        now.difference(_lastRecordedAt!) < const Duration(seconds: 10)) {
      return;
    }
    _lastSignature = signature;
    _lastRecordedAt = now;
    final records = await _historyStore.add(
      RecognitionRecord(
        timestamp: now,
        mode: realtime ? 'realtime' : 'capture',
        results: selected,
      ),
    );
    if (mounted) setState(() => _history = records);
  }

  Future<void> _clearHistory() async {
    await _historyStore.clear();
    if (mounted) setState(() => _history = const []);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final camera = _camera;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _realtimeTimer?.cancel();
      camera.dispose();
      _camera = null;
    } else if (state == AppLifecycleState.resumed && _imageBytes == null) {
      setState(() => _initializing = true);
      _initialize();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeTimer?.cancel();
    _camera?.dispose();
    _recognizer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = MaxWidth(
      width: 900,
      child: Padding(
        padding: context.pagePadding.copyWith(
          bottom: widget.embedded && !context.isExpanded ? 16 : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.embedded) ...[
              Text('Recognize food', style: context.text.headlineMedium),
              const SizedBox(height: 4),
              Text(
                'Labels are computed on this device. Nothing is uploaded.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 20),
            ],
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognize food'),
        centerTitle: context.isCompact,
      ),
      body: AppBackground(child: SafeArea(child: content)),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (!_isSupported) return const _UnsupportedCamera();
    if (_initializing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 120,
              child: LinearProgressIndicator(minHeight: 3),
            ),
            const SizedBox(height: 16),
            Text('Starting the camera…', style: context.text.bodySmall),
          ],
        ),
      );
    }
    if (_camera == null || !_camera!.value.isInitialized) {
      return _CameraError(
          message: _error ?? 'The camera could not be started.');
    }

    final preview = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: _camera!.value.aspectRatio,
        child: _imageBytes == null
            ? CameraPreview(_camera!)
            : Image.memory(_imageBytes!, fit: BoxFit.cover),
      ),
    );
    final details = _RecognitionPanel(
      results: _results,
      processing: _processing,
      error: _error,
    );
    final history = _HistoryPanel(
      records: _history,
      onClear: _confirmClearHistory,
    );
    final detailColumn = Column(
      mainAxisSize: MainAxisSize.min,
      children: [details, const SizedBox(height: 16), history],
    );

    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<CameraPreference>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: CameraPreference.capture,
                icon: Icon(Icons.camera_rounded, size: 18),
                label: Text('Capture'),
              ),
              ButtonSegment(
                value: CameraPreference.realtime,
                icon: Icon(Icons.motion_photos_on_rounded, size: 18),
                label: Text('Real-time'),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (selection) => _setMode(selection.first),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: context.isExpanded
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 3, child: preview),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 2,
                      child: SingleChildScrollView(child: detailColumn),
                    ),
                  ],
                )
              : ListView(
                  children: [
                    preview,
                    const SizedBox(height: 16),
                    detailColumn,
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: context.isCompact ? double.infinity : 360,
          child: _mode == CameraPreference.realtime
              ? FilledButton.tonalIcon(
                  onPressed: null,
                  icon: _processing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.motion_photos_on),
                  label: Text(
                      _processing ? 'Analyzing frame…' : 'Real-time active'),
                )
              : _imageBytes == null
                  ? ElevatedButton.icon(
                      onPressed: _processing ? null : _captureAndRecognize,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(_processing
                          ? 'Recognizing…'
                          : 'Capture and recognize'),
                    )
                  : OutlinedButton.icon(
                      onPressed: _retake,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retake photo'),
                    ),
        ),
      ],
    );
  }

  Future<void> _confirmClearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear recognition history?'),
        content:
            const Text('This removes all locally stored recognition records.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _clearHistory();
  }

  String _cameraMessage(CameraException error) => switch (error.code) {
        'CameraAccessDenied' =>
          'Camera access was denied. Enable it in system settings and try again.',
        'CameraAccessDeniedWithoutPrompt' =>
          'Camera permission is disabled. Enable it in system settings.',
        _ =>
          'The camera could not be started (${error.description ?? error.code}).',
      };
}

class _RecognitionPanel extends StatelessWidget {
  const _RecognitionPanel({
    required this.results,
    required this.processing,
    this.error,
  });

  final List<FoodRecognition> results;
  final bool processing;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final foodResults = results.where((result) => result.isFood).toList();
    final shown =
        foodResults.isNotEmpty ? foodResults : results.take(5).toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('On-device results',
                    style: context.text.titleMedium),
              ),
              Icon(Icons.lock_outline_rounded,
                  size: 15, color: context.tokens.inkSoft),
              const SizedBox(width: 5),
              Text('Private', style: context.text.labelSmall),
            ],
          ),
          const SizedBox(height: 14),
          if (processing)
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: const LinearProgressIndicator(minHeight: 3),
            ),
          if (error != null)
            Row(
              children: [
                Icon(Icons.error_outline_rounded,
                    size: 17, color: context.colors.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    error!,
                    style: context.text.bodySmall
                        ?.copyWith(color: context.colors.error),
                  ),
                ),
              ],
            ),
          if (!processing && error == null && results.isEmpty)
            Text(
              'Point the camera at the food and capture a clear, well-lit '
              'photo to begin.',
              style: context.text.bodySmall,
            ),
          if (results.isNotEmpty && foodResults.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'No confident food label was found — showing general image '
                'labels instead.',
                style: context.text.bodySmall
                    ?.copyWith(color: context.tokens.caution),
              ),
            ),
          for (final result in shown)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                children: [
                  Icon(
                    result.isFood
                        ? Icons.restaurant_rounded
                        : Icons.label_outline_rounded,
                    size: 17,
                    color: result.isFood
                        ? context.colors.primary
                        : context.tokens.inkSoft,
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 108,
                    child: Text(
                      result.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.bodyMedium,
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: result.confidence.clamp(0, 1),
                        minHeight: 6,
                        backgroundColor: context.tokens.hairline,
                        color: result.isFood
                            ? context.colors.primary
                            : context.tokens.inkSoft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(result.confidence * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: context.text.labelSmall,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _HistoryPanel extends StatelessWidget {
  const _HistoryPanel({required this.records, required this.onClear});

  final List<RecognitionRecord> records;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Recognition history',
                      style: context.text.titleMedium),
                ),
                if (records.isNotEmpty)
                  TextButton(
                    onPressed: onClear,
                    child: const Text('Clear'),
                  ),
              ],
            ),
            if (records.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Items you recognize are listed here, on this device only.',
                  style: context.text.bodySmall,
                ),
              )
            else
              for (final record in records.take(20))
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        record.mode == 'realtime'
                            ? Icons.motion_photos_on_rounded
                            : Icons.camera_rounded,
                        size: 16,
                        color: context.tokens.inkSoft,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              record.results
                                  .map((result) => result.label)
                                  .join(', '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.bodyMedium,
                            ),
                            Text(
                              DateFormat.MMMd()
                                  .add_jm()
                                  .format(record.timestamp),
                              style: context.text.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            if (records.length > 20)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '${records.length - 20} older records are stored on this '
                  'device.',
                  style: context.text.bodySmall,
                ),
              ),
          ],
        ),
      );
}

class _UnsupportedCamera extends StatelessWidget {
  const _UnsupportedCamera();
  @override
  Widget build(BuildContext context) => const Center(
        child: AppEmptyState(
          icon: Icons.phone_iphone_rounded,
          title: 'Available on Android and iOS',
          message:
              'Offline food recognition needs a device camera. Run Soul Serve '
              'on a phone or a mobile emulator to use it.',
        ),
      );
}

class _CameraError extends StatelessWidget {
  const _CameraError({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
        child: AppEmptyState(
          icon: Icons.videocam_off_rounded,
          title: 'The camera is unavailable',
          message: message,
        ),
      );
}
