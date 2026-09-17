import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'food_recognition_service.dart';

class RecognitionRecord {
  const RecognitionRecord({
    required this.timestamp,
    required this.mode,
    required this.results,
  });

  final DateTime timestamp;
  final String mode;
  final List<FoodRecognition> results;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'mode': mode,
        'results': results
            .map((result) => {
                  'label': result.label,
                  'confidence': result.confidence,
                  'isFood': result.isFood,
                })
            .toList(),
      };

  factory RecognitionRecord.fromJson(Map<String, dynamic> json) =>
      RecognitionRecord(
        timestamp: DateTime.parse(json['timestamp']),
        mode: json['mode'] ?? 'capture',
        results: (json['results'] as List? ?? const [])
            .map((item) => Map<String, dynamic>.from(item))
            .map(
              (item) => FoodRecognition(
                label: item['label'],
                confidence: (item['confidence'] as num).toDouble(),
                isFood: item['isFood'] == true,
              ),
            )
            .toList(),
      );
}

class RecognitionHistoryStore {
  static const _key = 'recognition_history_v1';
  static const maxRecords = 100;

  Future<List<RecognitionRecord>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getStringList(_key) ?? const [];
    return raw
        .map((item) => RecognitionRecord.fromJson(jsonDecode(item)))
        .toList();
  }

  Future<List<RecognitionRecord>> add(RecognitionRecord record) async {
    final records = [record, ...await load()].take(maxRecords).toList();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(
      _key,
      records.map((item) => jsonEncode(item.toJson())).toList(),
    );
    return records;
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
  }
}
