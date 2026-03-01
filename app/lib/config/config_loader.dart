import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'dashboard_config.dart';

/// Loads a [DashboardConfig] from a JSON asset file.
///
/// Usage:
///   final config = await ConfigLoader.load('configs/pharma_reactor.json');
class ConfigLoader {
  /// Load config from an asset path relative to the `assets/` folder.
  static Future<DashboardConfig> load(String assetPath) async {
    final jsonString = await rootBundle.loadString('assets/$assetPath');
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return DashboardConfig.fromJson(json);
  }

  /// Load config from a raw JSON string (useful for tests or remote configs).
  static DashboardConfig fromString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return DashboardConfig.fromJson(json);
  }
}
