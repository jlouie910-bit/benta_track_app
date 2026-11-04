import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:camera/camera.dart' as cam;

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  // Barcode Controller
  late final MobileScannerController _barcodeController;

  // Native In-App Camera Controller for AI Vision
  cam.CameraController? _aiCameraController;
  List<cam.CameraDescription>? _cameras;

  GenerativeModel? _visionModel;

  bool _isAiMode = true; // Default mode is AI Name Scanning
  bool _hasDetected = false;
  bool _isProcessingAi = false;
  bool _isCameraInitialized = false;

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize Google Generative AI (Gemini) Model
    _visionModel = GenerativeModel(
      model: 'gemini-1.5-flash',
      apiKey: 'AIzaSyAiyWvCp3DEzhX_E2yA_L37f2-jbTQDB9A', // Replace with your actual Gemini API key if needed
    );

    _barcodeController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: false,
    );

    _initializeAiCamera();
  }

  Future<void> _initializeAiCamera() async {
    try {
      _cameras = await cam.availableCameras();
      if (_cameras != null && _cameras!.isNotEmpty) {
        // Select back camera
        final backCamera = _cameras!.firstWhere(
          (element) => element.lensDirection == cam.CameraLensDirection.back,
          orElse: () => _cameras!.first,
        );

        _aiCameraController = cam.CameraController(
          backCamera,
          cam.ResolutionPreset.medium,
          enableAudio: false,
        );

        await _aiCameraController!.initialize();
        if (mounted) {
          setState(() {
            _isCameraInitialized = true;
          });
        }
      }
    } catch (e) {
      debugPrint("Error initializing native camera: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isAiMode) {
      if (_aiCameraController == null || !_aiCameraController!.value.isInitialized) {
        return;
      }
      if (state == AppLifecycleState.paused) {
        _aiCameraController?.dispose();
      } else if (state == AppLifecycleState.resumed) {
        _initializeAiCamera();
      }
    } else {
      if (_barcodeController.value.isInitialized) {
        if (state == AppLifecycleState.paused) {
          _barcodeController.stop();
        } else if (state == AppLifecycleState.resumed) {
          _barcodeController.start();
        }
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeController.dispose();
    _aiCameraController?.dispose();
    super.dispose();
  }

  // Captures photo from the live in-app camera feed and analyzes with Gemini AI
  Future<void> _captureAndAnalyzeWithGemini() async {
    if (_isProcessingAi || _hasDetected || _visionModel == null) return;
    if (_aiCameraController == null || !_aiCameraController!.value.isInitialized) return;

    setState(() => _isProcessingAi = true);

    try {
      // Snap picture directly from the live in-app camera preview
      final cam.XFile rawImage = await _aiCameraController!.takePicture();
      final Uint8List imageBytes = await rawImage.readAsBytes();

      const promptText = '''
        Analyze this retail product image carefully.
        Return ONLY the exact item name string as it appears in a store catalog (e.g., "Marlboro Red", "Coca Cola", "Century Tuna"). Keep it clear and concise.
        If no retail product is identified clearly, return "UNKNOWN".
      ''';

      final prompt = TextPart(promptText);
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await _visionModel!.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      final String detectedName = response.text?.trim() ?? 'UNKNOWN';

      if (detectedName != 'UNKNOWN' && detectedName.isNotEmpty && mounted) {
        _hasDetected = true;
        Navigator.pop(context, detectedName);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Could not identify product. Try again.")),
        );
      }
    } catch (e) {
      debugPrint("Error running Generative AI Vision: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("AI Analysis Error: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          _isAiMode ? "AI Vision Assistant" : "Barcode Scanner",
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Toggle between AI Name Scan and Barcode Scan
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isAiMode = !_isAiMode;
                if (_isAiMode) {
                  _barcodeController.stop();
                } else {
                  _barcodeController.start();
                }
              });
            },
            icon: Icon(_isAiMode ? Icons.qr_code_scanner : Icons.auto_awesome, color: tealAccent),
            label: Text(
              _isAiMode ? "Use Barcode" : "Use AI Vision",
              style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // View 1: Barcode Scanner View
          if (!_isAiMode)
            MobileScanner(
              controller: _barcodeController,
              onDetect: (capture) {
                if (_hasDetected || _isProcessingAi) return;

                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;
                  if (code != null && code.isNotEmpty) {
                    _hasDetected = true;
                    _barcodeController.stop();
                    Navigator.pop(context, code);
                    return;
                  }
                }
              },
            )
          // View 2: Live In-App Camera Feed for AI Vision
          else if (_isCameraInitialized && _aiCameraController != null)
            SizedBox.expand(
              child: cam.CameraPreview(_aiCameraController!),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.tealAccent),
            ),

          // Targeting Viewfinder Box Overlay
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: tealAccent.withOpacity(0.8), width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),

          // Bottom Controls & Capture Button (Only active in AI Mode)
          if (_isAiMode)
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton.extended(
                    onPressed: _isProcessingAi ? null : _captureAndAnalyzeWithGemini,
                    backgroundColor: tealAccent,
                    foregroundColor: Colors.black,
                    elevation: 4,
                    icon: _isProcessingAi
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt_rounded),
                    label: Text(
                      _isProcessingAi ? "Analyzing with AI..." : "Capture & Identify Item",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      "Center the item in the box and tap capture. Switch to Barcode mode top-right if needed.",
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
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