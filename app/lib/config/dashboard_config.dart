import 'package:flutter/material.dart';

// ── Top-level config ────────────────────────────────────────────────

class DashboardConfig {
  final String id;
  final String name;
  final String version;
  final ServerConfig server;
  final DeviceRef device;
  final ThemeConfig theme;
  final List<RegisterConfig> registers;
  final List<AlarmThreshold> alarms;
  final LayoutConfig dashboard;

  const DashboardConfig({
    required this.id,
    required this.name,
    this.version = '1.0',
    required this.server,
    required this.device,
    required this.theme,
    required this.registers,
    this.alarms = const [],
    required this.dashboard,
  });

  factory DashboardConfig.fromJson(Map<String, dynamic> json) {
    return DashboardConfig(
      id: json['id'] as String,
      name: json['name'] as String,
      version: json['version'] as String? ?? '1.0',
      server: ServerConfig.fromJson(json['server'] as Map<String, dynamic>),
      device: DeviceRef.fromJson(json['device'] as Map<String, dynamic>),
      theme: ThemeConfig.fromJson(json['theme'] as Map<String, dynamic>),
      registers: (json['registers'] as List)
          .map((e) => RegisterConfig.fromJson(e as Map<String, dynamic>))
          .toList(),
      alarms: (json['alarms'] as List?)
              ?.map((e) => AlarmThreshold.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      dashboard:
          LayoutConfig.fromJson(json['dashboard'] as Map<String, dynamic>),
    );
  }

  /// Lookup a register config by address.
  RegisterConfig? registerByAddress(int address) {
    try {
      return registers.firstWhere((r) => r.address == address);
    } catch (_) {
      return null;
    }
  }

  /// Lookup a register config by key name.
  RegisterConfig? registerByKey(String key) {
    try {
      return registers.firstWhere((r) => r.key == key);
    } catch (_) {
      return null;
    }
  }
}

// ── Server connection ───────────────────────────────────────────────

class ServerConfig {
  final String httpUrl;
  final String wsUrl;

  const ServerConfig({required this.httpUrl, required this.wsUrl});

  factory ServerConfig.fromJson(Map<String, dynamic> json) {
    return ServerConfig(
      httpUrl: json['httpUrl'] as String,
      wsUrl: json['wsUrl'] as String,
    );
  }
}

// ── Device reference ────────────────────────────────────────────────

class DeviceRef {
  final String id;

  const DeviceRef({required this.id});

  factory DeviceRef.fromJson(Map<String, dynamic> json) {
    return DeviceRef(id: json['id'] as String);
  }
}

// ── Theme colors ────────────────────────────────────────────────────

class ThemeConfig {
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceBorder;
  final Color healthy;
  final Color warning;
  final Color danger;
  final Color info;

  const ThemeConfig({
    this.accent = const Color(0xFFE8763A),
    this.background = const Color(0xFF0C0C0E),
    this.surface = const Color(0xFF18181C),
    this.surfaceBorder = const Color(0xFF2A2A32),
    this.healthy = const Color(0xFF3DD68C),
    this.warning = const Color(0xFFE8B63A),
    this.danger = const Color(0xFFE84057),
    this.info = const Color(0xFF5B9CF5),
  });

  factory ThemeConfig.fromJson(Map<String, dynamic> json) {
    return ThemeConfig(
      accent: _parseColor(json['accent']) ?? const Color(0xFFE8763A),
      background: _parseColor(json['background']) ?? const Color(0xFF0C0C0E),
      surface: _parseColor(json['surface']) ?? const Color(0xFF18181C),
      surfaceBorder:
          _parseColor(json['surfaceBorder']) ?? const Color(0xFF2A2A32),
      healthy: _parseColor(json['healthy']) ?? const Color(0xFF3DD68C),
      warning: _parseColor(json['warning']) ?? const Color(0xFFE8B63A),
      danger: _parseColor(json['danger']) ?? const Color(0xFFE84057),
      info: _parseColor(json['info']) ?? const Color(0xFF5B9CF5),
    );
  }

  /// Dim version of a color (~20% opacity) for backgrounds.
  Color get accentDim => accent.withValues(alpha: 0.2);
  Color get healthyDim => healthy.withValues(alpha: 0.2);
  Color get warningDim => warning.withValues(alpha: 0.2);
  Color get dangerDim => danger.withValues(alpha: 0.2);

  // Text colors derived from background brightness.
  Color get textPrimary => const Color(0xFFE8E8EC);
  Color get textSecondary => const Color(0xFF8B8B96);
  Color get textMuted => const Color(0xFF55555F);
  Color get surfaceRaised => const Color(0xFF222228);
}

Color? _parseColor(dynamic value) {
  if (value == null) return null;
  final hex = (value as String).replaceAll('#', '');
  if (hex.length == 6) return Color(int.parse('FF$hex', radix: 16));
  if (hex.length == 8) return Color(int.parse(hex, radix: 16));
  return null;
}

// ── Register definition ─────────────────────────────────────────────

class RegisterConfig {
  final int address;
  final String key;
  final String label;
  final String unit;
  final Color color;
  final double divisor;
  final bool writable;
  final String? type; // "batch_state", "progress", or null (numeric)

  const RegisterConfig({
    required this.address,
    required this.key,
    required this.label,
    this.unit = '',
    this.color = const Color(0xFFE8763A),
    this.divisor = 1,
    this.writable = false,
    this.type,
  });

  factory RegisterConfig.fromJson(Map<String, dynamic> json) {
    return RegisterConfig(
      address: json['address'] as int,
      key: json['key'] as String,
      label: json['label'] as String,
      unit: json['unit'] as String? ?? '',
      color: _parseColor(json['color']) ?? const Color(0xFFE8763A),
      divisor: (json['divisor'] as num?)?.toDouble() ?? 1,
      writable: json['writable'] as bool? ?? false,
      type: json['type'] as String?,
    );
  }

  /// Apply divisor to a raw register value.
  double applyDivisor(double raw) => raw / divisor;
}

// ── Alarm threshold ─────────────────────────────────────────────────

class AlarmThreshold {
  final int register;
  final String label;
  final double? warnHigh;
  final double? critHigh;
  final double? warnLow;
  final double? critLow;

  const AlarmThreshold({
    required this.register,
    required this.label,
    this.warnHigh,
    this.critHigh,
    this.warnLow,
    this.critLow,
  });

  factory AlarmThreshold.fromJson(Map<String, dynamic> json) {
    return AlarmThreshold(
      register: json['register'] as int,
      label: json['label'] as String,
      warnHigh: (json['warnHigh'] as num?)?.toDouble(),
      critHigh: (json['critHigh'] as num?)?.toDouble(),
      warnLow: (json['warnLow'] as num?)?.toDouble(),
      critLow: (json['critLow'] as num?)?.toDouble(),
    );
  }
}

// ── Dashboard layout ────────────────────────────────────────────────

class LayoutConfig {
  final GaugeConfig? gauge;
  final BatchStateConfig? batchState;
  final List<String> statCards; // register keys
  final List<String> charts; // register keys
  final ControlsConfig? controls;

  const LayoutConfig({
    this.gauge,
    this.batchState,
    this.statCards = const [],
    this.charts = const [],
    this.controls,
  });

  factory LayoutConfig.fromJson(Map<String, dynamic> json) {
    return LayoutConfig(
      gauge: json['gauge'] != null
          ? GaugeConfig.fromJson(json['gauge'] as Map<String, dynamic>)
          : null,
      batchState: json['batchState'] != null
          ? BatchStateConfig.fromJson(
              json['batchState'] as Map<String, dynamic>)
          : null,
      statCards: (json['statCards'] as List?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      charts:
          (json['charts'] as List?)?.map((e) => e as String).toList() ?? [],
      controls: json['controls'] != null
          ? ControlsConfig.fromJson(json['controls'] as Map<String, dynamic>)
          : null,
    );
  }
}

class GaugeConfig {
  final String registerKey;
  final double max;
  final double warningThreshold;
  final double dangerThreshold;

  const GaugeConfig({
    required this.registerKey,
    this.max = 100,
    this.warningThreshold = 80,
    this.dangerThreshold = 95,
  });

  factory GaugeConfig.fromJson(Map<String, dynamic> json) {
    return GaugeConfig(
      registerKey: json['registerKey'] as String,
      max: (json['max'] as num?)?.toDouble() ?? 100,
      warningThreshold: (json['warningThreshold'] as num?)?.toDouble() ?? 80,
      dangerThreshold: (json['dangerThreshold'] as num?)?.toDouble() ?? 95,
    );
  }
}

class BatchStateConfig {
  final String stateRegisterKey;
  final String progressRegisterKey;

  const BatchStateConfig({
    required this.stateRegisterKey,
    required this.progressRegisterKey,
  });

  factory BatchStateConfig.fromJson(Map<String, dynamic> json) {
    return BatchStateConfig(
      stateRegisterKey: json['stateRegisterKey'] as String,
      progressRegisterKey: json['progressRegisterKey'] as String,
    );
  }
}

class ControlsConfig {
  final EmergencyStopConfig? emergencyStop;
  final AgitatorConfig? agitator;

  const ControlsConfig({this.emergencyStop, this.agitator});

  factory ControlsConfig.fromJson(Map<String, dynamic> json) {
    return ControlsConfig(
      emergencyStop: json['emergencyStop'] != null
          ? EmergencyStopConfig.fromJson(
              json['emergencyStop'] as Map<String, dynamic>)
          : null,
      agitator: json['agitator'] != null
          ? AgitatorConfig.fromJson(json['agitator'] as Map<String, dynamic>)
          : null,
    );
  }
}

class EmergencyStopConfig {
  final int register;
  final int stopValue;
  final int restartValue;

  const EmergencyStopConfig({
    required this.register,
    this.stopValue = 0,
    this.restartValue = 1,
  });

  factory EmergencyStopConfig.fromJson(Map<String, dynamic> json) {
    return EmergencyStopConfig(
      register: json['register'] as int,
      stopValue: json['stopValue'] as int? ?? 0,
      restartValue: json['restartValue'] as int? ?? 1,
    );
  }
}

class AgitatorConfig {
  final int register;
  final int min;
  final int max;

  const AgitatorConfig({
    required this.register,
    this.min = 0,
    this.max = 500,
  });

  factory AgitatorConfig.fromJson(Map<String, dynamic> json) {
    return AgitatorConfig(
      register: json['register'] as int,
      min: json['min'] as int? ?? 0,
      max: json['max'] as int? ?? 500,
    );
  }
}
