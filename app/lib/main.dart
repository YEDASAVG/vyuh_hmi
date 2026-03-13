import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/config_loader.dart';
import 'config/dashboard_config.dart';
import 'config/hmi_theme_engine.dart';
import 'screens/alarm_history_screen.dart';
import 'screens/audit_trail_screen.dart';
import 'screens/batch_record_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_list_screen.dart';
import 'screens/history_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/plc_detail_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/websocket_service.dart';
import 'stores/dashboard_store.dart';
import 'widgets/inactivity_detector.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const HmiApp());
}

class HmiApp extends StatefulWidget {
  const HmiApp({super.key});

  @override
  State<HmiApp> createState() => _HmiAppState();
}

class _HmiAppState extends State<HmiApp> {
  DashboardConfig? _config;
  DashboardStore? _store;
  AuthService? _authService;
  int _currentIndex = 0;
  String? _loadError;
  bool _isAuthenticated = false;
  bool _checkingSession = true;

  // Startup flow: splash → onboarding (first time) → login
  _StartupPhase _phase = _StartupPhase.splash;
  bool _onboardingSeen = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      // Check onboarding status
      final prefs = await SharedPreferences.getInstance();
      _onboardingSeen = prefs.getBool('onboarding_seen') ?? false;

      final config =
          await ConfigLoader.load('configs/chemical_plant.json');

      // Create auth service with the config's server URL
      final authService = AuthService(baseUrl: config.server.httpUrl);

      // Try to restore previous session
      final wasAuthenticated = await authService.tryRestoreSession();

      final store = DashboardStore(
        config: config,
        ws: WebSocketService(url: config.server.wsUrl),
        api: ApiService(baseUrl: config.server.httpUrl),
      );

      if (wasAuthenticated) {
        store.api.setAuthToken(authService.currentUser?.token);
        store.ws.setAuthToken(authService.currentUser?.token);
        store.ws.onAuthFailed = _onWsAuthFailed;
        store.init();
      }

      setState(() {
        _config = config;
        _store = store;
        _authService = authService;
        _isAuthenticated = wasAuthenticated;
        _checkingSession = false;
      });
    } catch (e) {
      setState(() {
        _loadError = e.toString();
        _checkingSession = false;
      });
    }
  }

  void _onLoginSuccess() {
    // Recreate the store so we get a fresh WebSocket + API service.
    // (The previous store's WS was disposed on logout and can't reconnect.)
    final config = _config!;
    final store = DashboardStore(
      config: config,
      ws: WebSocketService(url: config.server.wsUrl),
      api: ApiService(baseUrl: config.server.httpUrl),
    );

    final token = _authService?.currentUser?.token;
    store.api.setAuthToken(token);
    store.ws.setAuthToken(token);
    store.ws.onAuthFailed = _onWsAuthFailed;
    store.init();

    setState(() {
      _store = store;
      _isAuthenticated = true;
    });
  }

  void _onLogout() async {
    await _authService?.logout();
    _store?.dispose();
    setState(() {
      _isAuthenticated = false;
      _currentIndex = 0;
    });
  }

  /// Called when the server rejects the WebSocket auth token
  /// (e.g. server restarted, session cleared). Force re-login.
  void _onWsAuthFailed() {
    _authService?.clearSavedSession();
    _store?.dispose();
    if (mounted) {
      setState(() {
        _isAuthenticated = false;
        _currentIndex = 0;
      });
    }
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ── Phase 1: Splash screen (always shown first) ──
    if (_phase == _StartupPhase.splash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: SplashScreen(
          onComplete: () {
            setState(() {
              _phase = _onboardingSeen
                  ? _StartupPhase.ready
                  : _StartupPhase.onboarding;
            });
          },
        ),
      );
    }

    // ── Phase 2: Onboarding (first launch only) ──
    if (_phase == _StartupPhase.onboarding) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: OnboardingScreen(
          onComplete: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setBool('onboarding_seen', true);
            setState(() => _phase = _StartupPhase.ready);
          },
        ),
      );
    }

    // ── Phase 3: App ready — loading / error / login / main ──

    // Still loading config or checking session
    if ((_config == null && _loadError == null) || _checkingSession) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          backgroundColor: Color(0xFF0C0C0E),
          body: Center(child: CircularProgressIndicator(color: Color(0xFFE8763A))),
        ),
      );
    }

    // Load error
    if (_loadError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: Text('Config error: $_loadError',
                style: const TextStyle(color: Colors.red)),
          ),
        ),
      );
    }

    final config = _config!;
    final store = _store!;
    final authService = _authService!;
    final theme = HmiThemeEngine(config.theme).build();

    // Not authenticated → show login screen
    if (!_isAuthenticated) {
      return ActiveTheme(
        colors: config.theme,
        child: MaterialApp(
          title: config.name,
          debugShowCheckedModeBanner: false,
          theme: theme,
          home: LoginScreen(
            authService: authService,
            onLoginSuccess: _onLoginSuccess,
          ),
        ),
      );
    }

    final user = authService.currentUser;

    return ActiveTheme(
      colors: config.theme,
      child: MaterialApp(
        title: config.name,
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InactivityDetector(
          timeoutMinutes: config.server.sessionTimeoutMinutes,
          onTimeout: _onLogout,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final screens = [
                DashboardScreen(
                    store: store,
                    config: config,
                    userRole: user?.role ?? 'viewer',
                    authService: authService,
                    onNavigateToDevices: () => setState(() => _currentIndex = 5)),
                PlcDetailScreen(store: store),
                HistoryScreen(store: store),
                AlarmHistoryScreen(
                    api: store.api,
                    canManage: user?.isOperator ?? false),
                BatchRecordScreen(api: store.api),
                DeviceListScreen(
                    api: store.api,
                    canManage: user?.isOperator ?? false),
                AuditTrailScreen(authService: authService),
              ];

              // ── Bottom Menu Bar (no sidebar — matches HMI wireframe) ──
              return Scaffold(
                body: IndexedStack(
                  index: _currentIndex,
                  children: screens,
                ),
                bottomNavigationBar: Container(
                  decoration: BoxDecoration(
                    color: config.theme.surface,
                    border: Border(
                      top: BorderSide(
                          color: config.theme.surfaceBorder, width: 1.5),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _bottomMenuItem(config, 0, Icons.dashboard_rounded,
                          'Dashboard'),
                      _bottomMenuItem(
                          config,
                          1,
                          Icons.precision_manufacturing_rounded,
                          'PLC Detail'),
                      _bottomMenuItem(
                          config, 2, Icons.history_rounded, 'History'),
                      _bottomMenuItem(
                          config, 3, Icons.warning_amber_rounded, 'Alarms'),
                      _bottomMenuItem(
                          config, 4, Icons.assignment_rounded, 'Batches'),
                      _bottomMenuItem(
                          config, 5, Icons.devices_other_rounded, 'Devices'),
                      _bottomMenuItem(
                          config, 6, Icons.security_rounded, 'Audit'),
                      // Profile avatar with logout
                      _buildProfileButton(context, config, user),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Top bar showing current user, role badge, and logout button.
  Widget _bottomMenuItem(
      DashboardConfig config, int index, IconData icon, String label) {
    final isSelected = _currentIndex == index;
    final color =
        isSelected ? config.theme.accent : config.theme.textMuted;
    return InkWell(
      onTap: () => setState(() => _currentIndex = index),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Logout button with confirmation dialog — prevents accidental logout.
  Widget _buildProfileButton(BuildContext navContext, DashboardConfig config, AuthUser? user) {
    final colors = config.theme;
    final initials = (user?.username ?? '?')
        .split(' ')
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .take(2)
        .join();

    return PopupMenuButton<String>(
      offset: const Offset(0, -180),
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.surfaceBorder, width: 1.5),
      ),
      onSelected: (value) {
        if (value == 'logout') _showLogoutConfirmation(navContext, config);
      },
      itemBuilder: (ctx) => [
        // User info header (non-selectable)
        PopupMenuItem(
          enabled: false,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                user?.username ?? 'Unknown',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: _roleColor(user?.role).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  (user?.role ?? 'viewer').toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _roleColor(user?.role),
                  ),
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        // Logout option
        PopupMenuItem(
          value: 'logout',
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.logout_rounded,
                  size: 22, color: Colors.red.shade300),
              const SizedBox(width: 12),
              Text(
                'Logout',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.red.shade300,
                ),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.accent.withValues(alpha: 0.15),
          border: Border.all(
              color: colors.accent.withValues(alpha: 0.4), width: 2),
        ),
        child: Center(
          child: Text(
            initials,
            style: GoogleFonts.outfit(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.accent,
            ),
          ),
        ),
      ),
    );
  }

  Color _roleColor(String? role) {
    return switch (role) {
      'admin' => Colors.amber.shade300,
      'operator' => Colors.blue.shade300,
      'viewer' => Colors.green.shade300,
      _ => Colors.grey.shade300,
    };
  }

  void _showLogoutConfirmation(BuildContext navContext, DashboardConfig config) {
    showDialog(
      context: navContext,
      barrierDismissible: false,
      builder: (ctx) {
        final colors = config.theme;
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.surfaceBorder, width: 1.5),
          ),
          icon: Icon(Icons.logout_rounded,
              size: 48, color: Colors.red.shade300),
          title: Text(
            'Confirm Logout',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          content: Text(
            'Are you sure you want to log out?\nYou will need to sign in again.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              fontSize: 18,
              color: Colors.white70,
            ),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actionsPadding:
              const EdgeInsets.only(left: 24, right: 24, bottom: 20),
          actions: [
            // Cancel — prominent so it's the safe default
            SizedBox(
              width: 160,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: colors.surfaceBorder, width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Cancel',
                    style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 16),
            // Logout — red, requires deliberate click
            SizedBox(
              width: 160,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _onLogout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('Logout',
                    style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Colors.white)),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Startup flow phases.
enum _StartupPhase { splash, onboarding, ready }
