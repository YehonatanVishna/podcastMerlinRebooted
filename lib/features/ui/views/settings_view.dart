import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/services/image_cache_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../sync/opml_ui_helper.dart';
import '../../sync/secure_storage_service.dart';
import '../widgets/sync_error_banner.dart';
import '../../../main.dart';

class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  final _serverController = TextEditingController();
  final _userController = TextEditingController();
  final _passwordController = TextEditingController();
  final _podcastIndexKeyController = TextEditingController();
  final _podcastIndexSecretController = TextEditingController();
  final _deviceIdController = TextEditingController();

  bool _isLoading = true;
  bool _isTesting = false;
  bool _obscurePodcastIndexSecret = true;
  String? _statusMessage;
  bool _isSuccessStatus = false;
  int? _imageCacheBytes;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  Future<void> _loadSavedCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final settings = ref.read(appSettingsProvider);

    _serverController.text = await storage.read(SecureStorageService.keyServerUrl) ?? '';
    _userController.text = await storage.read(SecureStorageService.keyUsername) ?? '';
    _passwordController.text = await storage.read(SecureStorageService.keyPassword) ?? '';
    _podcastIndexKeyController.text = settings.podcastIndexApiKey;
    _podcastIndexSecretController.text = settings.podcastIndexApiSecret;
    _deviceIdController.text = settings.deviceId;

    _refreshImageCacheSize();
    ref.invalidate(downloadStorageUsageBytesProvider);
    ref.invalidate(downloadedEpisodesCountProvider);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _refreshImageCacheSize() async {
    try {
      final bytes = await ImageCacheService.getCacheSizeBytes();
      if (mounted) {
        setState(() => _imageCacheBytes = bytes);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _imageCacheBytes = -1);
      }
    }
  }

  @override
  void dispose() {
    _serverController.dispose();
    _userController.dispose();
    _passwordController.dispose();
    _podcastIndexKeyController.dispose();
    _podcastIndexSecretController.dispose();
    _deviceIdController.dispose();
    super.dispose();
  }

  Future<void> _saveCredentials() async {
    final storage = ref.read(secureStorageProvider);
    final oldServer = await storage.read(SecureStorageService.keyServerUrl) ?? '';
    final oldUser = await storage.read(SecureStorageService.keyUsername) ?? '';
    final newServer = _serverController.text.trim();
    final newUser = _userController.text.trim();

    if (oldServer != newServer || oldUser != newUser) {
      await storage.delete(SecureStorageService.keyLastSubscriptionTimestamp);
      await storage.delete(SecureStorageService.keyLastActionTimestamp);
    }

    await storage.write(SecureStorageService.keyServerUrl, newServer);
    await storage.write(SecureStorageService.keyUsername, newUser);
    await storage.write(SecureStorageService.keyPassword, _passwordController.text.trim());

    final settingsNotifier = ref.read(appSettingsProvider.notifier);
    settingsNotifier.setPodcastIndexCredentials(
      _podcastIndexKeyController.text.trim(),
      _podcastIndexSecretController.text.trim(),
    );
    if (_deviceIdController.text.trim().isNotEmpty) {
      settingsNotifier.setDeviceId(_deviceIdController.text.trim());
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved successfully')),
      );
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _isTesting = true;
      _statusMessage = null;
      _isSuccessStatus = false;
    });

    final apiClient = ref.read(apiClientProvider);
    final errorDetail = await apiClient.testConnectionDetailed(
      serverUrl: _serverController.text.trim(),
      username: _userController.text.trim(),
      password: _passwordController.text.trim(),
    );

    if (!mounted) return;
    setState(() {
      _isTesting = false;
      _isSuccessStatus = errorDetail == null;
      _statusMessage = errorDetail == null
          ? 'Connected successfully to Nextcloud gPodder!'
          : 'Connection failed: $errorDetail';
    });
  }

  Future<void> _exportOpml() async {
    await OpmlUiHelper.exportOpml(context, ref);
  }

  void _showImportOpmlDialog() {
    OpmlUiHelper.importOpml(context, ref);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final syncStatus = ref.watch(syncStatusNotifierProvider);
    final settings = ref.watch(appSettingsProvider);
    final settingsNotifier = ref.read(appSettingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: 'Save Settings',
            onPressed: _saveCredentials,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header Logo
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: SvgPicture.asset(
                          'assets/images/logo.svg',
                          width: 80,
                          height: 80,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Podcast Merlin',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Configurable Podcast Client • v2.0.0',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (syncStatus.error != null && !syncStatus.isSyncing) ...[
                  SyncErrorBanner(
                    title: 'Sync Failed',
                    summary: 'Some sync tasks failed',
                    errorMessage: syncStatus.error!,
                    onDismiss: () => ref.read(syncStatusNotifierProvider.notifier).clearError(),
                    onRetry: () => ref.read(podcastsNotifierProvider.notifier).refreshAll(),
                  ),
                  const SizedBox(height: 16),
                ],

                // 1. DISCOVERY & OPML
                _buildSectionHeader('Discovery & OPML', Icons.explore_outlined),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<PreferredSearchProvider>(
                          isExpanded: true,
                          initialValue: PreferredSearchProvider.values.contains(settings.preferredSearchProvider)
                              ? settings.preferredSearchProvider
                              : PreferredSearchProvider.itunes,
                          decoration: const InputDecoration(
                            labelText: 'Preferred Search Provider',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.travel_explore),
                          ),
                          items: PreferredSearchProvider.values.map((p) {
                            return DropdownMenuItem(value: p, child: Text(p.label));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setPreferredSearchProvider(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _podcastIndexKeyController,
                          decoration: const InputDecoration(
                            labelText: 'Custom Podcast Index API Key (Optional)',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.vpn_key_outlined),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _podcastIndexSecretController,
                          obscureText: _obscurePodcastIndexSecret,
                          decoration: InputDecoration(
                            labelText: 'Custom Podcast Index API Secret (Optional)',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.password_outlined),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePodcastIndexSecret
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                              ),
                              tooltip: _obscurePodcastIndexSecret ? 'Show secret' : 'Hide secret',
                              onPressed: () {
                                setState(() {
                                  _obscurePodcastIndexSecret = !_obscurePodcastIndexSecret;
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text(
                          'OPML Management',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Import subscriptions from or export them to an OPML 2.0 file, compatible with antennaPod, Pocket Casts, and Apple Podcasts.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                        ),
                        const SizedBox(height: 12),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 500;
                            final exportBtn = OutlinedButton.icon(
                              icon: const Icon(Icons.file_upload_outlined),
                              label: const Text('Export OPML'),
                              onPressed: _exportOpml,
                            );
                            final importBtn = ElevatedButton.icon(
                              icon: const Icon(Icons.file_download_outlined),
                              label: const Text('Import OPML'),
                              onPressed: _showImportOpmlDialog,
                            );

                            if (isNarrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  exportBtn,
                                  const SizedBox(height: 12),
                                  importBtn,
                                ],
                              );
                            }

                            return Row(
                              children: [
                                Expanded(child: exportBtn),
                                const SizedBox(width: 16),
                                Expanded(child: importBtn),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 2. DOWNLOADS & STORAGE
                _buildSectionHeader('Downloads & Storage', Icons.download_for_offline_outlined),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDownloadsStorageCard(context),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        // Image cache row
                        Row(
                          children: [
                            const Icon(Icons.image_outlined, size: 28),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Artwork Image Cache',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    _imageCacheBytes == null
                                        ? 'Calculating...'
                                        : (_imageCacheBytes! < 0
                                            ? 'Error reading cache'
                                            : '${_formatBytes(_imageCacheBytes!)} cached artwork'),
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: _imageCacheBytes != null && _imageCacheBytes! < 0 ? Colors.red : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OutlinedButton.icon(
                              icon: const Icon(Icons.delete_outline, size: 16),
                              label: const Text('Clear'),
                              onPressed: () async {
                                await ImageCacheService.clearCache();
                                await _refreshImageCacheSize();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Image cache cleared')),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: const [1, 2, 3, 4, 5].contains(settings.maxConcurrentDownloads)
                              ? settings.maxConcurrentDownloads
                              : 2,
                          decoration: const InputDecoration(
                            labelText: 'Max Concurrent Downloads',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.speed),
                          ),
                          items: const [1, 2, 3, 4, 5]
                              .map((c) => DropdownMenuItem(value: c, child: Text('$c simultaneous downloads')))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setMaxConcurrentDownloads(val);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-Delete Episode After Play'),
                          subtitle: const Text('Automatically delete downloaded episode when playback finishes'),
                          value: settings.autoDeleteAfterPlay,
                          onChanged: (val) => settingsNotifier.setAutoDeleteAfterPlay(val),
                        ),
                        if (settings.autoDeleteAfterPlay) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<AutoDeletePlayedPolicy>(
                            isExpanded: true,
                            initialValue: AutoDeletePlayedPolicy.values.contains(settings.autoDeletePlayed)
                                ? settings.autoDeletePlayed
                                : AutoDeletePlayedPolicy.immediately,
                            decoration: const InputDecoration(
                              labelText: 'Auto-Delete Cleanup Schedule',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.auto_delete_outlined),
                            ),
                            items: AutoDeletePlayedPolicy.values.map((pol) {
                              return DropdownMenuItem(value: pol, child: Text(pol.label));
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) settingsNotifier.setAutoDeletePlayed(val);
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: const [0, 2, 5, 10, 20].contains(settings.maxStorageQuotaGb)
                              ? settings.maxStorageQuotaGb
                              : 10,
                          decoration: const InputDecoration(
                            labelText: 'Download Storage Quota',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sd_storage_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Unlimited')),
                            DropdownMenuItem(value: 2, child: Text('2 GB')),
                            DropdownMenuItem(value: 5, child: Text('5 GB')),
                            DropdownMenuItem(value: 10, child: Text('10 GB (Default)')),
                            DropdownMenuItem(value: 20, child: Text('20 GB')),
                          ],
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setMaxStorageQuotaGb(val);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Download on Wi-Fi Only'),
                          subtitle: const Text('Prevent large audio file downloads when connected to mobile data'),
                          value: settings.downloadWifiOnly,
                          onChanged: (val) => settingsNotifier.setDownloadWifiOnly(val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-Download Last Episodes'),
                          subtitle: const Text('Automatically download the last N episodes of every subscription'),
                          value: settings.autoDownloadNewEpisodes,
                          onChanged: (val) => settingsNotifier.setAutoDownloadNewEpisodes(val),
                        ),
                        if (settings.autoDownloadNewEpisodes) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<int>(
                            isExpanded: true,
                            initialValue: const [1, 2, 3, 5, 10].contains(settings.autoDownloadMaxPerShow)
                                ? settings.autoDownloadMaxPerShow
                                : 3,
                            decoration: const InputDecoration(
                              labelText: 'Episodes Per Subscription to Keep Downloaded',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.downloading_outlined),
                            ),
                            items: const [
                              DropdownMenuItem(value: 1, child: Text('Latest 1 episode')),
                              DropdownMenuItem(value: 2, child: Text('Latest 2 episodes')),
                              DropdownMenuItem(value: 3, child: Text('Latest 3 episodes (Default)')),
                              DropdownMenuItem(value: 5, child: Text('Latest 5 episodes')),
                              DropdownMenuItem(value: 10, child: Text('Latest 10 episodes')),
                            ],
                            onChanged: (val) {
                              if (val != null) settingsNotifier.setAutoDownloadMaxPerShow(val);
                            },
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final count = await ref.read(episodeDownloadServiceProvider).autoDownloadSubscriptions(
                                maxEpisodesPerSubscription: settings.autoDownloadMaxPerShow,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      count > 0
                                          ? 'Queued $count episode${count == 1 ? '' : 's'} for download across subscriptions'
                                          : 'All subscription episodes are already up to date',
                                    ),
                                  ),
                                );
                              }
                            },
                            icon: const Icon(Icons.sync),
                            label: const Text('Download Latest Episodes Now'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 3. APPEARANCE & INTERFACE
                _buildSectionHeader('Appearance & Interface', Icons.palette_outlined),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('App Theme', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: AppThemeMode.values.map((mode) {
                            final isSelected = settings.themeMode == mode;
                            return ChoiceChip(
                              label: Text(mode.label),
                              selected: isSelected,
                              onSelected: (_) => settingsNotifier.setThemeMode(mode),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 8),
                        Text('Accent Color', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: AppAccentColor.values.map((accent) {
                            final isSelected = settings.accentColor == accent;
                            return InkWell(
                              onTap: () => settingsNotifier.setAccentColor(accent),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected ? Theme.of(context).colorScheme.primary : Colors.transparent,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: accent.color,
                                  child: isSelected ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.color_lens_outlined),
                          title: const Text('Use system theme color'),
                          subtitle: const Text(
                            'Adapts brand and accent colors to your OS system theme or wallpaper (Android 12+, Windows, macOS, Linux).',
                          ),
                          value: ref.watch(themeSettingsProvider).useDynamicColor,
                          onChanged: (val) {
                            ref.read(themeSettingsProvider.notifier).setUseDynamicColor(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        DropdownButtonFormField<DefaultLandingTab>(
                          isExpanded: true,
                          initialValue: DefaultLandingTab.values.contains(settings.defaultLandingTab)
                              ? settings.defaultLandingTab
                              : DefaultLandingTab.catalog,
                          decoration: const InputDecoration(
                            labelText: 'Default Startup Tab',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.tab_outlined),
                          ),
                          items: DefaultLandingTab.values.map((tab) {
                            return DropdownMenuItem(value: tab, child: Text(tab.label));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setDefaultLandingTab(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<EpisodeSortOrder>(
                          isExpanded: true,
                          initialValue: EpisodeSortOrder.values.contains(settings.defaultEpisodeSort)
                              ? settings.defaultEpisodeSort
                              : EpisodeSortOrder.newestFirst,
                          decoration: const InputDecoration(
                            labelText: 'Default Episode Sort Order',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.sort_rounded),
                          ),
                          items: EpisodeSortOrder.values.map((sort) {
                            return DropdownMenuItem(value: sort, child: Text(sort.label));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setDefaultEpisodeSort(val);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Compact Episode Rows'),
                          subtitle: const Text('Fit more episodes on screen with dense row layouts'),
                          value: settings.compactEpisodeRows,
                          onChanged: (val) => settingsNotifier.setCompactEpisodeRows(val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Hide Completed Episodes'),
                          subtitle: const Text('Automatically filter out finished episodes across lists'),
                          value: settings.hideCompletedEpisodes,
                          onChanged: (val) => settingsNotifier.setHideCompletedEpisodes(val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 4. PLAYBACK & AUDIO CONTROLS
                _buildSectionHeader('Playback & Controls', Icons.play_circle_outline),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Default Playback Speed: ${settings.defaultPlaybackSpeed.toStringAsFixed(1)}x',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Slider(
                          value: settings.defaultPlaybackSpeed,
                          min: 0.5,
                          max: 3.0,
                          divisions: 25,
                          label: '${settings.defaultPlaybackSpeed.toStringAsFixed(1)}x',
                          onChanged: (val) {
                            settingsNotifier.setDefaultPlaybackSpeed(double.parse(val.toStringAsFixed(1)));
                          },
                        ),
                        const SizedBox(height: 8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isNarrow = constraints.maxWidth < 500;
                            final rewindDropdown = DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: const [5, 10, 15, 30, 45, 60].contains(settings.rewindDurationSeconds)
                                  ? settings.rewindDurationSeconds
                                  : 10,
                              decoration: const InputDecoration(
                                labelText: 'Rewind Interval',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.replay),
                              ),
                              items: const [5, 10, 15, 30, 45, 60]
                                  .map((s) => DropdownMenuItem(value: s, child: Text('$s seconds')))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) settingsNotifier.setSeekDurations(rewind: val);
                              },
                            );

                            final fastForwardDropdown = DropdownButtonFormField<int>(
                              isExpanded: true,
                              initialValue: const [5, 10, 15, 30, 45, 60].contains(settings.fastForwardDurationSeconds)
                                  ? settings.fastForwardDurationSeconds
                                  : 30,
                              decoration: const InputDecoration(
                                labelText: 'Fast Forward Interval',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.forward),
                              ),
                              items: const [5, 10, 15, 30, 45, 60]
                                  .map((s) => DropdownMenuItem(value: s, child: Text('$s seconds')))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) settingsNotifier.setSeekDurations(fastForward: val);
                              },
                            );

                            if (isNarrow) {
                              return Column(
                                children: [
                                  rewindDropdown,
                                  const SizedBox(height: 12),
                                  fastForwardDropdown,
                                ],
                              );
                            }
                            return Row(
                              children: [
                                Expanded(child: rewindDropdown),
                                const SizedBox(width: 12),
                                Expanded(child: fastForwardDropdown),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: const [0, 30, 60, 90, 120].contains(settings.markAsPlayedThresholdSeconds)
                              ? settings.markAsPlayedThresholdSeconds
                              : 60,
                          decoration: const InputDecoration(
                            labelText: 'Mark-as-Played Outro Buffer',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.check_circle_outline),
                            helperText: 'Episode marks as finished when remaining time drops below this buffer',
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('At very end (0s)')),
                            DropdownMenuItem(value: 30, child: Text('30 seconds before end')),
                            DropdownMenuItem(value: 60, child: Text('60 seconds before end (Default)')),
                            DropdownMenuItem(value: 90, child: Text('90 seconds before end')),
                            DropdownMenuItem(value: 120, child: Text('2 minutes before end')),
                          ],
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setMarkAsPlayedThresholdSeconds(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<AutoFocusLossAction>(
                          isExpanded: true,
                          initialValue: AutoFocusLossAction.values.contains(settings.audioFocusLossAction)
                              ? settings.audioFocusLossAction
                              : AutoFocusLossAction.pauseAndResume,
                          decoration: const InputDecoration(
                            labelText: 'Audio Focus Loss Action',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.volume_down_outlined),
                            helperText: 'Behavior when another app or notification plays sound',
                          ),
                          items: AutoFocusLossAction.values.map((act) {
                            return DropdownMenuItem(value: act, child: Text(act.label));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setAutoFocusLossAction(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: const [0, 10, 15, 30].contains(settings.sleepTimerFadeOutSeconds)
                              ? settings.sleepTimerFadeOutSeconds
                              : 15,
                          decoration: const InputDecoration(
                            labelText: 'Sleep Timer Fade-Out',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.bedtime_outlined),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Disabled (Instant Pause)')),
                            DropdownMenuItem(value: 10, child: Text('10 seconds fade')),
                            DropdownMenuItem(value: 15, child: Text('15 seconds fade (Default)')),
                            DropdownMenuItem(value: 30, child: Text('30 seconds fade')),
                          ],
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setSleepTimerFadeOutSeconds(val);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Continuous Playback (Auto-play Next)'),
                          subtitle: const Text('Automatically start next queued episode when current one ends'),
                          value: settings.autoAdvanceQueue,
                          onChanged: (val) => settingsNotifier.setAutoAdvanceQueue(val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Skip Silence'),
                          subtitle: const Text('Trim conversational pauses dynamically without pitch change'),
                          value: settings.skipSilence,
                          onChanged: (val) => settingsNotifier.setSkipSilence(val),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Auto-Delete Episode After Play'),
                          subtitle: const Text('Automatically remove downloaded audio file when playback completes'),
                          value: settings.autoDeleteAfterPlay,
                          onChanged: (val) => settingsNotifier.setAutoDeleteAfterPlay(val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 5. SYNCHRONIZATION & STORAGE
                _buildSectionHeader('Synchronization (Nextcloud / gPodder)', Icons.sync),
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListenableBuilder(
                          listenable: _serverController,
                          builder: (context, _) {
                            final isLocal = _serverController.text.trim().isEmpty;
                            return Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isLocal
                                        ? 'Standalone Local Mode (No server required)'
                                        : 'Nextcloud gPodder Sync Mode',
                                    style: TextStyle(
                                      color: isLocal
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _serverController,
                          decoration: const InputDecoration(
                            labelText: 'Nextcloud Server URL (Optional for Local Mode)',
                            hintText: 'https://nextcloud.example.com',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.cloud),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _userController,
                          decoration: const InputDecoration(
                            labelText: 'Username',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.person),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'App Password or Password',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.lock),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deviceIdController,
                          decoration: const InputDecoration(
                            labelText: 'gPodder Device Identifier',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.devices),
                            helperText: 'Unique client device identifier registered with Nextcloud gPodder',
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (_statusMessage != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _isSuccessStatus
                                  ? Colors.green.withValues(alpha: 0.15)
                                  : Colors.red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _isSuccessStatus ? Colors.green : Colors.red,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  _isSuccessStatus ? Icons.check_circle_outline : Icons.error_outline,
                                  color: _isSuccessStatus ? Colors.green[800] : Colors.red[800],
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _statusMessage!,
                                    style: TextStyle(
                                      color: _isSuccessStatus ? Colors.green[900] : Colors.red[900],
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Consumer(
                          builder: (context, ref, child) {
                            return ListenableBuilder(
                              listenable: Listenable.merge([_serverController, _userController]),
                              builder: (context, _) {
                                final syncState = ref.watch(syncStatusNotifierProvider);
                                final isSyncing = syncState.isSyncing;
                                final isConfigured = _serverController.text.trim().isNotEmpty &&
                                    _userController.text.trim().isNotEmpty;

                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (isSyncing) ...[
                                      Row(
                                        children: [
                                          const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              syncState.currentTask ?? (isConfigured ? 'Syncing with gPodder...' : 'Refreshing local feeds...'),
                                              style: Theme.of(context).textTheme.bodySmall,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                    ],
                                    FilledButton.icon(
                                      icon: isSyncing
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                            )
                                          : const Icon(Icons.sync),
                                      label: Text(
                                        isSyncing
                                            ? 'Processing...'
                                            : (isConfigured ? 'Save & Sync with gPodder' : 'Refresh Local Feeds (Local Mode)'),
                                      ),
                                      onPressed: isSyncing
                                          ? null
                                          : () async {
                                              await _saveCredentials();
                                              ref.read(podcastsNotifierProvider.notifier).refreshAll();
                                            },
                                    ),
                                    if (isConfigured) ...[
                                      const SizedBox(height: 8),
                                      TextButton.icon(
                                        icon: const Icon(Icons.refresh),
                                        label: const Text('Force Full Re-sync (Retrieve all played positions)'),
                                        onPressed: isSyncing
                                            ? null
                                            : () async {
                                                await _saveCredentials();
                                                ref.read(podcastsNotifierProvider.notifier).refreshAll(forceFullResync: true);
                                              },
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: _isTesting
                                                  ? const SizedBox(
                                                      width: 18,
                                                      height: 18,
                                                      child: CircularProgressIndicator(strokeWidth: 2),
                                                    )
                                                  : const Icon(Icons.cloud_done),
                                              label: const Text('Test Connection'),
                                              onPressed: _isTesting ? null : _testConnection,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: const Icon(Icons.cloud_off, color: Colors.red),
                                              label: const Text('Use Local Only'),
                                              onPressed: () async {
                                                await ref.read(syncServiceProvider).clearCredentials();
                                                setState(() {
                                                  _serverController.clear();
                                                  _userController.clear();
                                                  _passwordController.clear();
                                                  _statusMessage = 'Switched to standalone Local Mode.';
                                                  _isSuccessStatus = true;
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                );
                              },
                            );
                          },
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: const [0, 60, 180, 360, 720].contains(settings.periodicSyncIntervalMinutes)
                              ? settings.periodicSyncIntervalMinutes
                              : 180,
                          decoration: const InputDecoration(
                            labelText: 'Periodic Background Sync',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.schedule),
                          ),
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('Manual Only')),
                            DropdownMenuItem(value: 60, child: Text('Every 1 Hour')),
                            DropdownMenuItem(value: 180, child: Text('Every 3 Hours (Default)')),
                            DropdownMenuItem(value: 360, child: Text('Every 6 Hours')),
                            DropdownMenuItem(value: 720, child: Text('Every 12 Hours')),
                          ],
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setPeriodicSyncIntervalMinutes(val);
                          },
                        ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<SyncConflictPolicy>(
                          isExpanded: true,
                          initialValue: SyncConflictPolicy.values.contains(settings.syncConflictPolicy)
                              ? settings.syncConflictPolicy
                              : SyncConflictPolicy.furthestPosition,
                          decoration: const InputDecoration(
                            labelText: 'Sync Conflict Resolution',
                            border: OutlineInputBorder(),
                            prefixIcon: Icon(Icons.merge_type),
                          ),
                          items: SyncConflictPolicy.values.map((pol) {
                            return DropdownMenuItem(value: pol, child: Text(pol.label));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) settingsNotifier.setSyncConflictPolicy(val);
                          },
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Sync on App Launch'),
                          subtitle: const Text('Automatically refresh feeds and sync episode progress upon opening the app'),
                          value: settings.syncOnLaunch,
                          onChanged: (val) => settingsNotifier.setSyncOnLaunch(val),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
                  icon: const Icon(Icons.save),
                  label: const Text('Save All Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onPressed: _saveCredentials,
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0, left: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDownloadsStorageCard(BuildContext context) {
    final storageAsync = ref.watch(downloadStorageUsageBytesProvider);
    final countAsync = ref.watch(downloadedEpisodesCountProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_outlined, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Storage Used',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      storageAsync.when(
                        data: (bytes) {
                          final count = countAsync.valueOrNull ?? 0;
                          return Text(
                            '${_formatBytes(bytes)} across $count downloaded ${count == 1 ? 'episode' : 'episodes'}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                          );
                        },
                        loading: () => const Text('Calculating...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        error: (err, st) => const Text('Storage calculation error', style: TextStyle(fontSize: 12, color: Colors.red)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 20),
                  tooltip: 'Refresh storage info',
                  onPressed: () {
                    ref.invalidate(downloadStorageUsageBytesProvider);
                    ref.invalidate(downloadedEpisodesCountProvider);
                  },
                ),
                if (!isNarrow) ...[
                  const SizedBox(width: 4),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 18),
                    label: const Text('Clear All'),
                    onPressed: () => _showClearAllDownloadsDialog(context),
                  ),
                ],
              ],
            ),
            if (isNarrow) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.delete_sweep_outlined, color: Colors.red, size: 18),
                  label: const Text('Clear All Downloads'),
                  onPressed: () => _showClearAllDownloadsDialog(context),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Open Download Center'),
                onPressed: () {
                  PodcastMerlinApp.mainShellKey.currentState?.navigateTo(2);
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    var i = 0;
    double count = bytes.toDouble();
    while (count >= 1024 && i < suffixes.length - 1) {
      count /= 1024;
      i++;
    }
    return '${count.toStringAsFixed(1)} ${suffixes[i]}';
  }

  Future<void> _showClearAllDownloadsDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Downloads?'),
        content: const Text(
          'This will delete all downloaded audio files from your device. Your playback history and subscriptions will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final deleted = await ref.read(episodeDownloadServiceProvider).clearAllDownloads();
      ref.invalidate(downloadStorageUsageBytesProvider);
      ref.invalidate(downloadedEpisodesCountProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cleared $deleted downloaded audio ${deleted == 1 ? 'file' : 'files'}')),
        );
      }
    }
  }
}
