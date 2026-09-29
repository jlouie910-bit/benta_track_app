import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  static String get _apiKey => dotenv.env['VISION_API_KEY'] ?? '';

  /// Vision model service for identifying retail items from an image file
  static Future<Map<String, String>?> detectItemFromImage(File imageFile) async {
    if (_apiKey.isEmpty) {
      throw Exception("VISION_API_KEY is missing from .env file");
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
        systemInstruction: Content.system(
          "You are an AI inventory scanner for a sari-sari store or retail business in the Philippines. "
          "Analyze the image and return ONLY a plain JSON object with keys: "
          "'itemName' (specific product name and brand), "
          "'category' (choose best match: Food Products & Staples, Snacks & Treats, Beverages, Personal Care & Hygiene, Household & Cleaning Supplies), "
          "and 'estimatedPrice' (numeric string estimate in PHP, or empty string if unknown)."
        ),
      );

      final imageBytes = await imageFile.readAsBytes();
      final content = [
        Content.multi([
          TextPart("Identify this retail item and extract product details."),
          DataPart('image/jpeg', imageBytes),
        ])
      ];

      final response = await model.generateContent(content);

      if (response.text != null) {
        return {
          'rawResult': response.text!,
        };
      }
      return null;
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// Generates business insight for Filipino micro-enterprises
  static Future<String> getBusinessInsight({
    required List<Map<String, dynamic>> transactions,
    required List<Map<String, dynamic>> inventory,
  }) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
        systemInstruction: Content.system(
          "You are the BentaTrack Business Analyst for Filipino micro-enterprises. "
          "Analyze the data and provide a 2-sentence insight in Taglish. "
          "Focus on profit trends and specific items that need restocking. "
          "CRITICAL: Do NOT use any asterisks (*), bold formatting (**), bullet points, or markdown symbols. Write your response using plain text paragraphs only."
        ),
      );

      final prompt = "Transactions: $transactions \n Inventory: $inventory \n Give me a brief business insight:";
      final response = await model.generateContent([Content.text(prompt)]);

      return response.text ?? "Hindi makuha ang insight sa ngayon.";
    } catch (e) {
      return "Error: $e";
    }
  }

  /// Handles conversational Q&A based on store context
  static Future<String> getAIResponse(String userPrompt, List<Map<String, dynamic>> businessData) async {
    try {
      final model = GenerativeModel(
        model: 'gemini-2.5-flash',
        apiKey: _apiKey,
        systemInstruction: Content.system(
          "You are BentaTrack AI, a helpful financial assistant for sari-sari store owners in the Philippines. "
          "When asked about profits, sales, or data, calculate the numbers directly in the background. "
          "DO NOT show your step-by-step filtering process, raw JSON, or itemized timestamp lists. "
          "Give clear, concise, and direct answers in Taglish, straight to the point. "
          "CRITICAL: Do NOT use any asterisks (*), bold formatting (**), bullet points, or markdown symbols. Write your response using plain text paragraphs only."
        ),
      );
      
      final prompt = "Context: $businessData \n Question: $userPrompt";
      final response = await model.generateContent([Content.text(prompt)]);
      return response.text ?? "Pasensya na, subukan muli.";
    } catch (e) {
      return "Error: $e";
    }
  }
}