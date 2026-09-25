import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:podcast_merlin_flutter/core/database/database_helper.dart';
import 'package:podcast_merlin_flutter/core/models/episode.dart';
import 'package:podcast_merlin_flutter/core/models/podcast.dart';
import 'package:podcast_merlin_flutter/core/providers/app_providers.dart';
import 'package:podcast_merlin_flutter/core/services/connectivity_service.dart';
import 'package:podcast_merlin_flutter/features/downloads/episode_download_service.dart';
import 'package:podcast_merlin_flutter/features/sync/secure_storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('ConnectivityService & isResultsUnmetered Matrix', () {
    test('Wi-Fi or Ethernet is considered unmetered', () {
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.wifi]), isTrue);
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.ethernet]), isTrue);
      expect(
        DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.wifi, ConnectivityResult.mobile]),
        isTrue,
      );
      expect(
        DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.ethernet, ConnectivityResult.mobile]),
        isTrue,
      );
    });

    test('Mobile, none, or bluetooth alone is NOT unmetered', () {
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.mobile]), isFalse);
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.none]), isFalse);
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.bluetooth]), isFalse);
      expect(
        DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.mobile, ConnectivityResult.bluetooth]),
        isFalse,
      );
      expect(DefaultConnectivityService.isResultsUnmetered([]), isFalse);
    });

    test('VPN or Other without mobile is considered unmetered', () {
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.vpn]), isTrue);
      expect(DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.other]), isTrue);
    });

    test('VPN or Other with mobile is NOT unmetered', () {
      expect(
        DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.vpn, ConnectivityResult.mobile]),
        isFalse,
      );
      expect(
        DefaultConnectivityService.isResultsUnmetered([ConnectivityResult.other, ConnectivityResult.mobile]),
        isFalse,
      );
    });

    test('MockConnectivityService updates and emits changes', () async {
      final mock = MockConnectivityService(initialIsUnmetered: true);
      expect(await mock.isUnmetered(), isTrue);

      final emissions = <bool>[];
      final sub = mock.onUnmeteredChanged.listen(emissions.add);

      mock.isUnmeteredConnection = false;
      expect(await mock.isUnmetered(), isFalse);

      mock.setUnmetered(true);
      expect(await mock.isUnmetered(), isTrue);

      await Future.delayed(const Duration(milliseconds: 50));
      expect(emissions, [false, true]);

      await sub.cancel();
      mock.dispose();
    });
  });

  group('DownloadOnlyOnUnmeteredNotifier & Riverpod Providers', () {
    test('Notifier loads initial value and toggle writes to storage', () async {
      final storage = SecureStorageService();
      await storage.setDownloadOnlyOnUnmetered(false);

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(storage),
        ],
      );

      final notifier = container.read(downloadOnlyOnUnmeteredProvider.notifier);
      expect(container.read(downloadOnlyOnUnmeteredProvider), isFalse);

      await notifier.toggle(true);
      expect(container.read(downloadOnlyOnUnmeteredProvider), isTrue);
      expect(await storage.getDownloadOnlyOnUnmetered(), isTrue);

      await notifier.toggle(false);
      expect(container.read(downloadOnlyOnUnmeteredProvider), isFalse);
      expect(await storage.getDownloadOnlyOnUnmetered(), isFalse);

      container.dispose();
    });
  });

  group('EpisodeDownloadService Unmetered Network Integration', () {
    late Directory tempDir;
    late DatabaseHelper db;

    setUpAll(() async {
      HttpOverrides.global = null;
      tempDir = await Directory.systemTemp.createTemp('unmetered_dl_tests_');
    });

    tearDownAll(() async {
      try {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      } catch (_) {}
    });

    setUp(() async {
      db = DatabaseHelper.instance;
      final database = await db.database;
      await database.delete('episodes');
      await database.delete('podcasts');
    });

    test('startDownload is blocked when on metered network and unmetered only is enabled', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: false);
      bool unmeteredOnly = true;

      final service = EpisodeDownloadService(
        db: db,
        connectivityService: mockConn,
        isUnmeteredOnly: () => unmeteredOnly,
        downloadDirResolver: () async => tempDir,
      );

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed1.xml',
        title: 'Pod 1',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-metered-blocked',
          title: 'Metered Blocked Episode',
          mediaUrl: 'https://example.com/audio1.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed1.xml',
        ),
      ]);

      final episode = (await db.getEpisodeByGuid('ep-metered-blocked'))!;

      final events = <DownloadTaskEvent>[];
      final sub = service.onDownloadEvent.listen(events.add);

      await service.startDownload(episode);

      expect(service.isEpisodeActive(episode.id!), isFalse);
      expect(service.isEpisodeQueued(episode.id!), isTrue);

      final dbEp = await db.getEpisodeById(episode.id!);
      expect(dbEp?.downloadStatus, DownloadStatus.queued);
      expect(dbEp?.downloadError, 'Waiting for unmetered Wi-Fi connection');

      expect(events.length, 1);
      expect(events.first.status, DownloadStatus.queued);
      expect(events.first.error, 'Waiting for unmetered Wi-Fi connection');

      await sub.cancel();
      service.dispose();
      mockConn.dispose();
    });

    test('resumeDownload is blocked when on metered network and unmetered only is enabled', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: false);
      bool unmeteredOnly = true;

      final service = EpisodeDownloadService(
        db: db,
        connectivityService: mockConn,
        isUnmeteredOnly: () => unmeteredOnly,
        downloadDirResolver: () async => tempDir,
      );

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed2.xml',
        title: 'Pod 2',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-resume-blocked',
          title: 'Resume Blocked Episode',
          mediaUrl: 'https://example.com/audio2.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed2.xml',
          downloadStatus: DownloadStatus.paused,
        ),
      ]);

      final episode = (await db.getEpisodeByGuid('ep-resume-blocked'))!;

      final events = <DownloadTaskEvent>[];
      final sub = service.onDownloadEvent.listen(events.add);

      await service.resumeDownload(episode);

      expect(service.isEpisodeActive(episode.id!), isFalse);
      expect(service.isEpisodeQueued(episode.id!), isTrue);

      final dbEp = await db.getEpisodeById(episode.id!);
      expect(dbEp?.downloadStatus, DownloadStatus.queued);
      expect(dbEp?.downloadError, 'Waiting for unmetered Wi-Fi connection');

      await sub.cancel();
      service.dispose();
      mockConn.dispose();
    });

    test('Active download is paused/queued when connectivity changes from unmetered to metered', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: true);
      bool unmeteredOnly = true;

      // Mock Dio that yields slow stream of bytes
      final dio = Dio();
      final streamController = StreamController<Uint8List>();

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.cancelToken?.whenCancel.then((e) {
              if (!streamController.isClosed) {
                streamController.addError(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.cancel,
                    error: e,
                    message: e.toString(),
                  ),
                );
              }
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-length': ['1000'],
                }),
                data: ResponseBody(
                  streamController.stream,
                  200,
                  headers: {
                    'content-length': ['1000'],
                  },
                ),
              ),
            );
          },
        ),
      );

      final service = EpisodeDownloadService(
        db: db,
        dio: dio,
        connectivityService: mockConn,
        isUnmeteredOnly: () => unmeteredOnly,
        downloadDirResolver: () async => tempDir,
      );

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed3.xml',
        title: 'Pod 3',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-active-to-metered',
          title: 'Active to Metered Episode',
          mediaUrl: 'https://example.com/audio3.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed3.xml',
        ),
      ]);

      final episode = (await db.getEpisodeByGuid('ep-active-to-metered'))!;

      final events = <DownloadTaskEvent>[];
      final sub = service.onDownloadEvent.listen(events.add);

      // Start download
      await service.startDownload(episode);
      expect(service.isEpisodeActive(episode.id!), isTrue);

      // Feed initial chunk
      streamController.add(Uint8List.fromList(List.filled(200, 1)));
      await Future.delayed(const Duration(milliseconds: 50));

      // Network becomes metered!
      mockConn.isUnmeteredConnection = false;
      await Future.delayed(const Duration(milliseconds: 150));

      // Download should no longer be active, but queued with waiting message
      expect(service.isEpisodeActive(episode.id!), isFalse);
      expect(service.isEpisodeQueued(episode.id!), isTrue);

      final dbEp = await db.getEpisodeById(episode.id!);
      expect(dbEp?.downloadStatus, DownloadStatus.queued);
      expect(dbEp?.downloadError, 'Waiting for unmetered Wi-Fi connection');

      await streamController.close();
      await sub.cancel();
      service.dispose();
      mockConn.dispose();
    });

    test('Queued downloads are automatically resumed when switching from metered to unmetered', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: false);
      bool unmeteredOnly = true;

      // Mock Dio that completes immediately
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-length': ['50'],
                }),
                data: ResponseBody(
                  Stream.value(Uint8List.fromList(List.filled(50, 42))),
                  200,
                  headers: {
                    'content-length': ['50'],
                  },
                ),
              ),
            );
          },
        ),
      );

      final service = EpisodeDownloadService(
        db: db,
        dio: dio,
        connectivityService: mockConn,
        isUnmeteredOnly: () => unmeteredOnly,
        downloadDirResolver: () async => tempDir,
      );

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed4.xml',
        title: 'Pod 4',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-resume-on-wifi',
          title: 'Resume on Wi-Fi Episode',
          mediaUrl: 'https://example.com/audio4.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed4.xml',
        ),
      ]);

      final episode = (await db.getEpisodeByGuid('ep-resume-on-wifi'))!;

      // Queue it while on metered
      await service.startDownload(episode);
      expect(service.isEpisodeQueued(episode.id!), isTrue);
      expect(service.isEpisodeActive(episode.id!), isFalse);

      // Now switch to Wi-Fi / unmetered
      mockConn.isUnmeteredConnection = true;
      await Future.delayed(const Duration(milliseconds: 200));

      // Download should have been processed and completed!
      final dbEp = await db.getEpisodeById(episode.id!);
      expect(dbEp?.downloadStatus, DownloadStatus.downloaded);
      expect(dbEp?.downloadProgress, 1.0);

      service.dispose();
      mockConn.dispose();
    });

    test('onUnmeteredSettingChanged immediately reacts to setting toggles (CR-01 & CR-06)', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: false);
      final streamController = StreamController<Uint8List>.broadcast();
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.cancelToken?.whenCancel.then((e) {
              if (!streamController.isClosed) {
                streamController.addError(
                  DioException(
                    requestOptions: options,
                    type: DioExceptionType.cancel,
                    error: e,
                    message: e.toString(),
                  ),
                );
              }
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                headers: Headers.fromMap({
                  'content-length': ['1000'],
                }),
                data: ResponseBody(
                  streamController.stream,
                  200,
                  headers: {
                    'content-length': ['1000'],
                  },
                ),
              ),
            );
          },
        ),
      );

      bool unmeteredSetting = false;
      final service = EpisodeDownloadService(
        db: db,
        dio: dio,
        connectivityService: mockConn,
        isUnmeteredOnly: () => unmeteredSetting,
        downloadDirResolver: () async => tempDir,
      );

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed5.xml',
        title: 'Pod 5',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-toggle-setting-1',
          title: 'Toggle Episode 1',
          mediaUrl: 'https://example.com/audio5.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed5.xml',
        ),
      ]);

      final episode = (await db.getEpisodeByGuid('ep-toggle-setting-1'))!;

      // 1. With setting = false, download starts even on metered network
      await service.startDownload(episode);
      expect(service.isEpisodeActive(episode.id!), isTrue);

      // Feed initial chunk
      streamController.add(Uint8List.fromList(List.filled(200, 1)));
      await Future.delayed(const Duration(milliseconds: 50));

      // 2. User toggles setting to TRUE: active download should immediately pause
      unmeteredSetting = true;
      await service.onUnmeteredSettingChanged(true);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service.isEpisodeActive(episode.id!), isFalse);

      // 3. User toggles setting back to FALSE: queued download should resume
      unmeteredSetting = false;
      await service.onUnmeteredSettingChanged(false);
      await Future.delayed(const Duration(milliseconds: 100));
      expect(service.isEpisodeActive(episode.id!) || service.isEpisodeQueued(episode.id!), isTrue);

      await streamController.close();
      service.dispose();
      mockConn.dispose();
    });

    test('resumeDownload preserves download progress when blocked on metered network (CR-12)', () async {
      final mockConn = MockConnectivityService(initialIsUnmetered: false);
      final service = EpisodeDownloadService(
        db: db,
        connectivityService: mockConn,
        isUnmeteredOnly: () => true,
        downloadDirResolver: () async => tempDir,
      );

      final events = <DownloadTaskEvent>[];
      service.onDownloadEvent.listen(events.add);

      final podId = await db.insertPodcast(Podcast(
        rssUrl: 'https://example.com/feed-paused.xml',
        title: 'Pod Paused',
        description: '',
        link: '',
        imageUrl: '',
        lastUpdated: DateTime.now(),
      ));

      await db.insertEpisodes([
        Episode(
          podcastId: podId,
          guid: 'ep-paused-partial',
          title: 'Paused Episode',
          mediaUrl: 'https://example.com/paused.mp3',
          description: '',
          imageUrl: '',
          podcastRss: 'https://example.com/feed-paused.xml',
          downloadProgress: 0.65,
          downloadedBytes: 6500,
          totalBytes: 10000,
          downloadStatus: DownloadStatus.paused,
        ),
      ]);

      final pausedEp = (await db.getEpisodeByGuid('ep-paused-partial'))!;

      await service.resumeDownload(pausedEp);
      await Future.delayed(const Duration(milliseconds: 50));

      // Should be queued waiting for Wi-Fi and progress MUST be preserved at 0.65 (not 0.0)
      expect(events.isNotEmpty, isTrue);
      final lastEvent = events.last;
      expect(lastEvent.status, DownloadStatus.queued);
      expect(lastEvent.progress, 0.65);
      expect(lastEvent.downloadedBytes, 6500);
      expect(lastEvent.totalBytes, 10000);
      expect(isWaitingForUnmetered(lastEvent.error), isTrue);

      service.dispose();
      mockConn.dispose();
    });

    test('isWaitingForUnmetered helper correctly matches network messages (CR-09)', () {
      expect(isWaitingForUnmetered(kWaitingForUnmeteredMessage), isTrue);
      expect(isWaitingForUnmetered('Waiting for unmetered Wi-Fi connection'), isTrue);
      expect(isWaitingForUnmetered('download blocked: unmetered Wi-Fi required'), isTrue);
      expect(isWaitingForUnmetered(null), isFalse);
      expect(isWaitingForUnmetered(''), isFalse);
      expect(isWaitingForUnmetered('HTTP 404 Not Found'), isFalse);
      expect(isWaitingForUnmetered('Connection timed out'), isFalse);
    });
  });
}

