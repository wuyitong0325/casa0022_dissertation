class SpeciesProfile {
  final String commonName;
  final String scientificName;
  final String type;

  final String description;
  final String habitatNote;
  final String funFact;

  final String? imageUrl;
  final String? audioUrl;
  final String? audioSourceLabel;
  final String? audioSourceUrl;
  final String? sourceLabel;
  final String? sourceUrl;

  final bool isOnline;

  const SpeciesProfile({
    required this.commonName,
    required this.scientificName,
    required this.type,
    required this.description,
    required this.habitatNote,
    required this.funFact,
    this.imageUrl,
    this.audioUrl,
    this.audioSourceLabel,
    this.audioSourceUrl,
    this.sourceLabel,
    this.sourceUrl,
    this.isOnline = false,
  });

  bool get isBat => type == 'bat';

  bool get isBird => type == 'bird';

  SpeciesProfile copyWith({
    String? commonName,
    String? scientificName,
    String? type,
    String? description,
    String? habitatNote,
    String? funFact,
    String? imageUrl,
    String? audioUrl,
    String? audioSourceLabel,
    String? audioSourceUrl,
    String? sourceLabel,
    String? sourceUrl,
    bool? isOnline,
  }) {
    return SpeciesProfile(
      commonName: commonName ?? this.commonName,
      scientificName: scientificName ?? this.scientificName,
      type: type ?? this.type,
      description: description ?? this.description,
      habitatNote: habitatNote ?? this.habitatNote,
      funFact: funFact ?? this.funFact,
      imageUrl: imageUrl ?? this.imageUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      audioSourceLabel: audioSourceLabel ?? this.audioSourceLabel,
      audioSourceUrl: audioSourceUrl ?? this.audioSourceUrl,
      sourceLabel: sourceLabel ?? this.sourceLabel,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}