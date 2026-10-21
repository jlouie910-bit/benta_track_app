import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:image_picker/image_picker.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  late final MobileScannerController _scannerController;
  GenerativeModel? _visionModel;

  bool _isAiMode = true; // Default mode is AI Name Scanning
  bool _hasDetected = false;
  bool _isProcessingAi = false;

  final Color navyBlue = const Color(0xFF1E3A5F);
  final Color tealAccent = const Color(0xFF4FD1C5);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize Google Generative AI (Gemini) Model
    _visionModel = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: 'AIzaSyAiyWvCp3DEzhX_E2yA_L37f2-jbTQDB9A', // Replace with your actual Gemini API key
    );

    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.unrestricted,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: false, // Don't auto-start barcode stream when default is AI mode
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
      ],
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_isAiMode && _scannerController.value.isInitialized) {
      if (state == AppLifecycleState.paused) {
        _scannerController.stop();
      } else if (state == AppLifecycleState.resumed) {
        _scannerController.start();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  // Captures photo and analyzes item name using Gemini AI
  Future<void> _captureAndAnalyzeWithGemini() async {
    if (_isProcessingAi || _hasDetected || _visionModel == null) return;

    setState(() => _isProcessingAi = true);

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (imageFile != null) {
        final Uint8List imageBytes = await imageFile.readAsBytes();

        final prompt = TextPart('''
          Analyze this retail product image carefully.
          Return ONLY the exact item name string as it appears in a store catalog (e.g., "Marlboro Red", "Coca Cola", "Century Tuna"). Keep it clear and concise.
          If no retail product is identified clearly, return "UNKNOWN".
        ''');

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
      }
    } catch (e) {
      debugPrint("Error running Generative AI Vision: $e");
    } finally {
      if (mounted) setState(() => _isProcessingAi = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isAiMode ? "AI Vision Assistant" : "Barcode Scanner", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Toggle between AI Name Scan and Barcode Scan
          TextButton.icon(
            onPressed: () {
              setState(() {
                _isAiMode = !_isAiMode;
                if (_isAiMode) {
                  _scannerController.stop();
                } else {
                  _scannerController.start();
                }
              });
            },
            icon: Icon(_isAiMode ? Icons.qr_code_scanner : Icons.auto_awesome, color: tealAccent),
            label: Text(
              _isAiMode ? "Use Barcode" : "Use AI Vision",
              style: TextStyle(color: tealAccent, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
            tooltip: "Toggle Flashlight",
          ),
        ],
      ),
      body: Stack(
        children: [
          if (!_isAiMode)
            MobileScanner(
              controller: _scannerController,
              onDetect: (capture) {
                if (_hasDetected || _isProcessingAi) return;

                final List<Barcode> barcodes = capture.barcodes;
                for (final barcode in barcodes) {
                  final String? code = barcode.rawValue;
                  if (code != null && code.isNotEmpty) {
                    _hasDetected = true;
                    _scannerController.stop();
                    Navigator.pop(context, code);
                    return;
                  }
                }
              },
            )
          else
            Container(
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.camera_enhance, color: tealAccent.withValues(alpha: 0.5), size: 80),
                    const SizedBox(height: 20),
                    const Text(
                      "AI Vision Assistant Ready",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Center the item in the box and tap capture to identify",
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          // Targeting Viewfinder Box
          Center(
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                border: Border.all(color: tealAccent.withValues(alpha: 0.8), width: 2),
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
                      color: Colors.black.withValues(alpha: 0.8),
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