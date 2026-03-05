import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppConfig {
  static final AppConfig _instance = AppConfig._internal();
  factory AppConfig() => _instance;

  AppConfig._internal();

  late SharedPreferences _prefs;

  // Keys
  static const String _keyTargetUrl = 'target_url';

  // Defaults
  static const String defaultTargetUrl = 'show.gethypr.com';
  static const String defaultTargetUrlProtocol = 'https://';

  // File-based config
  String? _adcsServer;
  String? _certTemplate;
  List<String>? _validPinningHashes;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromFile();
  }

  Future<void> _loadFromFile() async {
    try {
      final execPath = Platform.resolvedExecutable;
      final execDir = File(execPath).parent;
      final configPath = '${execDir.path}/hyprready.json';
      final configFile = File(configPath);

      debugPrint('Looking for config at: $configPath');

      if (await configFile.exists()) {
        final content = await configFile.readAsString();
        final json = jsonDecode(content);

        if (json is Map<String, dynamic>) {
          if (json.containsKey('targetUrl')) {
            // If file has targetUrl, it overrides or sets default?
            // Let's say if file has it, we might want to prioritize it or just use it if preference is unset.
            // For now, let's treat preferences as user-overrides and file as system-defaults if we wanted to be complex.
            // BUT, req says "this file can have the SSL Pinning URL...".
            // Let's blindly update preference if it's there? Or just expose it.
            // Simpler: If present in file, use it as current session override without saving to prefs?
            // actually, let's just set the _adcsServer and _certTemplate
            // And for targetUrl, let's perhaps leave it to Prefs?
            // "If the file does not exists then we will use the defaults for everything"
            // Let's assume file overrides prefs if present?
            if (json['targetUrl'] != null) {
              // We won't persist to prefs to avoid un-user-setting it permanently if they delete file?
              // Or maybe we should.
              // Let's just return it in getter if file loaded?
              // Complexity: The existing getter reads from Prefs.
              // Let's update getter to prefer file config if available.
              _fileTargetUrl = json['targetUrl'];
            }
          }
          if (json['adcsServer'] != null) _adcsServer = json['adcsServer'];
          if (json['certTemplate'] != null)
            _certTemplate = json['certTemplate'];
          if (json['validPinningHashes'] != null) {
            _validPinningHashes = List<String>.from(json['validPinningHashes']);
          }
        }
      }
    } catch (e) {
      debugPrint('Error loading config file: $e');
    }
  }

  String? _fileTargetUrl;

  String? get targetUrl {
    if (_fileTargetUrl != null && _fileTargetUrl!.isNotEmpty) {
      return _fileTargetUrl!;
    }
    return _prefs.getString(_keyTargetUrl) ?? defaultTargetUrl;
  }

  String? get adcsServer => _adcsServer;
  String? get certTemplate => _certTemplate;
  List<String>? get validPinningHashes => _validPinningHashes;

  Future<void> setTargetUrl(String url) async {
    await _prefs.setString(_keyTargetUrl, url);
  }

  /// specific validation logic
  static bool isValidUrl(String url) {
    if (url.isEmpty) return false;

    // Check if it matches exactly the default or ends with .hypr.com
    if (url == 'show.gethypr.com') return true;

    // Regex match for *.hypr.com OR *.gethypr.com
    final regex = RegExp(r'^([a-zA-Z0-9-]+\.)*(hypr|gethypr)\.com$');
    return regex.hasMatch(url);
  }
}
