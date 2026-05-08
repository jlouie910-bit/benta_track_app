import 'package:google_generative_ai/google_generative_ai.dart';

class AIService {
  static const String _apiKey = 'AIzaSyAiyWvCp3DEzhX_E2yA_L37f2-jbTQDB9A';

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
                "Focus on profit trends and specific items that need restocking."
        ),
      );

      final prompt = "Transactions: $transactions \n Inventory: $inventory \n Give me a brief business insight:";
      final response = await model.generateContent([Content.text(prompt)]);

      return response.text ?? "Hindi makuha ang insight sa ngayon.";
    } catch (e) {
      return "Error: $e";
    }
  }

  static Future<String> getAIResponse(String userPrompt, List<Map<String, dynamic>> businessData) async {
    final model = GenerativeModel(
      model: 'gemini-2.5-flash',
      apiKey: _apiKey,
    );
    final prompt = "Context: $businessData \n Question: $userPrompt";
    final response = await model.generateContent([Content.text(prompt)]);
    return response.text ?? "Pasensya na, subukan muli.";
  }
}