import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'core/database/ffi_init.dart';
import 'core/providers/app_providers.dart';
import 'core/theme/app_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:media_kit/media_kit.dart';
import 'features/player/audio_player_service.dart';
import 'features/player/podcast_widget_service.dart';
import 'features/ui/views/main_shell.dart';

class GoBackIntent extends Intent {
  const GoBackIntent();
}

class GoForwardIntent extends Intent {
  const GoForwardIntent();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request notification permission on Android 13+ for native notification shade controls
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Permission.notification.request();
    } catch (_) {}
  }

  // Platform-safe FFI setup (noop on Web, sqflite_ffi on Desktop/Mobile)
  setupFfi();
  _registerNativeLicenses();
  try {
    MediaKit.ensureInitialized();
  } catch (e) {
    debugPrint('MediaKit.ensureInitialized error: $e');
  }

  // Initialize audio_service so the handler is registered with the platform's
  // media session (Android notification shade, lock-screen controls, etc.)
  final audioHandler = await AudioService.init(
    builder: () => MerlinAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.podcastmerlin.audio',
      androidNotificationChannelName: 'Podcast Merlin Playback',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
      androidNotificationClickStartsActivity: true,
      androidNotificationIcon: 'drawable/ic_stat_podcast',
      androidShowNotificationBadge: true,
    ),
  );

  // Wait for initial queue & active playback restoration to complete before launching UI
  await audioHandler.initFuture.timeout(
    const Duration(seconds: 4),
    onTimeout: () {
      debugPrint('audioHandler.initFuture timed out, proceeding with app startup');
    },
  );

  runApp(
    ProviderScope(
      overrides: [
        audioHandlerProvider.overrideWithValue(audioHandler),
      ],
      child: const PodcastMerlinApp(),
    ),
  );
}

class PodcastMerlinApp extends ConsumerWidget {
  const PodcastMerlinApp({super.key});

  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
  static final GlobalKey<MainShellState> mainShellKey = GlobalKey<MainShellState>();

  static bool handleGoBack() {
    final navState = rootNavigatorKey.currentState;
    if (navState != null && navState.canPop()) {
      navState.pop();
      return true;
    }
    return mainShellKey.currentState?.goBack() ?? false;
  }

  static bool handleGoForward() {
    return mainShellKey.currentState?.goForward() ?? false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    final seedColor = settings.accentColor.color;
    final isAmoled = settings.themeMode == AppThemeMode.amoled;
    final useDynamic = settings.useDynamicColor;

    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        final dynamicLight = useDynamic ? lightDynamic : null;
        final dynamicDark = useDynamic ? darkDynamic : null;

        final lightTheme = AppTheme.createLightTheme(
          dynamicLight,
          seedColor: seedColor,
        );

        final darkTheme = isAmoled
            ? AppTheme.createAmoledTheme(
                dynamicDark,
                seedColor: seedColor,
              )
            : AppTheme.createDarkTheme(
                dynamicDark,
                seedColor: seedColor,
              );

        // Sync darkTheme's harmonized primary/onPrimary accents to the home screen widget.
        // When dynamic colors are enabled, surfaceColor is omitted so Android 12+ natively
        // applies system_accent2_800 wallpaper-tinted background matching the YouTube widget.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          PodcastWidgetService.instance.updateThemeColors(
            primaryColor: darkTheme.colorScheme.primary,
            onPrimaryColor: darkTheme.colorScheme.onPrimary,
            surfaceColor: (useDynamic && !isAmoled)
                ? null
                : darkTheme.colorScheme.surfaceContainer,
          );
        });

        return MaterialApp(
          navigatorKey: rootNavigatorKey,
          title: 'Podcast Merlin',
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: settings.themeMode.toThemeMode(),
          builder: (context, child) {
            return Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true): const GoBackIntent(),
                const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true): const GoForwardIntent(),
                const SingleActivator(LogicalKeyboardKey.browserBack): const GoBackIntent(),
                const SingleActivator(LogicalKeyboardKey.browserForward): const GoForwardIntent(),
                const SingleActivator(LogicalKeyboardKey.navigatePrevious): const GoBackIntent(),
                const SingleActivator(LogicalKeyboardKey.navigateNext): const GoForwardIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  GoBackIntent: CallbackAction<GoBackIntent>(
                    onInvoke: (_) => handleGoBack(),
                  ),
                  GoForwardIntent: CallbackAction<GoForwardIntent>(
                    onInvoke: (_) => handleGoForward(),
                  ),
                },
                child: Focus(
                  autofocus: true,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (PointerDownEvent event) {
                      if ((event.buttons & kBackMouseButton) != 0) {
                        handleGoBack();
                      } else if ((event.buttons & kForwardMouseButton) != 0) {
                        handleGoForward();
                      }
                    },
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
          },
          home: MainShell(key: mainShellKey),
        );
      },
    );
  }
}

void _registerNativeLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['libmpv', 'mpv-player'],
      '''Copyright © mpv developers
Licensed under GNU General Public License v2.0 or later (with LGPL parts).
Upstream source code available at https://github.com/mpv-player/mpv
Windows runtime builds: https://github.com/media-kit/libmpv-win32-video-build''',
    );
    yield const LicenseEntryWithLineBreaks(
      ['libsecret'],
      '''Copyright © GNOME Foundation
Licensed under GNU Lesser General Public License v2.1 or later.''',
    );
    yield const LicenseEntryWithLineBreaks(
      ['sqlite3'],
      '''SQLite is in the Public Domain (dedicated to the public domain by D. Richard Hipp).''',
    );
    yield const LicenseEntryWithLineBreaks(
      ['ANGLE (Google / Chromium)'],
      '''Copyright 2018 The ANGLE Project Authors.
Licensed under BSD 3-Clause License.''',
    );
  });
}
