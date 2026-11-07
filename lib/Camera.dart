import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:camera/camera.dart' as cam;
import 'ai_service.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class CameraScreen extends StatefulWidget {
  /// Names of the store's own items (with aliases). The AI picks from these first.
  final List<String> knownItems;
  const CameraScreen({super.key, this.knownItems = const []});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  // ── Mode ──────────────────────────────────────────────────────
  bool _isAiMode = false;

  // ── Closing guard ─────────────────────────────────────────────
  bool _closing = false;

  /// The ONLY place that closes this screen. Ignores any second call.
  void _finish([Object? result]) {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context).pop(result);
  }

  // ── Barcode mode ──────────────────────────────────────────────
  MobileScannerController? _barcodeController;
  bool _barcodeScanned = false;

  // ── AI mode ───────────────────────────────────────────────────
  cam.CameraController? _aiCameraController;
  bool _aiCameraReady = false;
  bool _isCapturing = false;
  bool _isAnalyzing = false;
  String? _aiError;

  // ── Lifecycle ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBarcodeMode();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeController?.dispose();
    _aiCameraController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _barcodeController?.stop();
    } else if (state == AppLifecycleState.resumed && !_isAiMode && !_closing) {
      _barcodeController?.start();
    }
  }

  // ── Barcode mode ──────────────────────────────────────────────
  void _startBarcodeMode() {
        _barcodeController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
    _barcodeScanned = false;
  }

  Future<void> _stopBarcodeMode() async {
    await _barcodeController?.stop();
    _barcodeController?.dispose();
    _barcodeController = null;
  }

  // ── AI mode ───────────────────────────────────────────────────
  Future<void> _startAiMode() async {
    setState(() {
      _aiCameraReady = false;
      _aiError = null;
    });
    try {
      final cameras = await cam.availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _aiError = 'Walang available na camera.');
        return;
      }
      final backCamera = cameras.firstWhere(
        (c) => c.lensDirection == cam.CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _aiCameraController = cam.CameraController(
        backCamera,
        cam.ResolutionPreset.medium, // smaller upload, faster answer
        enableAudio: false,
      );
      await _aiCameraController!.initialize();
      if (mounted) setState(() => _aiCameraReady = true);
    } catch (e) {
      if (mounted) setState(() => _aiError = 'Hindi mabuksan ang camera: $e');
    }
  }

  Future<void> _stopAiMode() async {
    await _aiCameraController?.dispose();
    _aiCameraController = null;
    if (mounted) setState(() => _aiCameraReady = false);
  }

  // ── Toggle ────────────────────────────────────────────────────
  Future<void> _toggleMode() async {
    if (_closing) return;
    if (_isAiMode) {
      await _stopAiMode();
      _startBarcodeMode();
      if (mounted) setState(() => _isAiMode = false);
    } else {
      await _stopBarcodeMode();
      if (mounted) setState(() => _isAiMode = true);
      await _startAiMode();
    }
  }

  // ── Barcode detect ────────────────────────────────────────────
  void _onBarcodeDetect(BarcodeCapture capture) {
    if (_barcodeScanned || _closing) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _barcodeScanned = true;
    _barcodeController?.stop();
    _finish({'source': 'barcode', 'barcode': value});
  }

  // ── AI capture + analyze ──────────────────────────────────────
  Future<void> _captureAndAnalyze() async {
    final ctrl = _aiCameraController;
    if (ctrl == null ||
        !ctrl.value.isInitialized ||
        _isCapturing ||
        _isAnalyzing ||
        _closing) {
      return;
    }

    setState(() {
      _isCapturing = true;
      _aiError = null;
    });

    try {
      final xFile = await ctrl.takePicture();
      final imageFile = File(xFile.path);

      if (!mounted) return;
      setState(() {
        _isCapturing = false;
        _isAnalyzing = true;
      });

      final result = await AIService.detectItemFromImage(
        imageFile,
        knownItems: widget.knownItems,
      );
      debugPrint('AI RESULT: $result');

      if (!mounted || _closing) return;

      if (result == null) {
        setState(() {
          _aiError = 'Walang sagot ang AI. Subukan ulit.';
          _isAnalyzing = false;
        });
        return;
      }

      if (result['error'] != null) {
        setState(() {
          _aiError = AIService.friendlyError('Error:${result['error']}');
          _isAnalyzing = false;
        });
        return;
      }

      final itemName = (result['itemName'] as String? ?? '').trim();
      if (itemName.isEmpty) {
        setState(() {
          _aiError = 'Hindi nakilala ang produkto. Subukan ulit.';
          _isAnalyzing = false;
        });
        return;
      }

      final confidence = (result['confidence'] as num?)?.toDouble() ?? 0.0;
      final matched = result['matchedExisting'] == true;

      // Sure AND already in the store's list → no extra tap needed.
      final sure = matched && confidence >= 0.85;
      if (!sure) {
        final ok = await _confirmDetection(itemName, confidence, matched);
        if (!mounted || _closing) return;
        if (ok != true) {
          setState(() => _isAnalyzing = false); // retake
          return;
        }
      }

      final Map<String, dynamic> out = {
        'source': 'ai',
        'itemName': itemName,
        'category': result['category'],
        'estimatedPrice': result['estimatedPrice'],
        'matchedExisting': matched,
        'confidence': confidence,
        'imagePath': xFile.path,
      };
      _finish(out);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCapturing = false;
          _isAnalyzing = false;
          _aiError = 'May error: $e';
        });
      }
    }
  }

  Future<bool?> _confirmDetection(
      String name, double confidence, bool matched) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: const Color(0xFF1E3A5F),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              matched ? 'Found in your inventory' : 'New product detected',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Confidence: ${(confidence * 100).round()}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white),
                    child: const Text('Retake'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Use this'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          _isAiMode ? _buildAiPreview() : _buildBarcodePreview(),

          // Scan frame overlay drawn on top
          const _ScanFrameOverlay(),

          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Colors.white),
                      onPressed: () => _finish(),
                    ),
                    Expanded(
                      child: Text(
                        _isAiMode ? 'AI Vision Scanner' : 'Barcode Scanner',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (!_isAiMode)
                      IconButton(
                        icon: const Icon(Icons.flashlight_on_rounded,
                            color: Colors.white),
                        onPressed: () => _barcodeController?.toggleTorch(),
                      )
                    else
                      const SizedBox(width: 48),
                  ],
                ),
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.85),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_aiError != null) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _aiError!,
                          style: const TextStyle(color: Colors.white),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _BottomButton(
                          icon: _isAiMode
                              ? Icons.qr_code_scanner_rounded
                              : Icons.auto_awesome_rounded,
                          label: _isAiMode ? 'Barcode' : 'AI Vision',
                          onTap: _toggleMode,
                        ),
                        if (_isAiMode)
                          GestureDetector(
                            onTap: (_isCapturing || _isAnalyzing)
                                ? null
                                : _captureAndAnalyze,
                            child: Container(
                              width: 68,
                              height: 68,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 3),
                                color: (_isCapturing || _isAnalyzing)
                                    ? Colors.white.withValues(alpha: 0.15)
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                              child: (_isCapturing || _isAnalyzing)
                                  ? const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Icons.camera_alt_rounded,
                                      color: Colors.white, size: 32),
                            ),
                          )
                        else
                          const SizedBox(width: 68),
                        const SizedBox(width: 68),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isAiMode
                          ? (_isAnalyzing
                              ? 'Kinukuha ang impormasyon ng produkto...'
                              : 'I-point sa produkto at pindutin ang shutter')
                          : 'I-scan ang barcode ng produkto',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcodePreview() {
    final ctrl = _barcodeController;
    if (ctrl == null) return const SizedBox.shrink();
    return MobileScanner(
      controller: ctrl,
      onDetect: _onBarcodeDetect,
    );
  }

  Widget _buildAiPreview() {
    if (!_aiCameraReady || _aiCameraController == null) {
      return Center(
        child: _aiError != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_aiError!,
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center),
              )
            : const CircularProgressIndicator(color: Colors.white),
      );
    }
    return cam.CameraPreview(_aiCameraController!);
  }
}

// ── Scan frame drawn via Stack ────────────────────────────────
class _ScanFrameOverlay extends StatelessWidget {
  const _ScanFrameOverlay();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 260,
        height: 260,
        decoration: BoxDecoration(
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Stack(
          children: [
            _Corner(top: -1, left: -1, color: Colors.white),
            _Corner(top: -1, right: -1, color: Colors.white, flipH: true),
            _Corner(bottom: -1, left: -1, color: Colors.white, flipV: true),
            _Corner(
                bottom: -1,
                right: -1,
                color: Colors.white,
                flipH: true,
                flipV: true),
          ],
        ),
      ),
    );
  }
}

class _Corner extends StatelessWidget {
  final double? top, bottom, left, right;
  final Color color;
  final bool flipH, flipV;

  const _Corner({
    this.top,
    this.bottom,
    this.left,
    this.right,
    required this.color,
    this.flipH = false,
    this.flipV = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.scale(
        scaleX: flipH ? -1 : 1,
        scaleY: flipV ? -1 : 1,
        child: CustomPaint(
          size: const Size(24, 24),
          painter: _CornerPainter(color),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final Color color;
  const _CornerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset.zero, Offset(0, size.height), paint);
    canvas.drawLine(Offset.zero, Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

// ── Bottom icon button ────────────────────────────────────────
class _BottomButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}