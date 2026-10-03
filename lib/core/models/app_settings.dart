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
  itunes('Apple Podcasts (iTunes)'),
  podcastIndex('Podcast Index');

  final String label;
  const PreferredSearchProvider(this.label);
}

class AppSettings {
  // Theme & Appearance
  final AppThemeMode themeMode;
  final AppAccentColor accentColor;
  final DefaultLandingTab defaultLandingTab;
  final bool compactEpisodeRows;
  final EpisodeSortOrder defaultEpisodeSort;
  final bool hideCompletedEpisodes;

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
  final String podcastIndexApiKey;
  final String podcastIndexApiSecret;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.accentColor = AppAccentColor.purple,
    this.defaultLandingTab = DefaultLandingTab.catalog,
    this.compactEpisodeRows = false,
    this.defaultEpisodeSort = EpisodeSortOrder.newestFirst,
    this.hideCompletedEpisodes = false,
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
    this.podcastIndexApiKey = '',
    this.podcastIndexApiSecret = '',
  });

  AppSettings copyWith({
    AppThemeMode? themeMode,
    AppAccentColor? accentColor,
    DefaultLandingTab? defaultLandingTab,
    bool? compactEpisodeRows,
    EpisodeSortOrder? defaultEpisodeSort,
    bool? hideCompletedEpisodes,
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
    String? podcastIndexApiKey,
    String? podcastIndexApiSecret,
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
      defaultLandingTab: defaultLandingTab ?? this.defaultLandingTab,
      compactEpisodeRows: compactEpisodeRows ?? this.compactEpisodeRows,
      defaultEpisodeSort: defaultEpisodeSort ?? this.defaultEpisodeSort,
      hideCompletedEpisodes: hideCompletedEpisodes ?? this.hideCompletedEpisodes,
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
      podcastIndexApiKey: podcastIndexApiKey ?? this.podcastIndexApiKey,
      podcastIndexApiSecret: podcastIndexApiSecret ?? this.podcastIndexApiSecret,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'themeMode': themeMode.name,
      'accentColor': accentColor.name,
      'defaultLandingTab': defaultLandingTab.name,
      'compactEpisodeRows': compactEpisodeRows,
      'defaultEpisodeSort': defaultEpisodeSort.name,
      'hideCompletedEpisodes': hideCompletedEpisodes,
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
      'podcastIndexApiKey': podcastIndexApiKey,
      'podcastIndexApiSecret': podcastIndexApiSecret,
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

    return AppSettings(
      themeMode: parseTheme(json['themeMode']),
      accentColor: parseAccent(json['accentColor']),
      defaultLandingTab: parseTab(json['defaultLandingTab']),
      compactEpisodeRows: json['compactEpisodeRows'] as bool? ?? false,
      defaultEpisodeSort: parseSort(json['defaultEpisodeSort']),
      hideCompletedEpisodes: json['hideCompletedEpisodes'] as bool? ?? false,
      defaultPlaybackSpeed: (json['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1.0,
      autoAdvanceQueue: json['autoAdvanceQueue'] as bool? ?? true,
      markAsPlayedThresholdSeconds: json['markAsPlayedThresholdSeconds'] as int? ?? 60,
      audioFocusLossAction: parseFocus(json['audioFocusLossAction']),
      sleepTimerFadeOutSeconds: json['sleepTimerFadeOutSeconds'] as int? ?? 15,
      skipSilence: json['skipSilence'] as bool? ?? false,
      rewindDurationSeconds: json['rewindDurationSeconds'] as int? ?? 10,
      fastForwardDurationSeconds: json['fastForwardDurationSeconds'] as int? ?? 30,
      downloadWifiOnly: json['downloadWifiOnly'] as bool? ?? true,
      maxConcurrentDownloads: json['maxConcurrentDownloads'] as int? ?? 2,
      autoDeletePlayed: parseAutoDelete(json['autoDeletePlayed']),
      autoDeleteAfterPlay: json['autoDeleteAfterPlay'] as bool? ??
          (parseAutoDelete(json['autoDeletePlayed']) != AutoDeletePlayedPolicy.never),
      autoDownloadNewEpisodes: json['autoDownloadNewEpisodes'] as bool? ?? false,
      autoDownloadMaxPerShow: json['autoDownloadMaxPerShow'] as int? ?? 3,
      maxStorageQuotaGb: json['maxStorageQuotaGb'] as int? ?? 10,
      customDownloadPath: json['customDownloadPath'] as String?,
      syncOnLaunch: json['syncOnLaunch'] as bool? ?? true,
      periodicSyncIntervalMinutes: json['periodicSyncIntervalMinutes'] as int? ?? 180,
      syncConflictPolicy: parseSyncConflict(json['syncConflictPolicy']),
      deviceId: json['deviceId'] as String? ?? 'podcast_merlin_flutter',
      preferredSearchProvider: parseSearchProvider(json['preferredSearchProvider']),
      podcastIndexApiKey: json['podcastIndexApiKey'] as String? ?? '',
      podcastIndexApiSecret: json['podcastIndexApiSecret'] as String? ?? '',
    );
  }
}
