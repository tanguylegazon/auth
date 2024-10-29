import "dart:developer";

import "package:flutter/material.dart";
import "package:logging/logging.dart";
import "package:photos/core/configuration.dart";
import "package:photos/core/constants.dart";
import "package:photos/db/files_db.dart";
import "package:photos/db/ml/db.dart";
import "package:photos/generated/l10n.dart";
import "package:photos/models/file/file.dart";
import "package:photos/models/file/file_type.dart";
import "package:photos/models/location_tag/location_tag.dart";
import "package:photos/models/ml/face/person.dart";
import "package:photos/models/search/hierarchical/album_filter.dart";
import "package:photos/models/search/hierarchical/contacts_filter.dart";
import "package:photos/models/search/hierarchical/face_filter.dart";
import "package:photos/models/search/hierarchical/file_type_filter.dart";
import "package:photos/models/search/hierarchical/hierarchical_search_filter.dart";
import "package:photos/models/search/hierarchical/location_filter.dart";
import "package:photos/models/search/hierarchical/magic_filter.dart";
import "package:photos/models/search/hierarchical/only_them_filter.dart";
import "package:photos/models/search/hierarchical/top_level_generic_filter.dart";
import "package:photos/service_locator.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/services/machine_learning/face_ml/face_filtering/face_filtering_constants.dart";
import "package:photos/services/machine_learning/face_ml/person/person_service.dart";
import "package:photos/services/magic_cache_service.dart";
import "package:photos/services/search_service.dart";
import "package:photos/ui/viewer/gallery/state/search_filter_data_provider.dart";
import "package:photos/utils/file_util.dart";

Future<List<EnteFile>> getFilteredFiles(
  List<HierarchicalSearchFilter> filters,
) async {
  final logger = Logger("HierarchicalSearchUtil");
  late final List<EnteFile> filteredFiles;
  final files = await SearchService.instance.getAllFilesForHierarchicalSearch();
  final resultsNeverComputedFilters = <HierarchicalSearchFilter>[];
  final ignoredCollections =
      CollectionsService.instance.archivedOrHiddenCollectionIds();

  logger.info("Getting filtered files for Filters: $filters");
  for (HierarchicalSearchFilter filter in filters) {
    if (filter is FaceFilter && filter.getMatchedUploadedIDs().isEmpty) {
      try {
        final stopwatch = Stopwatch()..start();

        if (filter.personId != null) {
          logger.info(
            "Fetching files for never fetched person ${filter.personId}",
          );
          final fileIDs = await MLDataDB.instance.getFileIDsOfPersonID(
            filter.personId!,
          );
          filter.matchedUploadedIDs.addAll(fileIDs);
        } else if (filter.clusterId != null) {
          logger.info(
            "Fetching files for never fetched cluster ${filter.clusterId}",
          );
          final fileIDs = await MLDataDB.instance.getFileIDsOfClusterID(
            filter.clusterId!,
          );
          filter.matchedUploadedIDs.addAll(fileIDs);
        }

        stopwatch.stop();
      } catch (e) {
        log("Error in face filter: $e");
      }
    } else if (filter is! FaceFilter &&
        filter.getMatchedUploadedIDs().isEmpty) {
      resultsNeverComputedFilters.add(filter);
    }
  }

  try {
    for (EnteFile file in files) {
      if (file.uploadedFileID == null || file.uploadedFileID == -1) {
        continue;
      }
      for (HierarchicalSearchFilter filter in resultsNeverComputedFilters) {
        if (filter.isMatch(file)) {
          filter.matchedUploadedIDs.add(file.uploadedFileID!);
        }
      }
    }

    Set<int> filteredUploadedIDs = {};
    for (int i = 0; i < filters.length; i++) {
      if (i == 0) {
        filteredUploadedIDs =
            filteredUploadedIDs.union(filters[i].getMatchedUploadedIDs());
      } else {
        filteredUploadedIDs = filteredUploadedIDs
            .intersection(filters[i].getMatchedUploadedIDs());
      }
    }

    filteredFiles = await FilesDB.instance.getFilesFromIDs(
      filteredUploadedIDs.toList(),
      dedupeByUploadId: true,
      collectionsToIgnore: ignoredCollections,
    );
  } catch (e) {
    Logger("HierarchicalSearchUtil").severe("Failed to get filtered files: $e");
  }

  return filteredFiles;
}

Future<void> curateFilters(
  SearchFilterDataProvider searchFilterDataProvider,
  List<EnteFile> files,
  BuildContext context,
) async {
  try {
    final albumFilters = await _curateAlbumFilters(files);
    final fileTypeFilters = _curateFileTypeFilters(files, context);
    final locationFilters = await _curateLocationFilters(
      files,
    );
    final contactsFilters = _curateContactsFilter(files);
    final faceFilters = await curateFaceFilters(files);
    final magicFilters = await curateMagicFilters(files);
    final onlyThemFilter = getOnlyThemFilter(
      searchFilterDataProvider,
      faceFilters,
    );

    searchFilterDataProvider.clearAndAddRecommendations(
      [
        ...onlyThemFilter,
        ...magicFilters,
        ...faceFilters,
        ...fileTypeFilters,
        ...contactsFilters,
        ...albumFilters,
        ...locationFilters,
      ],
    );
  } catch (e) {
    Logger("HierarchicalSearchUtil").severe("Failed to curate filters", e);
  }
}

List<OnlyThemFilter> getOnlyThemFilter(
  SearchFilterDataProvider searchFilterDataProvider,
  List<FaceFilter> recommendedFaceFilters,
) {
  final appliedFaceFilters =
      searchFilterDataProvider.appliedFilters.whereType<FaceFilter>().toList();
  if (appliedFaceFilters.isEmpty || appliedFaceFilters.length > 4) {
    return [];
  } else {
    final onlyThemFilter = OnlyThemFilter(
      faceFilters: appliedFaceFilters,
      faceFiltersToAvoid: recommendedFaceFilters,
      occurrence: kMostRelevantFilter,
    );
    return [onlyThemFilter];
  }
}

Future<List<AlbumFilter>> _curateAlbumFilters(
  List<EnteFile> files,
) async {
  final albumFilters = <AlbumFilter>[];
  final idToOccurrence = <int, int>{};
  final uploadedIDs = <int>[];
  for (EnteFile file in files) {
    if (file.uploadedFileID != null && file.uploadedFileID != -1) {
      uploadedIDs.add(file.uploadedFileID!);
    }
  }
  final collectionIDsOfFiles =
      await FilesDB.instance.getAllCollectionIDsOfFiles(uploadedIDs);

  for (int collectionID in collectionIDsOfFiles) {
    idToOccurrence[collectionID] = (idToOccurrence[collectionID] ?? 0) + 1;
  }

  for (int id in idToOccurrence.keys) {
    final collection = CollectionsService.instance.getCollectionByID(id);
    if (collection == null) {
      continue;
    }
    albumFilters.add(
      AlbumFilter(
        collectionID: id,
        albumName: collection.displayName,
        occurrence: idToOccurrence[id]!,
      ),
    );
  }

  return albumFilters;
}

List<FileTypeFilter> _curateFileTypeFilters(
  List<EnteFile> files,
  BuildContext context,
) {
  final fileTypeFilters = <FileTypeFilter>[];
  int photosCount = 0;
  int videosCount = 0;
  int livePhotosCount = 0;

  for (EnteFile file in files) {
    final id = file.uploadedFileID;
    if (id != null && id != -1) {
      if (file.fileType == FileType.image) {
        photosCount++;
      } else if (file.fileType == FileType.video) {
        videosCount++;
      } else if (file.fileType == FileType.livePhoto) {
        livePhotosCount++;
      }
    }
  }

  if (photosCount > 0) {
    fileTypeFilters.add(
      FileTypeFilter(
        fileType: FileType.image,
        typeName: S.of(context).photos,
        occurrence: photosCount,
      ),
    );
  }
  if (videosCount > 0) {
    fileTypeFilters.add(
      FileTypeFilter(
        fileType: FileType.video,
        typeName: S.of(context).videos,
        occurrence: videosCount,
      ),
    );
  }
  if (livePhotosCount > 0) {
    fileTypeFilters.add(
      FileTypeFilter(
        fileType: FileType.livePhoto,
        typeName: S.of(context).livePhotos,
        occurrence: livePhotosCount,
      ),
    );
  }

  return fileTypeFilters;
}

Future<List<LocationFilter>> _curateLocationFilters(
  List<EnteFile> files,
) async {
  final locationFilters = <LocationFilter>[];
  final locationTagToOccurrence =
      await locationService.getLocationTagsToOccurance(files);

  for (LocationTag locationTag in locationTagToOccurrence.keys) {
    locationFilters.add(
      LocationFilter(
        locationTag: locationTag,
        occurrence: locationTagToOccurrence[locationTag]!,
      ),
    );
  }

  return locationFilters;
}

List<ContactsFilter> _curateContactsFilter(
  List<EnteFile> files,
) {
  final contactsFilters = <ContactsFilter>[];
  final ownerIdToOccurrence = <int, int>{};

  for (EnteFile file in files) {
    if (file.ownerID == Configuration.instance.getUserID() ||
        file.uploadedFileID == null ||
        file.uploadedFileID == -1 ||
        file.ownerID == null) continue;
    ownerIdToOccurrence[file.ownerID!] =
        (ownerIdToOccurrence[file.ownerID] ?? 0) + 1;
  }

  for (int id in ownerIdToOccurrence.keys) {
    final user = CollectionsService.instance.getFileOwner(id, null);
    contactsFilters.add(
      ContactsFilter(
        user: user,
        occurrence: ownerIdToOccurrence[id]!,
      ),
    );
  }

  return contactsFilters;
}

Future<List<FaceFilter>> curateFaceFilters(
  List<EnteFile> files,
) async {
  try {
    final faceFilters = <FaceFilter>[];
    final Map<int, Set<String>> fileIdToClusterID =
        await MLDataDB.instance.getFileIdToClusterIds();
    final Map<String, PersonEntity> personIdToPerson =
        await PersonService.instance.getPersonsMap();
    final clusterIDToPersonID =
        await MLDataDB.instance.getClusterIDToPersonID();

    final Map<String, List<EnteFile>> clusterIdToFiles = {};
    final Map<String, List<EnteFile>> personIdToFiles = {};

    for (final f in files) {
      if (!fileIdToClusterID.containsKey(f.uploadedFileID ?? -1)) {
        continue;
      }
      final clusterIds = fileIdToClusterID[f.uploadedFileID ?? -1]!;
      for (final cluster in clusterIds) {
        final PersonEntity? p =
            personIdToPerson[clusterIDToPersonID[cluster] ?? ""];
        if (p != null) {
          if (personIdToFiles.containsKey(p.remoteID)) {
            personIdToFiles[p.remoteID]!.add(f);
          } else {
            personIdToFiles[p.remoteID] = [f];
          }
        } else {
          if (clusterIdToFiles.containsKey(cluster)) {
            clusterIdToFiles[cluster]!.add(f);
          } else {
            clusterIdToFiles[cluster] = [f];
          }
        }
      }
    }

    for (final personID in personIdToFiles.keys) {
      final files = personIdToFiles[personID]!;
      if (files.isEmpty) {
        continue;
      }
      final PersonEntity p = personIdToPerson[personID]!;
      if (p.data.isIgnored) continue;

      faceFilters.add(
        FaceFilter(
          personId: personID,
          clusterId: null,
          faceName: p.data.name,
          faceFile: files.first,
          occurrence: files.length,
        ),
      );
    }

    for (final clusterId in clusterIdToFiles.keys) {
      final files = clusterIdToFiles[clusterId]!;

      if (clusterIDToPersonID[clusterId] != null) {
        // This should not happen, means a faceID is assigned to multiple persons.
        Logger("hierarchical_search_util").severe(
          "`getAllFace`: Cluster $clusterId should not have person id ${clusterIDToPersonID[clusterId]}",
        );
      }
      if (files.length < kMinimumClusterSizeSearchResult) continue;

      faceFilters.add(
        FaceFilter(
          personId: null,
          clusterId: clusterId,
          faceName: null,
          faceFile: files.first,
          occurrence: files.length,
        ),
      );
    }

    return faceFilters;
  } catch (e, s) {
    Logger("hierarchical_search_util")
        .severe("Error in curating face filters", e, s);
    rethrow;
  }
}

Future<List<MagicFilter>> curateMagicFilters(List<EnteFile> files) async {
  final magicFilters = <MagicFilter>[];

  final magicCaches = await magicCacheService.getMagicCache();
  final filesUploadedFileIDs = filesToUploadedFileIDs(files);
  for (MagicCache magicCache in magicCaches) {
    final uploadedIDs = magicCache.fileUploadedIDs.toSet();
    final intersection = uploadedIDs.intersection(filesUploadedFileIDs);

    if (intersection.length > 3) {
      magicFilters.add(
        MagicFilter(
          filterName: magicCache.title,
          occurrence: intersection.length,
          matchedUploadedIDs: magicCache.fileUploadedIDs.toSet(),
        ),
      );
    }
  }

  return magicFilters;
}

Map<String, List<HierarchicalSearchFilter>> getFiltersForBottomSheet(
  SearchFilterDataProvider searchFilterDataProvider,
) {
  final onlyThemFilter = searchFilterDataProvider.appliedFilters
      .whereType<OnlyThemFilter>()
      .toList();
  onlyThemFilter.addAll(
    searchFilterDataProvider.recommendations.whereType<OnlyThemFilter>(),
  );

  final faceFilters =
      searchFilterDataProvider.appliedFilters.whereType<FaceFilter>().toList();
  faceFilters
      .addAll(searchFilterDataProvider.recommendations.whereType<FaceFilter>());

  final albumFilters =
      searchFilterDataProvider.appliedFilters.whereType<AlbumFilter>().toList();
  albumFilters.addAll(
    searchFilterDataProvider.recommendations.whereType<AlbumFilter>(),
  );

  final fileTypeFilters = searchFilterDataProvider.appliedFilters
      .whereType<FileTypeFilter>()
      .toList();
  fileTypeFilters.addAll(
    searchFilterDataProvider.recommendations.whereType<FileTypeFilter>(),
  );

  final locationFilters = searchFilterDataProvider.appliedFilters
      .whereType<LocationFilter>()
      .toList();
  locationFilters.addAll(
    searchFilterDataProvider.recommendations.whereType<LocationFilter>(),
  );

  final contactsFilters = searchFilterDataProvider.appliedFilters
      .whereType<ContactsFilter>()
      .toList();
  contactsFilters.addAll(
    searchFilterDataProvider.recommendations.whereType<ContactsFilter>(),
  );

  final magicFilters =
      searchFilterDataProvider.appliedFilters.whereType<MagicFilter>().toList();
  magicFilters.addAll(
    searchFilterDataProvider.recommendations.whereType<MagicFilter>(),
  );

  final topLevelGenericFilter = searchFilterDataProvider.appliedFilters
      .whereType<TopLevelGenericFilter>()
      .toList();

  return {
    "onlyThemFilter": onlyThemFilter,
    "faceFilters": faceFilters,
    "magicFilters": magicFilters,
    "locationFilters": locationFilters,
    "contactsFilters": contactsFilters,
    "albumFilters": albumFilters,
    "fileTypeFilters": fileTypeFilters,
    "topLevelGenericFilter": topLevelGenericFilter,
  };
}

List<HierarchicalSearchFilter> getRecommendedFiltersForAppBar(
  SearchFilterDataProvider searchFilterDataProvider,
) {
  final recommendations = searchFilterDataProvider.recommendations;

  final mostRelevantFilterFromEachType = <HierarchicalSearchFilter>[];
  int index = 0;
  final totalRecommendations = recommendations.length;

  // Add the most relevant filter from each type available in the first half of
  // the recommendations list
  for (final filter in recommendations) {
    if (mostRelevantFilterFromEachType
        .every((element) => element.runtimeType != filter.runtimeType)) {
      mostRelevantFilterFromEachType.add(filter);
    }

    if (mostRelevantFilterFromEachType.length ==
            (FilterTypeNames.values.length) ||
        (index + 1) / totalRecommendations > 0.5) {
      break;
    }
    index++;
  }

  final curatedRecommendations = <HierarchicalSearchFilter>[
    ...mostRelevantFilterFromEachType,
  ];
  for (HierarchicalSearchFilter recommendation in recommendations) {
    if (curatedRecommendations.length >= kMaxAppbarFilters) {
      break;
    }
    if (mostRelevantFilterFromEachType.every(
      (element) => !element.isSameFilter(recommendation),
    )) {
      curatedRecommendations.add(recommendation);
    }
  }

  final faceReccos = <FaceFilter>[];
  final magicReccos = <MagicFilter>[];
  final locationReccos = <LocationFilter>[];
  final contactsReccos = <ContactsFilter>[];
  final albumReccos = <AlbumFilter>[];
  final fileTypeReccos = <FileTypeFilter>[];
  final onlyThemFilter = <OnlyThemFilter>[];

  for (var recommendation in curatedRecommendations) {
    if (recommendation is OnlyThemFilter) {
      onlyThemFilter.add(recommendation);
    } else if (recommendation is FaceFilter) {
      faceReccos.add(recommendation);
    } else if (recommendation is MagicFilter) {
      magicReccos.add(recommendation);
    } else if (recommendation is LocationFilter) {
      locationReccos.add(recommendation);
    } else if (recommendation is ContactsFilter) {
      contactsReccos.add(recommendation);
    } else if (recommendation is AlbumFilter) {
      albumReccos.add(recommendation);
    } else if (recommendation is FileTypeFilter) {
      fileTypeReccos.add(recommendation);
    }
  }

  return [
    ...onlyThemFilter,
    ...faceReccos,
    ...magicReccos,
    ...locationReccos,
    ...contactsReccos,
    ...albumReccos,
    ...fileTypeReccos,
  ];
}
