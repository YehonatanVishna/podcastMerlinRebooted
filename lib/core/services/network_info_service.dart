import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dbus/dbus.dart';
import '../models/app_settings.dart';

class NetworkConnectionInfo {
  final bool isConnected;
  final bool isWifi;
  final bool isEthernet;
  final bool isCellular;
  final String? ssid;

  const NetworkConnectionInfo({
    this.isConnected = true,
    this.isWifi = false,
    this.isEthernet = false,
    this.isCellular = false,
    this.ssid,
  });

  @override
  String toString() =>
      'NetworkConnectionInfo(connected: $isConnected, wifi: $isWifi, eth: $isEthernet, cell: $isCellular, ssid: "$ssid")';
}

class NetworkInfoService {
  static const MethodChannel _channel = MethodChannel('com.podcastmerlin.app/network');

  /// Helper to clean surrounding quotes and trim whitespace from SSIDs
  static String cleanSsid(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    if (s.isEmpty || s == '<unknown ssid>' || s == '0x') return '';
    if ((s.startsWith('"') && s.endsWith('"')) || (s.startsWith("'") && s.endsWith("'"))) {
      s = s.substring(1, s.length - 1).trim();
    }
    if (s == '<unknown ssid>' || s == '0x') return '';
    return s;
  }

  /// Requests location permission if required on the current platform (Android/macOS)
  Future<bool> requestPermissionIfNeeded() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final locStatus = await Permission.locationWhenInUse.status;
        if (locStatus.isGranted) return true;

        final nearbyStatus = await Permission.nearbyWifiDevices.status;
        if (nearbyStatus.isGranted) return true;

        final res = await Permission.locationWhenInUse.request();
        if (res.isGranted) return true;

        final nearbyRes = await Permission.nearbyWifiDevices.request();
        return nearbyRes.isGranted;
      } catch (_) {
        return false;
      }
    }
    return true;
  }

  /// Checks if system-wide Location Service (GPS) is enabled on the device
  Future<bool> isLocationServiceEnabled() async {
    if (kIsWeb) return true;
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        return await Permission.location.serviceStatus.isEnabled;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  /// Query the current network connection and Wi-Fi SSID
  Future<NetworkConnectionInfo> getNetworkInfo({bool requestPermission = false}) async {
    if (kIsWeb) {
      return const NetworkConnectionInfo(
        isConnected: true,
        isWifi: false,
        isEthernet: false,
        isCellular: false,
        ssid: null,
      );
    }

    if (requestPermission) {
      await requestPermissionIfNeeded();
    }

    // 1. Try native method channel first on mobile and desktop
    try {
      final res = await _channel.invokeMethod<Map<dynamic, dynamic>>('getNetworkInfo');
      if (res != null) {
        final isConnected = res['isConnected'] as bool? ?? true;
        final isWifi = res['isWifi'] as bool? ?? false;
        final isEthernet = res['isEthernet'] as bool? ?? false;
        final isCellular = res['isCellular'] as bool? ?? false;
        final ssid = cleanSsid(res['ssid']?.toString());
        return NetworkConnectionInfo(
          isConnected: isConnected,
          isWifi: isWifi,
          isEthernet: isEthernet,
          isCellular: isCellular,
          ssid: ssid.isNotEmpty ? ssid : null,
        );
      }
    } catch (_) {
      // Native channel method not implemented or failed, proceed to platform fallbacks
    }

    // 2. Platform-specific fallbacks
    if (defaultTargetPlatform == TargetPlatform.linux) {
      return await _getLinuxNetworkInfo();
    } else if (defaultTargetPlatform == TargetPlatform.macOS) {
      return await _getMacOsNetworkInfo();
    } else if (defaultTargetPlatform == TargetPlatform.windows) {
      return await _getWindowsNetworkInfo();
    }

    return await _getGenericNetworkInfo();
  }

  /// Convenience method to retrieve just the current Wi-Fi SSID
  Future<String?> getCurrentWifiSsid({bool requestPermissionIfNeeded = false}) async {
    final info = await getNetworkInfo(requestPermission: requestPermissionIfNeeded);
    return info.ssid;
  }

  /// Verifies if gPodder server access should be allowed based on configured constraints
  Future<({bool allowed, String? reason})> checkGpodderAccess({
    required GpodderNetworkRestrictionMode mode,
    required String allowedSsid,
    bool allowEthernet = true,
    bool requestPermission = false,
  }) async {
    if (mode == GpodderNetworkRestrictionMode.anyNetwork) {
      return (allowed: true, reason: null);
    }

    final info = await getNetworkInfo(requestPermission: requestPermission);

    if (mode == GpodderNetworkRestrictionMode.wifiOrEthernetOnly) {
      if (info.isCellular && !info.isWifi && !info.isEthernet) {
        return (
          allowed: false,
          reason: 'gPodder sync skipped: connected to cellular mobile data (restricted to Wi-Fi/Ethernet).'
        );
      }
      return (allowed: true, reason: null);
    }

    if (mode == GpodderNetworkRestrictionMode.specificWifiSsid) {
      // If user is connected via wired Ethernet (e.g. at home dock) and allowEthernet is enabled:
      if (allowEthernet && info.isEthernet) {
        return (allowed: true, reason: null);
      }

      final targets = allowedSsid
          .split(',')
          .map((s) => cleanSsid(s))
          .where((s) => s.isNotEmpty)
          .toList();

      if (targets.isEmpty) {
        // No specific SSID configured yet, allow connection
        return (allowed: true, reason: null);
      }

      final current = cleanSsid(info.ssid);
      if (current.isEmpty) {
        if (info.isWifi) {
          final isGpsOn = await isLocationServiceEnabled();
          if (!isGpsOn) {
            return (
              allowed: false,
              reason: 'gPodder sync skipped: connected to Wi-Fi, but Location Services (GPS) is turned OFF in device settings. Android requires Location to be ON to verify Wi-Fi name (allowed: ${targets.join(', ')}).'
            );
          }
          return (
            allowed: false,
            reason: 'gPodder sync skipped: connected to Wi-Fi, but could not detect Wi-Fi name (allowed: ${targets.join(', ')}). Please grant Location/Nearby devices permission in Android Settings.'
          );
        }
        return (
          allowed: false,
          reason: 'gPodder sync skipped: not connected to allowed Wi-Fi (allowed: ${targets.join(', ')})${allowEthernet ? ' or wired Ethernet' : ''}.'
        );
      }

      final matches = targets.any((t) => t.toLowerCase() == current.toLowerCase());
      if (!matches) {
        return (
          allowed: false,
          reason: 'gPodder sync skipped: connected to Wi-Fi "$current" (allowed: ${targets.join(', ')}).'
        );
      }

      return (allowed: true, reason: null);
    }

    return (allowed: true, reason: null);
  }

  // --- Linux Network Detection (D-Bus NetworkManager + CLI + sysfs) ---
  Future<NetworkConnectionInfo> _getLinuxNetworkInfo() async {
    // A. Try NetworkManager D-Bus
    try {
      final client = DBusClient.system();
      try {
        final nmObject = DBusRemoteObject(
          client,
          name: 'org.freedesktop.NetworkManager',
          path: DBusObjectPath('/org/freedesktop/NetworkManager'),
        );

        final devicesResponse = await nmObject.callMethod(
          'org.freedesktop.NetworkManager',
          'GetDevices',
          [],
          replySignature: DBusSignature('ao'),
        );

        final devicePaths = (devicesResponse.values.first as DBusArray)
            .children
            .map((e) => (e as DBusObjectPath).value)
            .toList();

        bool hasEthernet = false;
        for (final path in devicePaths) {
          final devObj = DBusRemoteObject(
            client,
            name: 'org.freedesktop.NetworkManager',
            path: DBusObjectPath(path),
          );

          final typeProp = await devObj.getProperty('org.freedesktop.NetworkManager.Device', 'DeviceType');
          final stateProp = await devObj.getProperty('org.freedesktop.NetworkManager.Device', 'State');
          final isActivated = stateProp.toNative() == 100;

          // 1 = NM_DEVICE_TYPE_ETHERNET
          if (typeProp.toNative() == 1 && isActivated) {
            hasEthernet = true;
          }

          // 2 = NM_DEVICE_TYPE_WIFI
          if (typeProp.toNative() == 2 && isActivated) {
            final activeApProp = await devObj.getProperty(
              'org.freedesktop.NetworkManager.Device.Wireless',
              'ActiveAccessPoint',
            );
            final apPath = (activeApProp as DBusObjectPath).value;
            if (apPath.isNotEmpty && apPath != '/') {
              final apObj = DBusRemoteObject(
                client,
                name: 'org.freedesktop.NetworkManager',
                path: DBusObjectPath(apPath),
              );
              final ssidProp = await apObj.getProperty(
                'org.freedesktop.NetworkManager.AccessPoint',
                'Ssid',
              );
              final bytes = (ssidProp as DBusArray).children.map((c) => (c as DBusByte).value).toList();
              final ssidStr = cleanSsid(utf8.decode(bytes, allowMalformed: true));
              return NetworkConnectionInfo(
                isConnected: true,
                isWifi: true,
                isEthernet: hasEthernet,
                ssid: ssidStr.isNotEmpty ? ssidStr : null,
              );
            }
          }
        }
        if (hasEthernet) {
          return const NetworkConnectionInfo(
            isConnected: true,
            isWifi: false,
            isEthernet: true,
            ssid: null,
          );
        }
      } finally {
        await client.close();
      }
    } catch (_) {}

    // B. CLI fallback: iwgetid -r
    try {
      final iwResult = await Process.run('iwgetid', ['-r']).timeout(const Duration(seconds: 2));
      if (iwResult.exitCode == 0) {
        final ssid = cleanSsid(iwResult.stdout.toString());
        if (ssid.isNotEmpty) {
          return NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: ssid);
        }
      }
    } catch (_) {}

    // C. CLI fallback: nmcli -t -f active,ssid dev wifi
    try {
      final nmcliResult = await Process.run(
        'nmcli',
        ['-t', '-f', 'active,ssid', 'dev', 'wifi'],
      ).timeout(const Duration(seconds: 2));
      if (nmcliResult.exitCode == 0) {
        final lines = nmcliResult.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('yes:') || trimmed.startsWith('ja:')) {
            final ssid = cleanSsid(trimmed.substring(trimmed.indexOf(':') + 1));
            if (ssid.isNotEmpty) {
              return NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: ssid);
            }
          }
        }
      }
    } catch (_) {}

    return await _getGenericNetworkInfo();
  }

  // --- macOS Network Detection (networksetup + ipconfig) ---
  Future<NetworkConnectionInfo> _getMacOsNetworkInfo() async {
    try {
      // Find default Wi-Fi interface (usually en0)
      for (final iface in ['en0', 'en1', 'en2']) {
        final res = await Process.run('networksetup', ['-getairportnetwork', iface])
            .timeout(const Duration(seconds: 2));
        if (res.exitCode == 0) {
          final out = res.stdout.toString();
          // "Current Wi-Fi Network: MySSID"
          if (out.contains('Current Wi-Fi Network:')) {
            final ssid = cleanSsid(out.split('Current Wi-Fi Network:').last);
            if (ssid.isNotEmpty) {
              return NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: ssid);
            }
          }
        }
      }
    } catch (_) {}

    return await _getGenericNetworkInfo();
  }

  // --- Windows Network Detection (netsh wlan) ---
  Future<NetworkConnectionInfo> _getWindowsNetworkInfo() async {
    try {
      final res = await Process.run('netsh', ['wlan', 'show', 'interfaces'])
          .timeout(const Duration(seconds: 2));
      if (res.exitCode == 0) {
        final lines = res.stdout.toString().split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          final lower = trimmed.toLowerCase();
          // Matches "SSID : MyWiFi" (excluding BSSID)
          if (lower.startsWith('ssid') && !lower.startsWith('bssid')) {
            final parts = trimmed.split(':');
            if (parts.length >= 2) {
              final ssid = cleanSsid(parts.sublist(1).join(':'));
              if (ssid.isNotEmpty) {
                return NetworkConnectionInfo(isConnected: true, isWifi: true, ssid: ssid);
              }
            }
          }
        }
      }
    } catch (_) {}

    return await _getGenericNetworkInfo();
  }

  // --- Generic Network Interface Inspection ---
  Future<NetworkConnectionInfo> _getGenericNetworkInfo() async {
    try {
      final interfaces = await NetworkInterface.list();
      bool hasWifi = false;
      bool hasEthernet = false;
      bool hasCellular = false;

      for (final iface in interfaces) {
        final name = iface.name.toLowerCase();
        if (name.startsWith('wlan') || name.startsWith('wl') || name.startsWith('wifi')) {
          hasWifi = true;
        } else if (name.startsWith('eth') || name.startsWith('en')) {
          hasEthernet = true;
        } else if (name.startsWith('rmnet') || name.startsWith('pdp') || name.startsWith('ccmni')) {
          hasCellular = true;
        }
      }

      return NetworkConnectionInfo(
        isConnected: interfaces.isNotEmpty,
        isWifi: hasWifi,
        isEthernet: hasEthernet,
        isCellular: hasCellular,
        ssid: null,
      );
    } catch (_) {
      return const NetworkConnectionInfo(isConnected: true);
    }
  }
}
