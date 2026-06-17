import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/detection_event.dart';
import '../models/species_profile.dart';
import '../services/online_species_service.dart';
import '../services/species_repository.dart';
import '../widgets/species_info_sheet.dart';

class SoundExplorerPage extends StatefulWidget {
  const SoundExplorerPage({super.key});

  @override
  State<SoundExplorerPage> createState() => _SoundExplorerPageState();
}

class _SoundExplorerPageState extends State<SoundExplorerPage> {
  String filter = 'all';
  String? loadingKey;
  _AtlasMarker? selectedMarker;

  final TextEditingController searchController = TextEditingController();
  final FocusNode searchFocusNode = FocusNode();
  bool isSearching = false;

  @override
  void dispose() {
    searchController.dispose();
    searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profiles = SpeciesRepository.curatedProfiles;
    final searchProfiles = _buildSearchProfiles(profiles);
    final searchSuggestions = _searchSuggestions(
      searchController.text,
      searchProfiles,
    );
    final markers = _filteredMarkers();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Species Atlas'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Explore Wildlife Around the World',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a bird or bat marker to learn where the reference species is commonly found, then open its full species profile.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 16),

          _AtlasSearchCard(
            controller: searchController,
            focusNode: searchFocusNode,
            isSearching: isSearching,
            suggestions: searchSuggestions,
            onChanged: (_) => setState(() {}),
            onSubmitted: _openSearchResult,
            onSuggestionTap: (profile) {
              searchController.text = profile.commonName;
              _openProfile(
                context: context,
                localProfile: profile,
              );
            },
          ),

          const SizedBox(height: 16),

          _AtlasMapCard(
            markers: markers,
            selectedMarker: selectedMarker,
            onMarkerTap: (marker) {
              setState(() {
                selectedMarker = marker;
              });
            },
            onOpenReference: (marker) {
              final profile = _profileForMarker(marker, profiles);
              _openProfile(
                context: context,
                localProfile: profile,
              );
            },
          ),

          const SizedBox(height: 14),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _FilterChip(
                label: 'All',
                value: 'all',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Birds',
                value: 'birds',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Bats',
                value: 'bats',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Europe',
                value: 'europe',
                group: filter,
                onTap: _setFilter,
              ),
              _FilterChip(
                label: 'Worldwide',
                value: 'worldwide',
                group: filter,
                onTap: _setFilter,
              ),
            ],
          ),

          const SizedBox(height: 16),

          const _AtlasLegend(),

          const SizedBox(height: 22),

          const Text(
            'Reference Species',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a species to view images, habitat notes, behaviour and real wildlife sound where available.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 14),

          for (final profile in _filteredProfiles(profiles))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ReferenceSpeciesCard(
                profile: profile,
                isLoading: loadingKey == _profileKey(profile),
                onTap: () => _openProfile(
                  context: context,
                  localProfile: profile,
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<_AtlasMarker> _filteredMarkers() {
    return _atlasMarkers.where((marker) {
      if (filter == 'birds') return marker.type == 'bird';
      if (filter == 'bats') return marker.type == 'bat';
      if (filter == 'europe') return marker.regionGroup == 'europe';
      if (filter == 'worldwide') return marker.regionGroup == 'worldwide';
      return true;
    }).toList();
  }

  List<SpeciesProfile> _filteredProfiles(List<SpeciesProfile> profiles) {
    return profiles.where((profile) {
      if (filter == 'birds') return profile.type == 'bird';
      if (filter == 'bats') return profile.type == 'bat';

      if (filter == 'europe' || filter == 'worldwide') {
        final key = _profileKey(profile);
        return _atlasMarkers.any(
          (marker) =>
              _markerKey(marker) == key && marker.regionGroup == filter,
        );
      }

      return true;
    }).toList();
  }

  List<SpeciesProfile> _buildSearchProfiles(List<SpeciesProfile> profiles) {
    final results = <SpeciesProfile>[
      ...profiles,
    ];

    for (final marker in _atlasMarkers) {
      final exists = results.any(
        (profile) =>
            profile.commonName.toLowerCase() ==
                marker.commonName.toLowerCase() ||
            profile.scientificName.toLowerCase() ==
                marker.scientificName.toLowerCase(),
      );

      if (!exists) {
        results.add(
          SpeciesProfile(
            commonName: marker.commonName,
            scientificName: marker.scientificName,
            type: marker.type,
            description:
                '${marker.commonName} is included as a searchable reference species in the Park Life Monitor atlas.',
            habitatNote: marker.habitat,
            funFact: marker.region,
          ),
        );
      }
    }

    return results;
  }

  List<SpeciesProfile> _searchSuggestions(
    String query,
    List<SpeciesProfile> profiles,
  ) {
    final normalisedQuery = _normaliseSearchText(query);

    final ranked = profiles.where((profile) {
      if (normalisedQuery.isEmpty) {
        return _defaultSuggestionNames.contains(
          profile.commonName.toLowerCase(),
        );
      }

      return _normaliseSearchText(profile.commonName)
              .contains(normalisedQuery) ||
          _normaliseSearchText(profile.scientificName)
              .contains(normalisedQuery);
    }).toList();

    ranked.sort((a, b) {
      if (normalisedQuery.isEmpty) {
        final aIndex = _defaultSuggestionNames.indexOf(
          a.commonName.toLowerCase(),
        );
        final bIndex = _defaultSuggestionNames.indexOf(
          b.commonName.toLowerCase(),
        );

        final safeA = aIndex == -1 ? 999 : aIndex;
        final safeB = bIndex == -1 ? 999 : bIndex;

        if (safeA != safeB) return safeA.compareTo(safeB);
      }

      final aCommon = _normaliseSearchText(a.commonName);
      final bCommon = _normaliseSearchText(b.commonName);
      final aScientific = _normaliseSearchText(a.scientificName);
      final bScientific = _normaliseSearchText(b.scientificName);

      final aStarts =
          aCommon.startsWith(normalisedQuery) ||
          aScientific.startsWith(normalisedQuery);
      final bStarts =
          bCommon.startsWith(normalisedQuery) ||
          bScientific.startsWith(normalisedQuery);

      if (aStarts != bStarts) return aStarts ? -1 : 1;

      return a.commonName.compareTo(b.commonName);
    });

    return ranked.take(7).toList();
  }

  SpeciesProfile _profileForMarker(
    _AtlasMarker marker,
    List<SpeciesProfile> profiles,
  ) {
    final markerKey = _markerKey(marker);

    for (final profile in profiles) {
      if (_profileKey(profile) == markerKey) {
        return profile;
      }
    }

    return SpeciesProfile(
      commonName: marker.commonName,
      scientificName: marker.scientificName,
      type: marker.type,
      description:
          '${marker.commonName} is included as a reference species in the Park Life Monitor atlas.',
      habitatNote: marker.habitat,
      funFact: marker.region,
    );
  }

  Future<void> _openSearchResult(String rawQuery) async {
    final query = rawQuery.trim();

    if (query.isEmpty) {
      _showAtlasMessage('Type a common name or scientific name first.');
      return;
    }

    final profiles = _buildSearchProfiles(SpeciesRepository.curatedProfiles);
    final match = _findBestProfileMatch(query, profiles);
    final profile = match ?? _profileFromSearchQuery(query, profiles);

    searchFocusNode.unfocus();

    setState(() {
      isSearching = true;
    });

    try {
      await _openProfile(
        context: context,
        localProfile: profile,
      );
    } finally {
      if (mounted) {
        setState(() {
          isSearching = false;
        });
      }
    }
  }

  SpeciesProfile? _findBestProfileMatch(
    String query,
    List<SpeciesProfile> profiles,
  ) {
    final normalisedQuery = _normaliseSearchText(query);

    for (final profile in profiles) {
      if (_normaliseSearchText(profile.commonName) == normalisedQuery ||
          _normaliseSearchText(profile.scientificName) == normalisedQuery) {
        return profile;
      }
    }

    for (final profile in profiles) {
      if (_normaliseSearchText(profile.commonName).contains(normalisedQuery) ||
          _normaliseSearchText(profile.scientificName)
              .contains(normalisedQuery)) {
        return profile;
      }
    }

    return null;
  }

  SpeciesProfile _profileFromSearchQuery(
    String query,
    List<SpeciesProfile> profiles,
  ) {
    final inferredType = _inferTypeFromQuery(query, profiles);
    final cleanedName = query.trim();

    return SpeciesProfile(
      commonName: cleanedName,
      scientificName: cleanedName,
      type: inferredType,
      description:
          '$cleanedName was searched from the Atlas. Online information will be loaded when available.',
      habitatNote: inferredType == 'bat'
          ? 'Bat species are often associated with night-time activity, roosting sites, trees, water and insect-rich areas.'
          : 'Bird species may be associated with parks, woodland, gardens, wetlands or urban green corridors depending on the species.',
      funFact: inferredType == 'bat'
          ? 'Many bats use ultrasonic echolocation calls that need special recording equipment to analyse.'
          : 'Acoustic monitoring can help reveal bird activity that may be missed by visual observation.',
    );
  }

  String _inferTypeFromQuery(
    String query,
    List<SpeciesProfile> profiles,
  ) {
    final normalisedQuery = _normaliseSearchText(query);

    for (final profile in profiles) {
      if (_normaliseSearchText(profile.commonName).contains(normalisedQuery) ||
          _normaliseSearchText(profile.scientificName)
              .contains(normalisedQuery) ||
          normalisedQuery.contains(_normaliseSearchText(profile.commonName)) ||
          normalisedQuery
              .contains(_normaliseSearchText(profile.scientificName))) {
        return profile.type;
      }
    }

    const batTerms = [
      'bat',
      'pipistrelle',
      'pipistrellus',
      'serotine',
      'eptesicus',
      'noctule',
      'nyctalus',
      'myotis',
      'rhinolophus',
      'plecotus',
      'daubenton',
      'natterer',
      'leisler',
      'horseshoe',
    ];

    if (batTerms.any(normalisedQuery.contains)) {
      return 'bat';
    }

    return 'bird';
  }

  Future<void> _openProfile({
    required BuildContext context,
    required SpeciesProfile localProfile,
  }) async {
    final onlineService = context.read<OnlineSpeciesService>();

    final event = DetectionEvent(
      deviceId: 'species-atlas',
      type: localProfile.type,
      commonName: localProfile.commonName,
      scientificName: localProfile.scientificName,
      confidence: 1,
      startTime: 0,
      endTime: 0,
      timestamp: DateTime.now(),
    );

    final key = _profileKey(localProfile);

    setState(() {
      loadingKey = key;
    });

    SpeciesProfile profile = localProfile;

    try {
      profile = await onlineService.fetchProfile(event);
    } catch (_) {
      profile = localProfile;
    }

    if (!mounted) return;

    setState(() {
      loadingKey = null;
    });

    if (!context.mounted) return;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SpeciesInfoSheet(
        event: event,
        profile: profile,
        isLoading: false,
      ),
    );
  }

  void _setFilter(String value) {
    setState(() {
      filter = value;
      selectedMarker = null;
    });
  }

  String _profileKey(SpeciesProfile profile) {
    return '${profile.type}:${profile.scientificName.toLowerCase().trim()}';
  }

  String _markerKey(_AtlasMarker marker) {
    return '${marker.type}:${marker.scientificName.toLowerCase().trim()}';
  }

  String _normaliseSearchText(String value) {
    return value.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _showAtlasMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _AtlasSearchCard extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isSearching;
  final List<SpeciesProfile> suggestions;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<SpeciesProfile> onSuggestionTap;

  const _AtlasSearchCard({
    required this.controller,
    required this.focusNode,
    required this.isSearching,
    required this.suggestions,
    required this.onChanged,
    required this.onSubmitted,
    required this.onSuggestionTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFFDDE8DA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.045),
            blurRadius: 14,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Search the atlas',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Search by common name, scientific name, or partial name. Results open the same species card with images, notes and audio where available.',
            style: TextStyle(
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            focusNode: focusNode,
            textInputAction: TextInputAction.search,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            decoration: InputDecoration(
              hintText: 'Search common or scientific name...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Search',
                      onPressed: () => onSubmitted(controller.text),
                      icon: const Icon(Icons.arrow_forward_rounded),
                    ),
              filled: true,
              fillColor: const Color(0xFFF5F9F3),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
if (controller.text.trim().isEmpty)
  const Text(
    'Enter a common name or scientific name, for example Turdus merula or Pipistrellus pipistrellus.',
    style: TextStyle(
      color: Colors.black54,
      height: 1.35,
    ),
  )
else if (suggestions.isEmpty)
  const Text(
    'No close local match found. Press search to try loading it online.',
    style: TextStyle(color: Colors.black54),
  )
else ...[
  const Text(
    'Matching species',
    style: TextStyle(
      fontWeight: FontWeight.w900,
      color: Colors.black87,
    ),
  ),
  const SizedBox(height: 8),
  Wrap(
    spacing: 8,
    runSpacing: 8,
    children: suggestions.map((profile) {
      final isBat = profile.type == 'bat';

      return ActionChip(
        avatar: Text(isBat ? '🦇' : '🐦'),
        label: Text(
          profile.commonName,
          overflow: TextOverflow.ellipsis,
        ),
        onPressed: () => onSuggestionTap(profile),
      );
    }).toList(),
  ),
],
        ],
      ),
    );
  }
}

const List<String> _defaultSuggestionNames = [
  'common blackbird',
  'european robin',
  'great tit',
  'blue tit',
  'common pipistrelle',
  'soprano pipistrelle',
  'serotine',
  'noctule',
];

class _AtlasMapCard extends StatelessWidget {
  final List<_AtlasMarker> markers;
  final _AtlasMarker? selectedMarker;
  final ValueChanged<_AtlasMarker> onMarkerTap;
  final ValueChanged<_AtlasMarker> onOpenReference;

  const _AtlasMapCard({
    required this.markers,
    required this.selectedMarker,
    required this.onMarkerTap,
    required this.onOpenReference,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 430,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: const LatLng(35.0, 15.0),
              initialZoom: 2.0,
              minZoom: 2.0,
              maxZoom: 7.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.drag |
                    InteractiveFlag.pinchZoom |
                    InteractiveFlag.doubleTapZoom |
                    InteractiveFlag.scrollWheelZoom,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.park_life_monitor',
              ),
              MarkerLayer(
                markers: markers.map((marker) {
                  return Marker(
                    point: marker.position,
                    width: 46,
                    height: 46,
                    child: GestureDetector(
                      onTap: () => onMarkerTap(marker),
                      child: _MapMarkerBubble(marker: marker),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),

          Positioned(
            left: 14,
            top: 14,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 9,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.92),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.public_rounded, size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Zoom and tap markers',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (selectedMarker != null)
            Positioned(
              left: 14,
              right: 14,
              bottom: 14,
              child: _SelectedMarkerCard(
                marker: selectedMarker!,
                onOpenReference: () => onOpenReference(selectedMarker!),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapMarkerBubble extends StatelessWidget {
  final _AtlasMarker marker;

  const _MapMarkerBubble({
    required this.marker,
  });

  @override
  Widget build(BuildContext context) {
    final isBat = marker.type == 'bat';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isBat ? const Color(0xFF352A66) : const Color(0xFFEAF6E8),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Center(
        child: Text(
          isBat ? '🦇' : '🐦',
          style: const TextStyle(fontSize: 23),
        ),
      ),
    );
  }
}

class _SelectedMarkerCard extends StatelessWidget {
  final _AtlasMarker marker;
  final VoidCallback onOpenReference;

  const _SelectedMarkerCard({
    required this.marker,
    required this.onOpenReference,
  });

  @override
  Widget build(BuildContext context) {
    final isBat = marker.type == 'bat';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isBat
                  ? const Color(0xFFE9E2FF)
                  : const Color(0xFFEAF6E8),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: Text(
                isBat ? '🦇' : '🐦',
                style: const TextStyle(fontSize: 28),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  marker.commonName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  marker.region,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  marker.habitat,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onOpenReference,
            child: const Text('Open'),
          ),
        ],
      ),
    );
  }
}

class _AtlasLegend extends StatelessWidget {
  const _AtlasLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.86),
        borderRadius: BorderRadius.circular(22),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Atlas guide',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Markers show broad reference regions for education, not exact live detections. Live detections from your Raspberry Pi are shown in Live, Diary and Discoveries.',
            style: TextStyle(
              color: Colors.black54,
              height: 1.35,
            ),
          ),
          SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _LegendChip(text: '🐦 Bird reference'),
              _LegendChip(text: '🦇 Bat reference'),
              _LegendChip(text: '🌍 Broad distribution'),
              _LegendChip(text: '🔎 Tap marker for profile'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendChip extends StatelessWidget {
  final String text;

  const _LegendChip({
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _ReferenceSpeciesCard extends StatelessWidget {
  final SpeciesProfile profile;
  final bool isLoading;
  final VoidCallback onTap;

  const _ReferenceSpeciesCard({
    required this.profile,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBat = profile.type == 'bat';

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.94),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isBat
                ? const Color(0xFFD6C9FF)
                : const Color(0xFFCBE8C9),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: isBat
                    ? const Color(0xFFE9E2FF)
                    : const Color(0xFFEAF6E8),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Center(
                child: Text(
                  isBat ? '🦇' : '🐦',
                  style: const TextStyle(fontSize: 30),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.commonName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    profile.scientificName,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(
                    profile.habitatNote,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.black54,
                      fontSize: 12,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isLoading)
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final String value;
  final String group;
  final ValueChanged<String> onTap;

  const _FilterChip({
    required this.label,
    required this.value,
    required this.group,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: value == group,
      onSelected: (_) => onTap(value),
    );
  }
}

class _AtlasMarker {
  final String commonName;
  final String scientificName;
  final String type;
  final LatLng position;
  final String region;
  final String regionGroup;
  final String habitat;

  const _AtlasMarker({
    required this.commonName,
    required this.scientificName,
    required this.type,
    required this.position,
    required this.region,
    required this.regionGroup,
    required this.habitat,
  });
}

const List<_AtlasMarker> _atlasMarkers = [
  // Birds: Common Blackbird
  _AtlasMarker(
    commonName: 'Common Blackbird',
    scientificName: 'Turdus merula',
    type: 'bird',
    position: LatLng(51.5, -0.1),
    region: 'United Kingdom and western Europe',
    regionGroup: 'europe',
    habitat: 'Woodland edges, gardens, parks and shrub-rich areas.',
  ),
  _AtlasMarker(
    commonName: 'Common Blackbird',
    scientificName: 'Turdus merula',
    type: 'bird',
    position: LatLng(52.5, 13.4),
    region: 'Central Europe',
    regionGroup: 'europe',
    habitat: 'Urban parks, hedges, gardens and woodland margins.',
  ),
  _AtlasMarker(
    commonName: 'Common Blackbird',
    scientificName: 'Turdus merula',
    type: 'bird',
    position: LatLng(41.9, 12.5),
    region: 'Southern Europe and the Mediterranean',
    regionGroup: 'europe',
    habitat: 'Gardens, orchards, parks and wooded urban areas.',
  ),
  _AtlasMarker(
    commonName: 'Common Blackbird',
    scientificName: 'Turdus merula',
    type: 'bird',
    position: LatLng(33.6, -7.6),
    region: 'North Africa',
    regionGroup: 'worldwide',
    habitat: 'Wooded gardens, irrigated areas and urban green spaces.',
  ),

  // Birds: European Robin
  _AtlasMarker(
    commonName: 'European Robin',
    scientificName: 'Erithacus rubecula',
    type: 'bird',
    position: LatLng(48.8, 2.3),
    region: 'Western Europe',
    regionGroup: 'europe',
    habitat: 'Woodlands, hedgerows, parks and gardens.',
  ),
  _AtlasMarker(
    commonName: 'European Robin',
    scientificName: 'Erithacus rubecula',
    type: 'bird',
    position: LatLng(40.4, -3.7),
    region: 'Iberian Peninsula',
    regionGroup: 'europe',
    habitat: 'Woodland, gardens, farmland edges and wintering areas.',
  ),
  _AtlasMarker(
    commonName: 'European Robin',
    scientificName: 'Erithacus rubecula',
    type: 'bird',
    position: LatLng(45.8, 16.0),
    region: 'Southeastern Europe',
    regionGroup: 'europe',
    habitat: 'Mixed woodland, parks, shrubs and garden vegetation.',
  ),

  // Birds: Great Tit
  _AtlasMarker(
    commonName: 'Great Tit',
    scientificName: 'Parus major',
    type: 'bird',
    position: LatLng(52.5, 13.4),
    region: 'Central Europe',
    regionGroup: 'europe',
    habitat: 'Trees, woodland, parks, gardens and nest boxes.',
  ),
  _AtlasMarker(
    commonName: 'Great Tit',
    scientificName: 'Parus major',
    type: 'bird',
    position: LatLng(59.3, 18.1),
    region: 'Northern Europe',
    regionGroup: 'europe',
    habitat: 'Mixed forest, garden trees and urban parks.',
  ),
  _AtlasMarker(
    commonName: 'Great Tit',
    scientificName: 'Parus major',
    type: 'bird',
    position: LatLng(39.9, 116.4),
    region: 'East Asia',
    regionGroup: 'worldwide',
    habitat: 'Woodland, farmland edges, city parks and gardens.',
  ),

  // Birds: Blue Tit
  _AtlasMarker(
    commonName: 'Blue Tit',
    scientificName: 'Cyanistes caeruleus',
    type: 'bird',
    position: LatLng(52.1, 5.2),
    region: 'Western and central Europe',
    regionGroup: 'europe',
    habitat: 'Deciduous woodland, gardens and urban parks.',
  ),
  _AtlasMarker(
    commonName: 'Blue Tit',
    scientificName: 'Cyanistes caeruleus',
    type: 'bird',
    position: LatLng(50.8, 4.4),
    region: 'Low Countries and western Europe',
    regionGroup: 'europe',
    habitat: 'Tree-rich gardens, parks and woodland edges.',
  ),

  // Birds: Eurasian Wren
  _AtlasMarker(
    commonName: 'Eurasian Wren',
    scientificName: 'Troglodytes troglodytes',
    type: 'bird',
    position: LatLng(54.0, -2.0),
    region: 'British Isles',
    regionGroup: 'europe',
    habitat: 'Dense shrubs, hedges, woodland floor and tangled vegetation.',
  ),
  _AtlasMarker(
    commonName: 'Eurasian Wren',
    scientificName: 'Troglodytes troglodytes',
    type: 'bird',
    position: LatLng(47.4, 8.5),
    region: 'Central Europe',
    regionGroup: 'europe',
    habitat: 'Moist woodland, dense undergrowth and garden shrubs.',
  ),

  // Birds: House Sparrow
  _AtlasMarker(
    commonName: 'House Sparrow',
    scientificName: 'Passer domesticus',
    type: 'bird',
    position: LatLng(51.5, -0.1),
    region: 'Urban Europe',
    regionGroup: 'worldwide',
    habitat: 'Urban areas, farms, gardens and buildings.',
  ),
  _AtlasMarker(
    commonName: 'House Sparrow',
    scientificName: 'Passer domesticus',
    type: 'bird',
    position: LatLng(28.6, 77.2),
    region: 'South Asia',
    regionGroup: 'worldwide',
    habitat: 'Human settlements, markets, homes and farmland.',
  ),
  _AtlasMarker(
    commonName: 'House Sparrow',
    scientificName: 'Passer domesticus',
    type: 'bird',
    position: LatLng(40.7, -74.0),
    region: 'North America introduced range',
    regionGroup: 'worldwide',
    habitat: 'Cities, suburbs, farms and parks.',
  ),
  _AtlasMarker(
    commonName: 'House Sparrow',
    scientificName: 'Passer domesticus',
    type: 'bird',
    position: LatLng(30.0, 31.2),
    region: 'North Africa and Middle East cities',
    regionGroup: 'worldwide',
    habitat: 'Buildings, streets, gardens and agricultural settlements.',
  ),

  // Birds: Wood Pigeon
  _AtlasMarker(
    commonName: 'Wood Pigeon',
    scientificName: 'Columba palumbus',
    type: 'bird',
    position: LatLng(41.9, 12.5),
    region: 'Southern Europe',
    regionGroup: 'europe',
    habitat: 'Woodland, farmland, parks and city trees.',
  ),
  _AtlasMarker(
    commonName: 'Wood Pigeon',
    scientificName: 'Columba palumbus',
    type: 'bird',
    position: LatLng(53.3, -6.3),
    region: 'Ireland and western Europe',
    regionGroup: 'europe',
    habitat: 'Parks, gardens, farmland and wooded areas.',
  ),

  // Birds: Carrion Crow
  _AtlasMarker(
    commonName: 'Carrion Crow',
    scientificName: 'Corvus corone',
    type: 'bird',
    position: LatLng(50.1, 8.7),
    region: 'Western and central Europe',
    regionGroup: 'europe',
    habitat: 'Open land, woodland edges, cities and farmland.',
  ),
  _AtlasMarker(
    commonName: 'Carrion Crow',
    scientificName: 'Corvus corone',
    type: 'bird',
    position: LatLng(35.7, 139.7),
    region: 'East Asian crow populations',
    regionGroup: 'worldwide',
    habitat: 'Urban areas, farmland, coastal edges and open land.',
  ),

  // Birds: Eurasian Magpie
  _AtlasMarker(
    commonName: 'Eurasian Magpie',
    scientificName: 'Pica pica',
    type: 'bird',
    position: LatLng(52.2, 21.0),
    region: 'Europe and temperate Asia',
    regionGroup: 'europe',
    habitat: 'Open woodland, cities, farmland and parks.',
  ),
  _AtlasMarker(
    commonName: 'Eurasian Magpie',
    scientificName: 'Pica pica',
    type: 'bird',
    position: LatLng(39.9, 116.4),
    region: 'East Asia',
    regionGroup: 'worldwide',
    habitat: 'Urban trees, farmland, parks and open countryside.',
  ),

  // Birds: Common Chaffinch
  _AtlasMarker(
    commonName: 'Common Chaffinch',
    scientificName: 'Fringilla coelebs',
    type: 'bird',
    position: LatLng(46.2, 6.1),
    region: 'Europe and western Asia',
    regionGroup: 'europe',
    habitat: 'Woodland, gardens, parks and tree-rich farmland.',
  ),
  _AtlasMarker(
    commonName: 'Common Chaffinch',
    scientificName: 'Fringilla coelebs',
    type: 'bird',
    position: LatLng(60.2, 24.9),
    region: 'Northern Europe breeding areas',
    regionGroup: 'europe',
    habitat: 'Coniferous and mixed forest, gardens and woodland edges.',
  ),

  // Birds: Common Cuckoo
  _AtlasMarker(
    commonName: 'Common Cuckoo',
    scientificName: 'Cuculus canorus',
    type: 'bird',
    position: LatLng(55.7, 12.6),
    region: 'European breeding range',
    regionGroup: 'europe',
    habitat: 'Open woodland, reedbeds, heathland and farmland edges.',
  ),
  _AtlasMarker(
    commonName: 'Common Cuckoo',
    scientificName: 'Cuculus canorus',
    type: 'bird',
    position: LatLng(-1.3, 36.8),
    region: 'African wintering region',
    regionGroup: 'worldwide',
    habitat: 'Seasonal habitats during migration and wintering.',
  ),

  // Birds: Common Raven
  _AtlasMarker(
    commonName: 'Common Raven',
    scientificName: 'Corvus corax',
    type: 'bird',
    position: LatLng(64.1, -21.9),
    region: 'North Atlantic and northern Europe',
    regionGroup: 'worldwide',
    habitat: 'Mountains, coasts, forests, open land and remote landscapes.',
  ),
  _AtlasMarker(
    commonName: 'Common Raven',
    scientificName: 'Corvus corax',
    type: 'bird',
    position: LatLng(51.0, -115.0),
    region: 'North America',
    regionGroup: 'worldwide',
    habitat: 'Forests, mountains, cliffs, coastlines and open country.',
  ),
  _AtlasMarker(
    commonName: 'Common Raven',
    scientificName: 'Corvus corax',
    type: 'bird',
    position: LatLng(43.2, 76.9),
    region: 'Central Asia',
    regionGroup: 'worldwide',
    habitat: 'Mountains, steppe, cliffs and open landscapes.',
  ),

  // Bats: Common Pipistrelle
  _AtlasMarker(
    commonName: 'Common Pipistrelle',
    scientificName: 'Pipistrellus pipistrellus',
    type: 'bat',
    position: LatLng(51.5, -0.1),
    region: 'United Kingdom and western Europe',
    regionGroup: 'europe',
    habitat: 'Urban parks, tree lines, gardens and water edges at dusk.',
  ),
  _AtlasMarker(
    commonName: 'Common Pipistrelle',
    scientificName: 'Pipistrellus pipistrellus',
    type: 'bat',
    position: LatLng(48.8, 2.3),
    region: 'Western Europe',
    regionGroup: 'europe',
    habitat: 'Buildings, riverside trees, parks and hedgerows.',
  ),
  _AtlasMarker(
    commonName: 'Common Pipistrelle',
    scientificName: 'Pipistrellus pipistrellus',
    type: 'bat',
    position: LatLng(40.4, -3.7),
    region: 'Southern Europe',
    regionGroup: 'europe',
    habitat: 'Warm urban edges, gardens, wetlands and tree lines.',
  ),

  // Bats: Soprano Pipistrelle
  _AtlasMarker(
    commonName: 'Soprano Pipistrelle',
    scientificName: 'Pipistrellus pygmaeus',
    type: 'bat',
    position: LatLng(55.9, -3.2),
    region: 'Northern and western Europe',
    regionGroup: 'europe',
    habitat: 'Wetlands, rivers, canals, lakes and woodland edges.',
  ),
  _AtlasMarker(
    commonName: 'Soprano Pipistrelle',
    scientificName: 'Pipistrellus pygmaeus',
    type: 'bat',
    position: LatLng(52.2, 21.0),
    region: 'Central and eastern Europe',
    regionGroup: 'europe',
    habitat: 'Water-side habitats, woodland edges and urban green corridors.',
  ),

  // Bats: Nathusius’ Pipistrelle
  _AtlasMarker(
    commonName: 'Nathusius’ Pipistrelle',
    scientificName: 'Pipistrellus nathusii',
    type: 'bat',
    position: LatLng(54.7, 25.3),
    region: 'Eastern and central Europe',
    regionGroup: 'europe',
    habitat: 'Wetlands, lakes, woodland edges and migration corridors.',
  ),
  _AtlasMarker(
    commonName: 'Nathusius’ Pipistrelle',
    scientificName: 'Pipistrellus nathusii',
    type: 'bat',
    position: LatLng(53.5, 10.0),
    region: 'Northern European migration route',
    regionGroup: 'europe',
    habitat: 'Coastal zones, wetlands and river systems.',
  ),

  // Bats: Daubenton’s Bat
  _AtlasMarker(
    commonName: 'Daubenton’s Bat',
    scientificName: 'Myotis daubentonii',
    type: 'bat',
    position: LatLng(52.2, 4.9),
    region: 'Western Europe',
    regionGroup: 'europe',
    habitat: 'Feeds low over rivers, lakes, canals and ponds.',
  ),
  _AtlasMarker(
    commonName: 'Daubenton’s Bat',
    scientificName: 'Myotis daubentonii',
    type: 'bat',
    position: LatLng(59.9, 10.7),
    region: 'Northern Europe',
    regionGroup: 'europe',
    habitat: 'Freshwater edges, forest lakes and sheltered rivers.',
  ),
  _AtlasMarker(
    commonName: 'Daubenton’s Bat',
    scientificName: 'Myotis daubentonii',
    type: 'bat',
    position: LatLng(48.2, 16.4),
    region: 'Central Europe',
    regionGroup: 'europe',
    habitat: 'Rivers, canals, lakes, bridges and tree roosts.',
  ),

  // Bats: Brown Long-eared Bat
  _AtlasMarker(
    commonName: 'Brown Long-eared Bat',
    scientificName: 'Plecotus auritus',
    type: 'bat',
    position: LatLng(47.4, 8.5),
    region: 'Central Europe',
    regionGroup: 'europe',
    habitat: 'Woodland, old buildings, tree cavities and quiet roosts.',
  ),
  _AtlasMarker(
    commonName: 'Brown Long-eared Bat',
    scientificName: 'Plecotus auritus',
    type: 'bat',
    position: LatLng(53.4, -2.9),
    region: 'British Isles',
    regionGroup: 'europe',
    habitat: 'Woodland, barns, lofts, old trees and sheltered gardens.',
  ),

  // Bats: Serotine
  _AtlasMarker(
    commonName: 'Serotine',
    scientificName: 'Eptesicus serotinus',
    type: 'bat',
    position: LatLng(50.8, 4.4),
    region: 'Western Europe',
    regionGroup: 'europe',
    habitat: 'Villages, towns, pasture edges, tree lines and open spaces.',
  ),
  _AtlasMarker(
    commonName: 'Serotine',
    scientificName: 'Eptesicus serotinus',
    type: 'bat',
    position: LatLng(44.4, 26.1),
    region: 'Southeastern Europe',
    regionGroup: 'europe',
    habitat: 'Open farmland, settlements, woodland edges and warm roosts.',
  ),

  // Bats: Leisler’s Bat
  _AtlasMarker(
    commonName: 'Leisler’s Bat',
    scientificName: 'Nyctalus leisleri',
    type: 'bat',
    position: LatLng(53.3, -6.3),
    region: 'Ireland and western Europe',
    regionGroup: 'europe',
    habitat: 'Woodland edges, open parkland, lakesides and tree roosts.',
  ),
  _AtlasMarker(
    commonName: 'Leisler’s Bat',
    scientificName: 'Nyctalus leisleri',
    type: 'bat',
    position: LatLng(45.5, 9.2),
    region: 'Southern and central Europe',
    regionGroup: 'europe',
    habitat: 'Forest edges, open habitats, parks and larger tree lines.',
  ),

  // Bats: Lesser Horseshoe Bat
  _AtlasMarker(
    commonName: 'Lesser Horseshoe Bat',
    scientificName: 'Rhinolophus hipposideros',
    type: 'bat',
    position: LatLng(45.8, 6.1),
    region: 'Western and southern Europe',
    regionGroup: 'europe',
    habitat: 'Caves, old buildings, woodland valleys and sheltered landscapes.',
  ),
  _AtlasMarker(
    commonName: 'Lesser Horseshoe Bat',
    scientificName: 'Rhinolophus hipposideros',
    type: 'bat',
    position: LatLng(42.7, 23.3),
    region: 'Balkan region',
    regionGroup: 'europe',
    habitat: 'Karst areas, caves, woodland, old buildings and valleys.',
  ),
];