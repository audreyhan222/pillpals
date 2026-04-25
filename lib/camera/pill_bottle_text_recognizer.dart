import 'dart:io';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class PillBottleTextRecognizer {
  PillBottleTextRecognizer() : _textRecognizer = TextRecognizer();

  final TextRecognizer _textRecognizer;

  Future<String> extractTextFromPath(String imagePath) async {
    final inputImage = InputImage.fromFilePath(imagePath);
    final recognizedText = await _textRecognizer.processImage(inputImage);
    return recognizedText.text.trim();
  }

  Future<String> extractTextFromFile(File imageFile) {
    return extractTextFromPath(imageFile.path);
  }

  Future<void> dispose() async {
    await _textRecognizer.close();
  }
}
