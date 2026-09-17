import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class FoodRecognition {
  const FoodRecognition({
    required this.label,
    required this.confidence,
    required this.isFood,
  });

  final String label;
  final double confidence;
  final bool isFood;
}

class FoodRecognitionService {
  FoodRecognitionService()
      : _labeler = ImageLabeler(
          options: ImageLabelerOptions(confidenceThreshold: 0.45),
        );

  final ImageLabeler _labeler;

  static const _foodTerms = <String>{
    'food',
    'dish',
    'meal',
    'cuisine',
    'ingredient',
    'produce',
    'fruit',
    'vegetable',
    'bread',
    'rice',
    'pasta',
    'noodle',
    'soup',
    'salad',
    'meat',
    'chicken',
    'fish',
    'seafood',
    'dessert',
    'cake',
    'dairy',
    'cheese',
    'breakfast',
    'snack',
    'recipe',
    'baked goods',
  };

  Future<List<FoodRecognition>> recognize(String imagePath) async {
    final labels =
        await _labeler.processImage(InputImage.fromFilePath(imagePath));
    final results = labels
        .map((label) => FoodRecognition(
              label: label.label,
              confidence: label.confidence,
              isFood: _looksLikeFood(label.label),
            ))
        .toList()
      ..sort((a, b) {
        if (a.isFood != b.isFood) return a.isFood ? -1 : 1;
        return b.confidence.compareTo(a.confidence);
      });
    return results;
  }

  bool _looksLikeFood(String label) {
    final normalized = label.toLowerCase();
    return _foodTerms.any(
      (term) => normalized == term || normalized.contains(term),
    );
  }

  Future<void> close() => _labeler.close();
}
