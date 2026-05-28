import '../models/detection_event.dart';
import '../models/species_profile.dart';

class SpeciesRepository {
  static final List<SpeciesProfile> curatedProfiles = [
    const SpeciesProfile(
      commonName: 'Common Blackbird',
      scientificName: 'Turdus merula',
      type: 'bird',
      description:
          'A familiar urban bird with rich, melodic song. It is commonly heard in parks, gardens and woodland edges.',
      habitatNote: 'Shrubs, lawns, gardens, woodland edges and city parks.',
      funFact: 'Male blackbirds often sing from high perches at dawn and dusk.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'European Robin',
      scientificName: 'Erithacus rubecula',
      type: 'bird',
      description:
          'A small songbird with a distinctive orange-red breast and a clear, delicate song.',
      habitatNote: 'Parks, hedgerows, gardens and woodland understory.',
      funFact: 'Robins are one of the few UK birds that regularly sing in winter.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Great Tit',
      scientificName: 'Parus major',
      type: 'bird',
      description:
          'A common parkland bird with varied calls, including repetitive two-note songs.',
      habitatNote: 'Woodland, parks, gardens and tree-lined streets.',
      funFact: 'Great tits can adapt their songs in noisy urban environments.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Blue Tit',
      scientificName: 'Cyanistes caeruleus',
      type: 'bird',
      description:
          'A small colourful bird often heard in gardens and parks, with sharp contact calls.',
      habitatNote: 'Trees, hedges, gardens and woodland patches.',
      funFact: 'Blue tits are agile foragers and often hang upside down on branches.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Eurasian Wren',
      scientificName: 'Troglodytes troglodytes',
      type: 'bird',
      description:
          'A tiny bird with a surprisingly loud and complex song.',
      habitatNote: 'Dense vegetation, hedges, woodland edges and park undergrowth.',
      funFact: 'For its size, the wren has one of the loudest songs in UK parks.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'House Sparrow',
      scientificName: 'Passer domesticus',
      type: 'bird',
      description:
          'A social urban bird with short chirping calls, often found near buildings.',
      habitatNote: 'Urban neighbourhoods, parks, gardens and street trees.',
      funFact: 'House sparrows often form noisy social groups.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Wood Pigeon',
      scientificName: 'Columba palumbus',
      type: 'bird',
      description:
          'A large pigeon with a deep, rhythmic cooing call common in UK parks.',
      habitatNote: 'Woodland, parks, gardens and open lawns.',
      funFact: 'Its wing claps during take-off can be louder than its call.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Carrion Crow',
      scientificName: 'Corvus corone',
      type: 'bird',
      description:
          'An intelligent black corvid with rough cawing calls.',
      habitatNote: 'Open parkland, trees, rooftops and urban green spaces.',
      funFact: 'Crows are highly adaptable and can recognise repeated patterns.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Eurasian Magpie',
      scientificName: 'Pica pica',
      type: 'bird',
      description:
          'A bold black-and-white corvid with chattering calls and complex social behaviour.',
      habitatNote: 'Parks, gardens, sports fields and urban trees.',
      funFact: 'Magpies are members of the crow family and are highly intelligent.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Common Chaffinch',
      scientificName: 'Fringilla coelebs',
      type: 'bird',
      description:
          'A common finch with a bright descending song and sharp contact calls.',
      habitatNote: 'Woodland edges, gardens and mature park trees.',
      funFact: 'Its song often ends with a flourish-like phrase.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Common Cuckoo',
      scientificName: 'Cuculus canorus',
      type: 'bird',
      description:
          'A migratory bird famous for its distinctive two-note call.',
      habitatNote: 'Seasonal visitor; more likely near wetlands, scrub and open woodland.',
      funFact: 'The cuckoo is known for laying eggs in other birds’ nests.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Common Raven',
      scientificName: 'Corvus corax',
      type: 'bird',
      description:
          'A large intelligent corvid with deep croaking calls.',
      habitatNote: 'More common in open countryside, but acoustic classifiers may return it for deep corvid-like calls.',
      funFact: 'Ravens are among the smartest birds in the world.',
      sourceLabel: 'Local curated profile',
    ),

    const SpeciesProfile(
      commonName: 'Common Pipistrelle',
      scientificName: 'Pipistrellus pipistrellus',
      type: 'bat',
      description:
          'A tiny and widespread UK bat species, often encountered in urban parks and gardens.',
      habitatNote: 'Often active around trees, paths, water and streetlights where insects gather.',
      funFact: 'It can eat thousands of small insects in one night.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Soprano Pipistrelle',
      scientificName: 'Pipistrellus pygmaeus',
      type: 'bat',
      description:
          'A small bat similar to the common pipistrelle but often associated with higher-frequency calls.',
      habitatNote: 'Wetlands, rivers, ponds, woodland edges and urban green corridors.',
      funFact: 'Its name comes from its relatively high-pitched echolocation.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Nathusius’ Pipistrelle',
      scientificName: 'Pipistrellus nathusii',
      type: 'bat',
      description:
          'A migratory pipistrelle species that may be recorded in the UK.',
      habitatNote: 'Wetlands, riversides, woodland edges and coastal migration routes.',
      funFact: 'Some individuals travel long distances across Europe.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Noctule',
      scientificName: 'Nyctalus noctula',
      type: 'bat',
      description:
          'One of the UK’s larger bats, often flying high and fast in open spaces.',
      habitatNote: 'Open parkland, lakesides, woodland edges and large trees.',
      funFact: 'Noctules can emerge early in the evening and fly above treetops.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Serotine',
      scientificName: 'Eptesicus serotinus',
      type: 'bat',
      description:
          'A large bat species with strong echolocation calls, often linked to buildings and open habitats.',
      habitatNote: 'Pasture, park edges, gardens and areas near buildings.',
      funFact: 'Serotines often fly with a slower, powerful wingbeat.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Daubenton’s Bat',
      scientificName: 'Myotis daubentonii',
      type: 'bat',
      description:
          'A bat often associated with water, flying low over ponds, canals and rivers.',
      habitatNote: 'Water bodies, canals, rivers, ponds and tree-lined banks.',
      funFact: 'It is sometimes called the “water bat”.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Brown Long-eared Bat',
      scientificName: 'Plecotus auritus',
      type: 'bat',
      description:
          'A quiet, manoeuvrable bat with large ears, often foraging close to vegetation.',
      habitatNote: 'Woodland, old buildings, hedgerows and sheltered park edges.',
      funFact: 'Its long ears help it detect tiny sounds made by insects.',
      sourceLabel: 'Local curated profile',
    ),
    const SpeciesProfile(
      commonName: 'Leisler’s Bat',
      scientificName: 'Nyctalus leisleri',
      type: 'bat',
      description:
          'A medium-sized bat that often flies in open areas and above trees.',
      habitatNote: 'Parks, woodland edges, open water and mature trees.',
      funFact: 'It is sometimes called the lesser noctule.',
      sourceLabel: 'Local curated profile',
    ),
  ];

  static SpeciesProfile findLocalProfile(DetectionEvent event) {
    final common = event.commonName.toLowerCase().trim();
    final scientific = event.scientificName.toLowerCase().trim();

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
            'A bat-like ultrasonic acoustic event was detected. Online information will be loaded when available.',
        habitatNote:
            'Bat activity is usually stronger at night, especially near trees, water and insect-rich areas.',
        funFact:
            'Many bat calls are ultrasonic, which means they are above the range of normal human hearing.',
      );
    }

    return SpeciesProfile(
      commonName: event.commonName,
      scientificName: event.scientificName,
      type: 'bird',
      description:
          'A bird-like acoustic event was detected from the live monitoring stream. Online information will be loaded when available.',
      habitatNote:
          'Bird detections can be affected by distance, wind, traffic noise and call quality.',
      funFact:
          'Urban parks can contain surprisingly rich acoustic biodiversity.',
    );
  }
}