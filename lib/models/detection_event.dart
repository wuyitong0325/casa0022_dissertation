class DetectionEvent {
  final String deviceId;
  final String type;
  final String commonName;
  final String scientificName;
  final double confidence;
  final double startTime;
  final double endTime;
  final DateTime timestamp;

  DetectionEvent({
    required this.deviceId,
    required this.type,
    required this.commonName,
    required this.scientificName,
    required this.confidence,
    required this.startTime,
    required this.endTime,
    required this.timestamp,
  });

  factory DetectionEvent.fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString().toLowerCase() ?? 'unknown';

    final commonName = json['common_name'] ??
        json['commonName'] ??
        json['species'] ??
        json['class'] ??
        json['class_name'] ??
        json['label'] ??
        'Unknown species';

    final scientificName = json['scientific_name'] ??
        json['scientificName'] ??
        json['latin_name'] ??
        json['scientific'] ??
        'Unknown';

    return DetectionEvent(
      deviceId: json['device_id']?.toString() ?? 'unknown-device',
      type: type,
      commonName: commonName.toString(),
      scientificName: scientificName.toString(),
      confidence: _toDouble(json['confidence']),
      startTime: _toDouble(json['start_time']),
      endTime: _toDouble(json['end_time']),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  static double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  String get speciesKey {
    final sci = scientificName.toLowerCase().trim();
    final common = commonName.toLowerCase().trim();

    if (sci.isNotEmpty && sci != 'unknown') {
      return '$type:$sci';
    }

    return '$type:$common';
  }

  bool get isBird => type == 'bird';
  bool get isBat => type == 'bat';

  String get emoji {
    if (isBat) return '🦇';
    if (isBird) return '🐦';
    return '🌿';
  }

  String get displayType {
    if (isBat) return 'Bat';
    if (isBird) return 'Bird';
    return 'Wildlife';
  }

  String get confidenceText => '${(confidence * 100).toStringAsFixed(0)}%';

  String get confidenceLabel {
    if (confidence >= 0.75) return 'High confidence';
    if (confidence >= 0.40) return 'Possible match';
    return 'Uncertain signal';
  }
}