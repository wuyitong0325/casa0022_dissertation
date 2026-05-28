import '../models/detection_event.dart';
import '../models/species_profile.dart';

class SpeciesRepository {
  static final List<SpeciesProfile> curatedProfiles = [
    const SpeciesProfile(
      commonName: 'Common Raven',
      scientificName: 'Corvus corax',
      type: 'bird',
      description:
          'A large and intelligent corvid with a deep call. In an acoustic monitoring system, raven-like calls may appear as strong, low-frequency bird signals.',
      habitatNote:
          'In urban parks, corvids may be detected around trees, open lawns, paths and nearby buildings.',
      funFact:
          'Ravens are known for complex social behaviour and problem-solving ability.',
    ),
    const SpeciesProfile(
      commonName: 'Common Cuckoo',
      scientificName: 'Cuculus canorus',
      type: 'bird',
      description:
          'A migratory bird famous for its distinctive call. It is often used as an example of a recognisable bird sound.',
      habitatNote:
          'Cuckoo detections are seasonal and strongly affected by location and date.',
      funFact:
          'The cuckoo is known for laying eggs in the nests of other bird species.',
    ),
    const SpeciesProfile(
      commonName: 'Common Pipistrelle',
      scientificName: 'Pipistrellus pipistrellus',
      type: 'bat',
      description:
          'A small and widespread UK bat species often found in parks, gardens and woodland edges.',
      habitatNote:
          'Often active near trees, paths, water and insect-rich areas at dusk and night.',
      funFact:
          'A pipistrelle can eat thousands of small insects in a single night.',
    ),
    const SpeciesProfile(
      commonName: 'Soprano Pipistrelle',
      scientificName: 'Pipistrellus pygmaeus',
      type: 'bat',
      description:
          'A small bat species that often uses higher-frequency echolocation calls than the common pipistrelle.',
      habitatNote:
          'Often associated with wetlands, rivers, ponds and green corridors.',
      funFact:
          'Its name comes from its relatively high-pitched echolocation calls.',
    ),
  ];

  static SpeciesProfile findLocalProfile(DetectionEvent event) {
    final common = event.commonName.toLowerCase();
    final scientific = event.scientificName.toLowerCase();

    for (final profile in curatedProfiles) {
      if (profile.commonName.toLowerCase() == common ||
          profile.scientificName.toLowerCase() == scientific) {
        return profile;
      }
    }

    return fallbackForEvent(event);
  }

  static SpeciesProfile fallbackForEvent(DetectionEvent event) {
    if (event.isBat) {
      return SpeciesProfile(
        commonName: event.commonName,
        scientificName: event.scientificName,
        type: 'bat',
        description:
            'A bat-like ultrasonic acoustic event was detected. A detailed online profile has not been loaded yet.',
        habitatNote:
            'Bat activity is usually stronger at night, especially near trees, water and insect-rich areas.',
        funFact:
            'Many bat calls are ultrasonic, meaning they are above the range of normal human hearing.',
      );
    }

    return SpeciesProfile(
      commonName: event.commonName,
      scientificName: event.scientificName,
      type: 'bird',
      description:
          'A bird-like acoustic event was detected from the live monitoring stream. A detailed online profile has not been loaded yet.',
      habitatNote:
          'Bird detections can be affected by distance, wind, traffic noise and call quality.',
      funFact:
          'Urban parks can contain surprisingly rich acoustic biodiversity.',
    );
  }
}