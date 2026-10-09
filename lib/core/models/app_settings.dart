import 'package:flutter/material.dart';

enum AppThemeMode {
  system,
  light,
  dark,
  amoled;

  String get label {
    switch (this) {
      case AppThemeMode.system:
        return 'System Default';
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.amoled:
        return 'AMOLED (True Black)';
    }
  }

  ThemeMode toThemeMode() {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
      case AppThemeMode.amoled:
        return ThemeMode.dark;
    }
  }
}

enum AppAccentColor {
  purple(Color(0xFF6750A4), 'Merlin Purple'),
  indigo(Color(0xFF3F51B5), 'Indigo'),
  blue(Color(0xFF1976D2), 'Deep Blue'),
  teal(Color(0xFF00796B), 'Teal'),
  amber(Color(0xFFFF8F00), 'Amber Gold'),
  coral(Color(0xFFE64A19), 'Coral');

  final Color color;
  final String label;
  const AppAccentColor(this.color, this.label);
}

enum DefaultLandingTab {
  catalog('Catalog'),
  episodes('Episodes'),
  downloads('Downloads'),
  discover('Discover');

  final String label;
  const DefaultLandingTab(this.label);
}

enum EpisodeSortOrder {
  newestFirst('Newest First', true),
  oldestFirst('Oldest First', false);

  final String label;
  final bool isDescending;
  const EpisodeSortOrder(this.label, this.isDescending);
}

enum AutoFocusLossAction {
  pauseAndResume('Pause & Resume'),
  duck('Duck Volume (50%)');

  final String label;
  const AutoFocusLossAction(this.label);
}

enum AutoDeletePlayedPolicy {
  never('Never'),
  immediately('Immediately when finished'),
  after24h('After 24 hours'),
  after7d('After 7 days');

  final String label;
  const AutoDeletePlayedPolicy(this.label);
}

enum SyncConflictPolicy {
  furthestPosition('Furthest Position Wins'),
  latestTimestamp('Latest Timestamp Wins'),
  serverAlways('Server Position Always Wins');

  final String label;
  const SyncConflictPolicy(this.label);
}

enum PreferredSearchProvider {
  itunes('Apple Podcasts (iTunes)');

  final String label;
  const PreferredSearchProvider(this.label);
}

enum DopamineVisualType {
  proceduralTunnel('Neon Warp Tunnel'),
  customVideo('Custom Video');

  final String label;
  const DopamineVisualType(this.label);
}

class DopamineCustomVideo {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final DateTime addedAt;

  const DopamineCustomVideo({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'sizeBytes': sizeBytes,
    'addedAt': addedAt.toIso8601String(),
  };

  factory DopamineCustomVideo.fromJson(Map<String, dynamic> json) => DopamineCustomVideo(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? 'Custom Video',
    path: json['path'] as String? ?? '',
    sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
    addedAt: DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now(),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DopamineCustomVideo && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

class AppSettings {
  // Theme & Appearance
  final AppThemeMode themeMode;
  final AppAccentColor accentColor;
  final bool useDynamicColor;
  final DefaultLandingTab defaultLandingTab;
  final bool compactEpisodeRows;
  final EpisodeSortOrder defaultEpisodeSort;
  final bool hideCompletedEpisodes;

  // Dopamine Mode
  final bool dopamineModeEnabled;
  final DopamineVisualType dopamineVisualType;
  final List<DopamineCustomVideo> dopamineCustomVideos;
  final String? selectedCustomVideoId;

  DopamineCustomVideo? get selectedCustomVideo {
    if (dopamineCustomVideos.isEmpty) return null;
    if (selectedCustomVideoId != null) {
      try {
        return dopamineCustomVideos.firstWhere((v) => v.id == selectedCustomVideoId);
      } catch (_) {}
    }
    return dopamineCustomVideos.first;
  }

  // Playback & Audio
  final double defaultPlaybackSpeed;
  final bool autoAdvanceQueue;
  final int markAsPlayedThresholdSeconds;
  final AutoFocusLossAction audioFocusLossAction;
  final int sleepTimerFadeOutSeconds;
  final bool skipSilence;
  final int rewindDurationSeconds;
  final int fastForwardDurationSeconds;

  // Downloads & Storage
  final bool downloadWifiOnly;
  final int maxConcurrentDownloads;
  final AutoDeletePlayedPolicy autoDeletePlayed;
  final bool autoDeleteAfterPlay;
  final bool autoDownloadNewEpisodes;
  final int autoDownloadMaxPerShow;

  bool get autoDownloadLastNEpisodes => autoDownloadNewEpisodes;
  int get autoDownloadEpisodesPerShow => autoDownloadMaxPerShow;

  final int maxStorageQuotaGb;
  final String? customDownloadPath;

  // Sync & Discovery
  final bool syncOnLaunch;
  final int periodicSyncIntervalMinutes;
  final SyncConflictPolicy syncConflictPolicy;
  final String deviceId;
  final PreferredSearchProvider preferredSearchProvider;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentColor = AppAccentColor.purple,
    this.useDynamicColor = true,
    this.defaultLandingTab = DefaultLandingTab.catalog,
    this.compactEpisodeRows = false,
    this.defaultEpisodeSort = EpisodeSortOrder.newestFirst,
    this.hideCompletedEpisodes = false,
    this.dopamineModeEnabled = false,
    this.dopamineVisualType = DopamineVisualType.proceduralTunnel,
    this.dopamineCustomVideos = const [],
    this.selectedCustomVideoId,
    this.defaultPlaybackSpeed = 1.0,
    this.autoAdvanceQueue = true,
    this.markAsPlayedThresholdSeconds = 60,
    this.audioFocusLossAction = AutoFocusLossAction.pauseAndResume,
    this.sleepTimerFadeOutSeconds = 15,
    this.skipSilence = false,
    this.rewindDurationSeconds = 10,
    this.fastForwardDurationSeconds = 30,
    this.downloadWifiOnly = true,
    this.maxConcurrentDownloads = 2,
    this.autoDeletePlayed = AutoDeletePlayedPolicy.immediately,
    this.autoDeleteAfterPlay = true,
    this.autoDownloadNewEpisodes = false,
    this.autoDownloadMaxPerShow = 3,
    this.maxStorageQuotaGb = 10,
    this.customDownloadPath,
    this.syncOnLaunch = true,
    this.periodicSyncIntervalMinutes = 180,
    this.syncConflictPolicy = SyncConflictPolicy.furthestPosition,
    this.deviceId = 'podcast_merlin_flutter',
    this.preferredSearchProvider = PreferredSearchProvider.itunes,
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppAccentColor? accentColor,
    bool? useDynamicColor,
    DefaultLandingTab? defaultLandingTab,
    bool? compactEpisodeRows,
    EpisodeSortOrder? defaultEpisodeSort,
    bool? hideCompletedEpisodes,
    bool? dopamineModeEnabled,
    DopamineVisualType? dopamineVisualType,
    List<DopamineCustomVideo>? dopamineCustomVideos,
    String? selectedCustomVideoId,
    bool clearSelectedCustomVideo = false,
    double? defaultPlaybackSpeed,
    bool? autoAdvanceQueue,
    int? markAsPlayedThresholdSeconds,
    AutoFocusLossAction? audioFocusLossAction,
    int? sleepTimerFadeOutSeconds,
    bool? skipSilence,
    int? rewindDurationSeconds,
    int? fastForwardDurationSeconds,
    bool? downloadWifiOnly,
    int? maxConcurrentDownloads,
    AutoDeletePlayedPolicy? autoDeletePlayed,
    bool? autoDeleteAfterPlay,
    bool? autoDownloadNewEpisodes,
    int? autoDownloadMaxPerShow,
    int? maxStorageQuotaGb,
    String? customDownloadPath,
    bool clearCustomDownloadPath = false,
    bool? syncOnLaunch,
    int? periodicSyncIntervalMinutes,
    SyncConflictPolicy? syncConflictPolicy,
    String? deviceId,
    PreferredSearchProvider? preferredSearchProvider,
  }) {
    AutoDeletePlayedPolicy resolvedPolicy = autoDeletePlayed ?? this.autoDeletePlayed;
    bool resolvedAutoDeleteAfterPlay = autoDeleteAfterPlay ?? this.autoDeleteAfterPlay;
    if (autoDeleteAfterPlay != null && autoDeletePlayed == null) {
      if (!autoDeleteAfterPlay) {
        resolvedPolicy = AutoDeletePlayedPolicy.never;
      } else if (resolvedPolicy == AutoDeletePlayedPolicy.never) {
        resolvedPolicy = AutoDeletePlayedPolicy.immediately;
      }
    } else if (autoDeletePlayed != null && autoDeleteAfterPlay == null) {
      resolvedAutoDeleteAfterPlay = autoDeletePlayed != AutoDeletePlayedPolicy.never;
    }

    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      accentColor: accentColor ?? this.accentColor,
      useDynamicColor: useDynamicColor ?? this.useDynamicColor,
      defaultLandingTab: defaultLandingTab ?? this.defaultLandingTab,
      compactEpisodeRows: compactEpisodeRows ?? this.compactEpisodeRows,
      defaultEpisodeSort: defaultEpisodeSort ?? this.defaultEpisodeSort,
      hideCompletedEpisodes: hideCompletedEpisodes ?? this.hideCompletedEpisodes,
      dopamineModeEnabled: dopamineModeEnabled ?? this.dopamineModeEnabled,
      dopamineVisualType: dopamineVisualType ?? this.dopamineVisualType,
      dopamineCustomVideos: dopamineCustomVideos ?? this.dopamineCustomVideos,
      selectedCustomVideoId: clearSelectedCustomVideo
          ? null
          : (selectedCustomVideoId ?? this.selectedCustomVideoId),
      defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
      autoAdvanceQueue: autoAdvanceQueue ?? this.autoAdvanceQueue,
      markAsPlayedThresholdSeconds: markAsPlayedThresholdSeconds ?? this.markAsPlayedThresholdSeconds,
      audioFocusLossAction: audioFocusLossAction ?? this.audioFocusLossAction,
      sleepTimerFadeOutSeconds: sleepTimerFadeOutSeconds ?? this.sleepTimerFadeOutSeconds,
      skipSilence: skipSilence ?? this.skipSilence,
      rewindDurationSeconds: rewindDurationSeconds ?? this.rewindDurationSeconds,
      fastForwardDurationSeconds: fastForwardDurationSeconds ?? this.fastForwardDurationSeconds,
      downloadWifiOnly: downloadWifiOnly ?? this.downloadWifiOnly,
      maxConcurrentDownloads: maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      autoDeletePlayed: resolvedPolicy,
      autoDeleteAfterPlay: resolvedAutoDeleteAfterPlay,
      autoDownloadNewEpisodes: autoDownloadNewEpisodes ?? this.autoDownloadNewEpisodes,
      autoDownloadMaxPerShow: autoDownloadMaxPerShow ?? this.autoDownloadMaxPerShow,
      maxStorageQuotaGb: maxStorageQuotaGb ?? this.maxStorageQuotaGb,
      customDownloadPath: clearCustomDownloadPath ? null : (customDownloadPath ?? this.customDownloadPath),
      syncOnLaunch: syncOnLaunch ?? this.syncOnLaunch,
      periodicSyncIntervalMinutes: periodicSyncIntervalMinutes ?? this.periodicSyncIntervalMinutes,
      syncConflictPolicy: syncConflictPolicy ?? this.syncConflictPolicy,
      deviceId: deviceId ?? this.deviceId,
      preferredSearchProvider: preferredSearchProvider ?? this.preferredSearchProvider,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'accentColor': accentColor.name,
      'useDynamicColor': useDynamicColor,
      'defaultLandingTab': defaultLandingTab.name,
      'compactEpisodeRows': compactEpisodeRows,
      'defaultEpisodeSort': defaultEpisodeSort.name,
      'hideCompletedEpisodes': hideCompletedEpisodes,
      'dopamineModeEnabled': dopamineModeEnabled,
      'dopamineVisualType': dopamineVisualType.name,
      'dopamineCustomVideos': dopamineCustomVideos.map((v) => v.toJson()).toList(),
      'selectedCustomVideoId': selectedCustomVideoId,
      'defaultPlaybackSpeed': defaultPlaybackSpeed,
      'autoAdvanceQueue': autoAdvanceQueue,
      'markAsPlayedThresholdSeconds': markAsPlayedThresholdSeconds,
      'audioFocusLossAction': audioFocusLossAction.name,
      'sleepTimerFadeOutSeconds': sleepTimerFadeOutSeconds,
      'skipSilence': skipSilence,
      'rewindDurationSeconds': rewindDurationSeconds,
      'fastForwardDurationSeconds': fastForwardDurationSeconds,
      'downloadWifiOnly': downloadWifiOnly,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'autoDeletePlayed': autoDeletePlayed.name,
      'autoDeleteAfterPlay': autoDeleteAfterPlay,
      'autoDownloadNewEpisodes': autoDownloadNewEpisodes,
      'autoDownloadMaxPerShow': autoDownloadMaxPerShow,
      'maxStorageQuotaGb': maxStorageQuotaGb,
      'customDownloadPath': customDownloadPath,
      'syncOnLaunch': syncOnLaunch,
      'periodicSyncIntervalMinutes': periodicSyncIntervalMinutes,
      'syncConflictPolicy': syncConflictPolicy.name,
      'deviceId': deviceId,
      'preferredSearchProvider': preferredSearchProvider.name,
    };
  }

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    AppThemeMode parseTheme(dynamic val) {
      if (val is String) {
        return AppThemeMode.values.firstWhere((e) => e.name == val, orElse: () => AppThemeMode.system);
      }
      return AppThemeMode.system;
    }

    AppAccentColor parseAccent(dynamic val) {
      if (val is String) {
        return AppAccentColor.values.firstWhere((e) => e.name == val, orElse: () => AppAccentColor.purple);
      }
      return AppAccentColor.purple;
    }

    DefaultLandingTab parseTab(dynamic val) {
      if (val is String) {
        return DefaultLandingTab.values.firstWhere((e) => e.name == val, orElse: () => DefaultLandingTab.catalog);
      }
      return DefaultLandingTab.catalog;
    }

    EpisodeSortOrder parseSort(dynamic val) {
      if (val is String) {
        return EpisodeSortOrder.values.firstWhere((e) => e.name == val, orElse: () => EpisodeSortOrder.newestFirst);
      }
      return EpisodeSortOrder.newestFirst;
    }

    AutoFocusLossAction parseFocus(dynamic val) {
      if (val is String) {
        return AutoFocusLossAction.values.firstWhere((e) => e.name == val, orElse: () => AutoFocusLossAction.pauseAndResume);
      }
      return AutoFocusLossAction.pauseAndResume;
    }

    AutoDeletePlayedPolicy parseAutoDelete(dynamic val) {
      if (val is String) {
        return AutoDeletePlayedPolicy.values.firstWhere((e) => e.name == val, orElse: () => AutoDeletePlayedPolicy.immediately);
      }
      return AutoDeletePlayedPolicy.immediately;
    }

    SyncConflictPolicy parseSyncConflict(dynamic val) {
      if (val is String) {
        return SyncConflictPolicy.values.firstWhere((e) => e.name == val, orElse: () => SyncConflictPolicy.furthestPosition);
      }
      return SyncConflictPolicy.furthestPosition;
    }

    PreferredSearchProvider parseSearchProvider(dynamic val) {
      if (val is String) {
        return PreferredSearchProvider.values.firstWhere((e) => e.name == val, orElse: () => PreferredSearchProvider.itunes);
      }
      return PreferredSearchProvider.itunes;
    }

    DopamineVisualType parseDopamineVisual(dynamic val) {
      if (val is String) {
        return DopamineVisualType.values.firstWhere(
          (e) => e.name == val,
          orElse: () => DopamineVisualType.proceduralTunnel,
        );
      }
      return DopamineVisualType.proceduralTunnel;
    }

    List<DopamineCustomVideo> parseCustomVideos(dynamic val) {
      if (val is List) {
        return val
            .whereType<Map<String, dynamic>>()
            .map((e) => DopamineCustomVideo.fromJson(e))
            .where((v) => v.id.isNotEmpty && v.path.isNotEmpty)
            .toList();
      }
      return const [];
    }

    bool parseBool(dynamic val, bool fallback) {
      if (val is bool) return val;
      if (val is String) {
        if (val.toLowerCase() == 'true') return true;
        if (val.toLowerCase() == 'false') return false;
      }
      return fallback;
    }

    int parseInt(dynamic val, int fallback) {
      if (val is int) return val;
      if (val is num) return val.toInt();
      if (val is String) {
        final parsed = int.tryParse(val);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    double parseDouble(dynamic val, double fallback) {
      if (val is double) return val;
      if (val is num) return val.toDouble();
      if (val is String) {
        final parsed = double.tryParse(val);
        if (parsed != null) return parsed;
      }
      return fallback;
    }

    String parseString(dynamic val, String fallback) {
      if (val is String) return val;
      return fallback;
    }

    String? parseNullableString(dynamic val) {
      if (val is String && val.isNotEmpty) return val;
      return null;
    }

    final autoDel = parseAutoDelete(json['autoDeletePlayed']);
    final defaultAutoDeleteAfterPlay = (autoDel != AutoDeletePlayedPolicy.never);

    return AppSettings(
      themeMode: parseTheme(json['themeMode']),
      accentColor: parseAccent(json['accentColor']),
      useDynamicColor: parseBool(json['useDynamicColor'], true),
      defaultLandingTab: parseTab(json['defaultLandingTab']),
      compactEpisodeRows: parseBool(json['compactEpisodeRows'], false),
      defaultEpisodeSort: parseSort(json['defaultEpisodeSort']),
      hideCompletedEpisodes: parseBool(json['hideCompletedEpisodes'], false),
      dopamineModeEnabled: parseBool(json['dopamineModeEnabled'], false),
      dopamineVisualType: parseDopamineVisual(json['dopamineVisualType'] ?? json['dopamineVideoSource']),
      dopamineCustomVideos: parseCustomVideos(json['dopamineCustomVideos']),
      selectedCustomVideoId: parseNullableString(json['selectedCustomVideoId']),
      defaultPlaybackSpeed: parseDouble(json['defaultPlaybackSpeed'], 1.0),
      autoAdvanceQueue: parseBool(json['autoAdvanceQueue'], true),
      markAsPlayedThresholdSeconds: parseInt(json['markAsPlayedThresholdSeconds'], 60),
      audioFocusLossAction: parseFocus(json['audioFocusLossAction']),
      sleepTimerFadeOutSeconds: parseInt(json['sleepTimerFadeOutSeconds'], 15),
      skipSilence: parseBool(json['skipSilence'], false),
      rewindDurationSeconds: parseInt(json['rewindDurationSeconds'], 10),
      fastForwardDurationSeconds: parseInt(json['fastForwardDurationSeconds'], 30),
      downloadWifiOnly: parseBool(json['downloadWifiOnly'], true),
      maxConcurrentDownloads: parseInt(json['maxConcurrentDownloads'], 2),
      autoDeletePlayed: autoDel,
      autoDeleteAfterPlay: parseBool(json['autoDeleteAfterPlay'], defaultAutoDeleteAfterPlay),
      autoDownloadNewEpisodes: parseBool(json['autoDownloadNewEpisodes'], false),
      autoDownloadMaxPerShow: parseInt(json['autoDownloadMaxPerShow'], 3),
      maxStorageQuotaGb: parseInt(json['maxStorageQuotaGb'], 10),
      customDownloadPath: parseNullableString(json['customDownloadPath']),
      syncOnLaunch: parseBool(json['syncOnLaunch'], true),
      periodicSyncIntervalMinutes: parseInt(json['periodicSyncIntervalMinutes'], 180),
      syncConflictPolicy: parseSyncConflict(json['syncConflictPolicy']),
      deviceId: parseString(json['deviceId'], 'podcast_merlin_flutter'),
      preferredSearchProvider: parseSearchProvider(json['preferredSearchProvider']),
    );
  }
}
