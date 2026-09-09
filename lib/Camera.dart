import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  bool _hasDetected = false;
  bool _isProcessingAi = false;

  final Color navyBlue = const Color(0xFF1E3A5F);

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
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
      autoStart: true,
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
    if (!_scannerController.value.isInitialized) return;
    if (state == AppLifecycleState.paused) {
      _scannerController.stop();
    } else if (state == AppLifecycleState.resumed) {
      _scannerController.start();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  // Captures current camera view and analyzes image using Gemini AI
  // Captures current camera view and analyzes image using Gemini AI
  Future<void> _captureAndAnalyzeWithGemini() async {
    if (_isProcessingAi || _hasDetected || _visionModel == null) return;

    setState(() => _isProcessingAi = true);

    try {
      final ImagePicker picker = ImagePicker();
      // Capture a photo directly from device camera
      final XFile? imageFile = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
      );

      if (imageFile != null) {
        final Uint8List imageBytes = await imageFile.readAsBytes();

        final prompt = TextPart('''
          Analyze this product image carefully.
          Return ONLY the exact item name string as it appears in a store catalog (e.g., "Coca Cola").
          If no retail product is identified clearly, return "UNKNOWN".
        ''');

        final imagePart = DataPart('image/jpeg', imageBytes);

        final response = await _visionModel!.generateContent([
          Content.multi([prompt, imagePart])
        ]);

        final String detectedName = response.text?.trim() ?? 'UNKNOWN';

        if (detectedName != 'UNKNOWN' && detectedName.isNotEmpty) {
          await fetchProductByCameraLabel(detectedName);
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

  // Query Firestore for matching inventory items
  Future<void> fetchProductByCameraLabel(String detectedLabel) async {
    if (_hasDetected) return;

    try {
      QuerySnapshot querySnapshot = await FirebaseFirestore.instance
          .collection('Inventory')
          .where('itemName', isEqualTo: detectedLabel)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        _hasDetected = true;
        _scannerController.stop();

        var productDoc = querySnapshot.docs.first;
        var data = productDoc.data() as Map<String, dynamic>;

        await FirebaseFirestore.instance
            .collection('Inventory')
            .doc(productDoc.id)
            .update({'stock': FieldValue.increment(-1)});

        if (!mounted) return;

        Navigator.pop(context, {
          'id': productDoc.id,
          'itemName': data['itemName'],
          'price': data['price'],
          'category': data['category'],
        });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No item "$detectedLabel" found in Inventory.')),
        );
      }
    } catch (e) {
      debugPrint("Error querying Firestore: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Scan Product or Barcode", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: navyBlue,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _scannerController.toggleTorch(),
            tooltip: "Toggle Flashlight",
          ),
        ],
      ),
      body: Stack(
        children: [
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
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navyBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isProcessingAi ? null : _captureAndAnalyzeWithGemini,
                  icon: _isProcessingAi
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Icon(Icons.center_focus_strong),
                  label: Text(_isProcessingAi ? "Analyzing with Gemini..." : "Scan Item with Gemini AI"),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    "Point camera at barcode for auto-scan, or tap AI Scan for item detection",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
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