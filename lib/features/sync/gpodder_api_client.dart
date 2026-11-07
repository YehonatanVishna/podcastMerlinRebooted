import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../../core/models/gpodder_action.dart';
import '../../core/utils/error_formatter.dart';

class GPodderApiException implements Exception {
  final String message;
  final int? statusCode;

  GPodderApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class GPodderApiClient {
  final Dio _dio;
  String? lastError;
  int? lastEpisodeActionTimestamp;
  final Set<String> _registeredDevices = {};

  GPodderApiClient({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 30),
                receiveTimeout: const Duration(seconds: 60),
                headers: {
                  'User-Agent': 'PodcastMerlin/2.0 (Flutter)',
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  String _cleanRootUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    final suffixes = [
      '/index.php/apps/gpoddersync',
      '/index.php/apps/gpodder',
      '/apps/gpoddersync',
      '/apps/gpodder',
      '/index.php',
      '/api/2',
    ];
    for (final suffix in suffixes) {
      if (url.toLowerCase().endsWith(suffix)) {
        url = url.substring(0, url.length - suffix.length);
        while (url.endsWith('/')) {
          url = url.substring(0, url.length - 1);
        }
      }
    }
    return url;
  }

  bool _isStandardGpodderServer(String serverUrl) {
    final lower = serverUrl.trim().toLowerCase();
    return lower.contains('gpodder.net') || lower.contains('/api/2');
  }

  String _formatBaseUrl(String serverUrl) {
    var url = serverUrl.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/index.php')) {
      url = url.substring(0, url.length - 10);
    }
    if (_isStandardGpodderServer(url)) {
      return _cleanRootUrl(url);
    }
    final lower = url.toLowerCase();
    if (!lower.contains('/apps/gpoddersync') && !lower.contains('/apps/gpodder')) {
      url = '$url/index.php/apps/gpoddersync';
    }
    return url;
  }

  String _normalizeDeviceId(String? deviceId) {
    final trimmed = deviceId?.trim() ?? '';
    return trimmed.isEmpty ? 'podcast_merlin_flutter' : trimmed;
  }

  bool _shouldTryNextEndpoint(int? statusCode) {
    return statusCode == 301 ||
        statusCode == 302 ||
        statusCode == 307 ||
        statusCode == 308 ||
        statusCode == 400 ||
        statusCode == 404 ||
        statusCode == 405;
  }

  bool _isHtmlResponse(dynamic data) {
    if (data is String) {
      final trimmed = data.trimLeft().toLowerCase();
      return trimmed.startsWith('<!doctype html') || trimmed.startsWith('<html');
    }
    return false;
  }

  Future<void> _ensureDeviceRegistered({
    required String rootUrl,
    required String username,
    required String password,
    required String deviceId,
    bool force = false,
  }) async {
    final key = '$rootUrl|$username|$deviceId';
    if (!force && _registeredDevices.contains(key)) return;
    final encUser = Uri.encodeComponent(username.trim());
    final encDevice = Uri.encodeComponent(deviceId);
    try {
      final res = await _dio.post(
        '$rootUrl/api/2/devices/$encUser/$encDevice.json',
        data: {
          'caption': 'Podcast Merlin',
          'type': 'desktop',
        },
        options: _getAuthOptions(username, password).copyWith(
          connectTimeout: const Duration(seconds: 10),
          sendTimeout: const Duration(seconds: 10),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      if (res.statusCode == 200 || res.statusCode == 201) {
        _registeredDevices.add(key);
      }
    } catch (_) {
      // Best-effort registration; some servers do not implement /api/2/devices
    }
  }

  Options _getAuthOptions(String username, String password) {
    final authBytes = utf8.encode('$username:$password');
    final authHeader = 'Basic ${base64Encode(authBytes)}';
    return Options(
      headers: {
        'Authorization': authHeader,
      },
    );
  }

  List<String> _extractUrls(dynamic raw) {
    final urls = <String>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is String) {
          final trimmed = item.trim();
          if (trimmed.isNotEmpty) urls.add(trimmed);
        } else if (item is Map) {
          final url = (item['url'] ?? item['rss_url'] ?? item['rssUrl'] ?? item['feed'] ?? item['link'] ?? '').toString().trim();
          if (url.isNotEmpty) urls.add(url);
        }
      }
    } else if (raw is String && raw.trim().isNotEmpty) {
      urls.add(raw.trim());
    } else if (raw is Map) {
      final url = (raw['url'] ?? raw['rss_url'] ?? raw['rssUrl'] ?? raw['feed'] ?? raw['link'] ?? '').toString().trim();
      if (url.isNotEmpty) urls.add(url);
    }
    return urls;
  }

  /// Fast connectivity ping check prior to any server HTTP request
  Future<bool> pingServer({
    required String serverUrl,
    required String username,
    required String password,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return false;
    }
    try {
      final rootUrl = _cleanRootUrl(serverUrl);
      final baseUrl = _formatBaseUrl(serverUrl);
      final encUser = Uri.encodeComponent(username.trim());
      final isStandard = _isStandardGpodderServer(serverUrl);
      final authOpts = _getAuthOptions(username, password).copyWith(
        connectTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
      );

      final attempts = <({String method, String url})>[
        if (isStandard) ...[
          (method: 'POST', url: '$rootUrl/api/2/auth/$encUser/login.json'),
          (method: 'GET', url: '$rootUrl/subscriptions/$encUser.json'),
          (method: 'GET', url: '$rootUrl/api/2/episodes/$encUser.json?since=2147483647'),
        ] else ...[
          (method: 'GET', url: '$baseUrl/subscriptions?since=2147483647'),
          (method: 'POST', url: '$rootUrl/api/2/auth/$encUser/login.json'),
          (method: 'GET', url: '$rootUrl/subscriptions/$encUser.json'),
          (method: 'GET', url: '$rootUrl/api/2/episodes/$encUser.json?since=2147483647'),
        ],
      ];

      DioException? lastDioErr;
      int? lastStatusCode;

      for (final attempt in attempts) {
        try {
          final Response response;
          if (attempt.method == 'POST') {
            response = await _dio.post(attempt.url, options: authOpts);
          } else {
            response = await _dio.get(attempt.url, options: authOpts);
          }
          lastStatusCode = response.statusCode;
          if (response.statusCode == 200) {
            if (attempt.method == 'GET' && _isHtmlResponse(response.data)) {
              continue;
            }
            lastError = null;
            return true;
          }
        } on DioException catch (dioErr) {
          lastDioErr = dioErr;
          if (_shouldTryNextEndpoint(dioErr.response?.statusCode)) {
            continue;
          }
          rethrow;
        }
      }

      if (lastDioErr != null) {
        throw lastDioErr;
      }
      lastError = 'gPodder server ping returned HTTP status ${lastStatusCode ?? "unknown"}';
      return false;
    } catch (e) {
      if (kDebugMode) print('pingServer error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }

  /// Check connectivity & credentials against Nextcloud gPodder server, returning detailed error or null if success
  Future<String?> testConnectionDetailed({
    required String serverUrl,
    required String username,
    required String password,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    if (serverUrl.trim().isEmpty) {
      return 'Server URL cannot be empty.';
    }
    if (username.trim().isEmpty || password.trim().isEmpty) {
      return 'Username and password cannot be empty.';
    }
    final ok = await pingServer(
      serverUrl: serverUrl,
      username: username,
      password: password,
      deviceId: deviceId,
    );
    return ok ? null : (lastError ?? 'Connection failed');
  }

  /// Check connectivity & credentials against Nextcloud gPodder server
  Future<bool> checkConnection({
    required String serverUrl,
    required String username,
    required String password,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    return pingServer(
      serverUrl: serverUrl,
      username: username,
      password: password,
      deviceId: deviceId,
    );
  }

  /// Get subscriptions diff from server
  Future<Map<String, dynamic>?> fetchSubscriptions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return null;
    }

    try {
      final rootUrl = _cleanRootUrl(serverUrl);
      final baseUrl = _formatBaseUrl(serverUrl);
      final encUser = Uri.encodeComponent(username.trim());
      final normDevice = _normalizeDeviceId(deviceId);
      final encDevice = Uri.encodeComponent(normDevice);
      final isStandard = _isStandardGpodderServer(serverUrl);
      final options = _getAuthOptions(username, password);

      if (isStandard) {
        await _ensureDeviceRegistered(
          rootUrl: rootUrl,
          username: username,
          password: password,
          deviceId: normDevice,
        );
      }

      final queryParam = sinceTimestamp > 0 ? '?since=$sinceTimestamp' : '';
      final urlsToTry = <String>[
        if (isStandard) ...[
          '$rootUrl/api/2/subscriptions/$encUser/$encDevice.json$queryParam',
          if (sinceTimestamp == 0) '$rootUrl/api/2/subscriptions/$encUser/$encDevice.json?since=0',
          '$rootUrl/subscriptions/$encUser/$encDevice.json',
          '$rootUrl/subscriptions/$encUser.json',
        ] else ...[
          '$baseUrl/subscriptions$queryParam',
          if (sinceTimestamp == 0) '$baseUrl/subscriptions?since=0',
          if (baseUrl.contains('/index.php/'))
            '${baseUrl.replaceFirst('/index.php/', '/')}/subscriptions$queryParam'
          else
            '$baseUrl/index.php/apps/gpoddersync/subscriptions$queryParam',
          '$rootUrl/api/2/subscriptions/$encUser/$encDevice.json$queryParam',
          '$rootUrl/subscriptions/$encUser.json',
        ],
      ];

      Response? response;
      String? matchedUrl;
      DioException? lastDioException;

      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.get(targetUrl, options: options);
          if (res.statusCode == 200 && res.data != null) {
            dynamic data = res.data;
            if (data is String) {
              final trimmed = data.trim();
              if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
                try {
                  data = jsonDecode(trimmed);
                } catch (_) {
                  data = null;
                }
              } else {
                data = null;
              }
            }
            if (data is Map || data is List) {
              response = res;
              matchedUrl = targetUrl;
              break;
            }
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (_shouldTryNextEndpoint(dioErr.response?.statusCode)) {
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        if (lastDioException != null) {
          throw lastDioException;
        }
        lastError = 'Failed to fetch subscriptions from server';
        return null;
      }

      if (response.statusCode == 200 && response.data != null) {
        dynamic decoded = response.data;
        if (decoded is String) {
          try {
            decoded = jsonDecode(decoded);
          } catch (_) {}
        }

        if (decoded is List) {
          lastError = null;
          final addList = _extractUrls(decoded);
          return {
            'add': addList,
            'remove': <String>[],
            'timestamp': sinceTimestamp,
          };
        } else if (decoded is Map) {
          lastError = null;
          final map = Map<String, dynamic>.from(decoded);
          final addRaw = map['add'] ?? map['subscriptions'] ?? map['urls'] ?? map['feeds'];
          final removeRaw = map['remove'];

          final addList = _extractUrls(addRaw);
          final removeList = _extractUrls(removeRaw);

          // On initial sync (sinceTimestamp == 0) with standard gPodder v2 device endpoints,
          // also merge account-wide subscriptions (/subscriptions/<user>.json) so subscriptions
          // from other devices on the same gpodder.net account are discovered immediately.
          if (sinceTimestamp == 0 &&
              matchedUrl != null &&
              matchedUrl.contains('/api/2/subscriptions/')) {
            try {
              final allRes = await _dio.get(
                '$rootUrl/subscriptions/$encUser.json',
                options: options,
              );
              if (allRes.statusCode == 200 && allRes.data != null) {
                dynamic allDecoded = allRes.data;
                if (allDecoded is String) {
                  final trimmed = allDecoded.trim();
                  if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
                    try {
                      allDecoded = jsonDecode(trimmed);
                    } catch (_) {}
                  }
                }
                final accountUrls = _extractUrls(allDecoded);
                final existingSet = {...addList, ...removeList};
                for (final url in accountUrls) {
                  if (!existingSet.contains(url)) {
                    addList.add(url);
                    existingSet.add(url);
                  }
                }
              }
            } catch (_) {
              // Best-effort merge of account-wide subscriptions
            }
          }

          int parsedTs = sinceTimestamp;
          final tsRaw = map['timestamp'];
          if (tsRaw is num) {
            parsedTs = tsRaw.toInt();
          } else if (tsRaw != null) {
            parsedTs = int.tryParse(tsRaw.toString()) ?? sinceTimestamp;
          }

          return {
            'add': addList,
            'remove': removeList,
            'timestamp': parsedTs,
          };
        }
      }
      lastError = 'Server returned HTTP status ${response.statusCode}';
      return null;
    } catch (e) {
      if (kDebugMode) print('fetchSubscriptions error: $e');
      lastError = AppErrorFormatter.format(e);
      return null;
    }
  }

  /// Upload subscription add/remove actions to server
  Future<bool> uploadSubscriptionChanges({
    required String serverUrl,
    required String username,
    required String password,
    required List<String> addUrls,
    required List<String> removeUrls,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    if (addUrls.isEmpty && removeUrls.isEmpty) return true;

    try {
      final rootUrl = _cleanRootUrl(serverUrl);
      final baseUrl = _formatBaseUrl(serverUrl);
      final encUser = Uri.encodeComponent(username.trim());
      final normDevice = _normalizeDeviceId(deviceId);
      final encDevice = Uri.encodeComponent(normDevice);
      final isStandard = _isStandardGpodderServer(serverUrl);

      if (isStandard) {
        await _ensureDeviceRegistered(
          rootUrl: rootUrl,
          username: username,
          password: password,
          deviceId: normDevice,
        );
      }

      final payload = {
        'add': addUrls,
        'remove': removeUrls,
      };
      final v2Url = '$rootUrl/api/2/subscriptions/$encUser/$encDevice.json';
      final urlsToTry = <String>[
        if (isStandard) ...[
          v2Url,
          '$baseUrl/subscription_change/create',
          '$baseUrl/subscriptions',
        ] else ...[
          '$baseUrl/subscription_change/create',
          '$baseUrl/subscriptions',
          v2Url,
        ],
      ];
      Response? response;
      DioException? lastDioException;
      for (final targetUrl in urlsToTry) {
        try {
          if (!isStandard && targetUrl == v2Url) {
            await _ensureDeviceRegistered(
              rootUrl: rootUrl,
              username: username,
              password: password,
              deviceId: normDevice,
            );
          }
          final res = await _dio.post(
            targetUrl,
            data: payload,
            options: _getAuthOptions(username, password),
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            response = res;
            break;
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (targetUrl == v2Url && dioErr.response?.statusCode == 404) {
            await _ensureDeviceRegistered(
              rootUrl: rootUrl,
              username: username,
              password: password,
              deviceId: normDevice,
              force: true,
            );
            try {
              final retryRes = await _dio.post(
                targetUrl,
                data: payload,
                options: _getAuthOptions(username, password),
              );
              if (retryRes.statusCode == 200 || retryRes.statusCode == 201) {
                response = retryRes;
                break;
              }
            } on DioException catch (retryErr) {
              lastDioException = retryErr;
            }
          }
          if (_shouldTryNextEndpoint(dioErr.response?.statusCode)) {
            continue;
          }
          rethrow;
        }
      }
      if (response != null) {
        lastError = null;
        return true;
      }
      if (lastDioException != null) throw lastDioException;
      lastError = 'Failed to upload subscriptions';
      return false;
    } catch (e) {
      if (kDebugMode) print('uploadSubscriptionChanges error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }

  /// Fetch remote episode actions since timestamp
  Future<List<GPodderAction>> fetchEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    int sinceTimestamp = 0,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    lastEpisodeActionTimestamp = null;
    if (serverUrl.trim().isEmpty || username.trim().isEmpty || password.trim().isEmpty) {
      lastError = 'Server credentials not configured.';
      return [];
    }

    try {
      final rootUrl = _cleanRootUrl(serverUrl);
      final baseUrl = _formatBaseUrl(serverUrl);
      final encUser = Uri.encodeComponent(username.trim());
      final isStandard = _isStandardGpodderServer(serverUrl);
      final options = _getAuthOptions(username, password).copyWith(
        receiveTimeout: const Duration(seconds: 90),
      );

      final queryParam = sinceTimestamp > 0 ? '?since=$sinceTimestamp' : '';
      final urlsToTry = <String>[
        if (isStandard) ...[
          '$rootUrl/api/2/episodes/$encUser.json$queryParam',
          if (sinceTimestamp == 0) '$rootUrl/api/2/episodes/$encUser.json?since=0',
          '$baseUrl/episode_action$queryParam',
        ] else ...[
          '$baseUrl/episode_action$queryParam',
          if (sinceTimestamp == 0) '$baseUrl/episode_action?since=0',
          if (baseUrl.contains('/index.php/'))
            '${baseUrl.replaceFirst('/index.php/', '/')}/episode_action$queryParam'
          else
            '$baseUrl/index.php/apps/gpoddersync/episode_action$queryParam',
          '$rootUrl/api/2/episodes/$encUser.json$queryParam',
        ],
      ];

      Response? response;
      DioException? lastDioException;

      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.get(targetUrl, options: options);
          if (res.statusCode == 200 && res.data != null) {
            dynamic data = res.data;
            if (data is String) {
              final trimmed = data.trim();
              if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
                try {
                  data = jsonDecode(trimmed);
                } catch (_) {
                  data = null;
                }
              } else {
                data = null;
              }
            }
            if (data is Map || data is List) {
              response = res;
              break;
            }
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (_shouldTryNextEndpoint(dioErr.response?.statusCode)) {
            continue;
          }
          rethrow;
        }
      }

      if (response == null) {
        if (lastDioException != null) {
          throw lastDioException;
        }
        lastError = 'Failed to fetch episode actions from server';
        return [];
      }

      dynamic decoded = response.data;
      if (decoded is String) {
        try {
          decoded = jsonDecode(decoded);
        } catch (_) {}
      }

      List rawActions = [];
      if (decoded is List) {
        rawActions = decoded;
      } else if (decoded is Map) {
        rawActions = (decoded['actions'] as List?) ??
            (decoded['episode_actions'] as List?) ??
            (decoded['episodeActions'] as List?) ??
            (decoded['data'] as List?) ??
            [];
        final tsVal = decoded['timestamp'];
        if (tsVal is num) {
          lastEpisodeActionTimestamp = tsVal.toInt();
        } else if (tsVal != null) {
          final s = tsVal.toString().trim();
          final parsedNum = num.tryParse(s);
          if (parsedNum != null) {
            lastEpisodeActionTimestamp = parsedNum.toInt();
          }
        }
      }

      lastError = null;
      final actions = <GPodderAction>[];
      for (final item in rawActions) {
        try {
          dynamic mapItem = item;
          if (mapItem is String) {
            try {
              mapItem = jsonDecode(mapItem);
            } catch (_) {}
          }
          if (mapItem is Map) {
            actions.add(GPodderAction.fromMap(Map<String, dynamic>.from(mapItem)));
          }
        } catch (e) {
          if (kDebugMode) print('Error parsing individual action: $e');
        }
      }

      if (lastEpisodeActionTimestamp == null && actions.isNotEmpty) {
        final maxActionTs = actions
            .map((a) => a.timestamp.millisecondsSinceEpoch ~/ 1000)
            .fold(0, (max, ts) => ts > max ? ts : max);
        if (maxActionTs > 0) {
          lastEpisodeActionTimestamp = maxActionTs;
        }
      }

      return actions;
    } catch (e) {
      if (kDebugMode) print('fetchEpisodeActions error: $e');
      lastError = AppErrorFormatter.format(e);
      return [];
    }
  }

  /// Post queued episode actions to server
  Future<bool> uploadEpisodeActions({
    required String serverUrl,
    required String username,
    required String password,
    required List<GPodderAction> actions,
    String deviceId = 'podcast_merlin_flutter',
  }) async {
    if (actions.isEmpty) return true;

    try {
      final rootUrl = _cleanRootUrl(serverUrl);
      final baseUrl = _formatBaseUrl(serverUrl);
      final encUser = Uri.encodeComponent(username.trim());
      final isStandard = _isStandardGpodderServer(serverUrl);
      final payload = actions.map((a) => a.toApiJson()).toList();
      final v2Url = '$rootUrl/api/2/episodes/$encUser.json';
      final urlsToTry = <String>[
        if (isStandard) ...[
          v2Url,
          '$baseUrl/episode_action/create',
          '$baseUrl/episode_actions',
        ] else ...[
          '$baseUrl/episode_action/create',
          '$baseUrl/episode_actions',
          v2Url,
        ],
      ];
      Response? response;
      DioException? lastDioException;
      for (final targetUrl in urlsToTry) {
        try {
          final res = await _dio.post(
            targetUrl,
            data: payload,
            options: _getAuthOptions(username, password),
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            response = res;
            break;
          }
        } on DioException catch (dioErr) {
          lastDioException = dioErr;
          if (_shouldTryNextEndpoint(dioErr.response?.statusCode)) {
            continue;
          }
          rethrow;
        }
      }
      if (response != null) {
        lastError = null;
        return true;
      }
      if (lastDioException != null) throw lastDioException;
      lastError = 'Failed to upload episode actions';
      return false;
    } catch (e) {
      if (kDebugMode) print('uploadEpisodeActions error: $e');
      lastError = AppErrorFormatter.format(e);
      return false;
    }
  }
}
