enum SyncStage {
  idle,
  connectingGpodder,
  pushingActions,
  fetchingSubscriptions,
  fetchingEpisodeActions,
  fetchingFeed,
  offlineMode,
  completed,
  error,
}

class SyncStatusState {
  final bool isSyncing;
  final SyncStage stage;
  final String? currentTask;
  final String? activeFeedUrl;
  final String? error;
  final List<String> feedWarnings;

  const SyncStatusState({
    this.isSyncing = false,
    this.stage = SyncStage.idle,
    this.currentTask,
    this.activeFeedUrl,
    this.error,
    this.feedWarnings = const [],
  });

  bool get hasFeedWarnings => feedWarnings.isNotEmpty;

  SyncStatusState copyWith({
    bool? isSyncing,
    SyncStage? stage,
    String? currentTask,
    bool clearCurrentTask = false,
    String? activeFeedUrl,
    bool clearActiveFeedUrl = false,
    String? error,
    bool clearError = false,
    List<String>? feedWarnings,
  }) {
    return SyncStatusState(
      isSyncing: isSyncing ?? this.isSyncing,
      stage: stage ?? this.stage,
      currentTask: clearCurrentTask ? null : (currentTask ?? this.currentTask),
      activeFeedUrl: clearActiveFeedUrl ? null : (activeFeedUrl ?? this.activeFeedUrl),
      error: clearError ? null : (error ?? this.error),
      feedWarnings: feedWarnings ?? this.feedWarnings,
    );
  }
}
