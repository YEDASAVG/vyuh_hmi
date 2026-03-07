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
              final useRail = constraints.maxWidth >= 800;
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

              if (useRail) {
                // ── Desktop / Web: side NavigationRail ──
                return Scaffold(
                  body: Column(
                    children: [
                      _buildUserBar(config, user),
                      Expanded(
                        child: Row(
                          children: [
                            NavigationRail(
                              selectedIndex: _currentIndex,
                              onDestinationSelected: (i) =>
                                  setState(() => _currentIndex = i),
                              extended: constraints.maxWidth >= 1100,
                              minWidth: 64,
                              minExtendedWidth: 180,
                              backgroundColor: config.theme.surface,
                              selectedIconTheme: IconThemeData(
                                color: config.theme.accent,
                              ),
                              unselectedIconTheme: IconThemeData(
                                color: config.theme.textMuted,
                              ),
                              selectedLabelTextStyle: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: config.theme.accent,
                              ),
                              unselectedLabelTextStyle: GoogleFonts.outfit(
                                fontSize: 13,
                                color: config.theme.textSecondary,
                              ),
                              indicatorColor:
                                  config.theme.accent.withValues(alpha: 0.15),
                              destinations: const [
                                NavigationRailDestination(
                                  icon: Icon(Icons.dashboard_rounded),
                                  label: Text('Dashboard'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(
                                      Icons.precision_manufacturing_rounded),
                                  label: Text('PLC Detail'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.history_rounded),
                                  label: Text('History'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.warning_amber_rounded),
                                  label: Text('Alarms'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.assignment_rounded),
                                  label: Text('Batches'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.devices_other_rounded),
                                  label: Text('Devices'),
                                ),
                                NavigationRailDestination(
                                  icon: Icon(Icons.security_rounded),
                                  label: Text('Audit'),
                                ),
                              ],
                            ),
                            VerticalDivider(
                              width: 1,
                              thickness: 1,
                              color: config.theme.surfaceBorder,
                            ),
                            Expanded(
                              child: IndexedStack(
                                index: _currentIndex,
                                children: screens,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }

              // ── Mobile / Tablet: bottom NavigationBar ──
              final isCompact = constraints.maxWidth < 500;
              return Scaffold(
                body: Column(
                  children: [
                    _buildUserBar(config, user),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: screens,
                      ),
                    ),
                  ],
                ),
                bottomNavigationBar: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (i) =>
                      setState(() => _currentIndex = i),
                  labelBehavior: isCompact
                      ? NavigationDestinationLabelBehavior.alwaysHide
                      : NavigationDestinationLabelBehavior.alwaysShow,
                  height: isCompact ? 60 : 80,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.dashboard_rounded),
                      label: 'Dashboard',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.precision_manufacturing_rounded),
                      label: 'PLC',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      label: 'History',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.warning_amber_rounded),
                      label: 'Alarms',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.assignment_rounded),
                      label: 'Batches',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.devices_other_rounded),
                      label: 'Devices',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.security_rounded),
                      label: 'Audit',
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Top bar showing current user, role badge, and logout button.
  Widget _buildUserBar(DashboardConfig config, AuthUser? user) {
    if (user == null) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        left: 16,
        right: 8,
        bottom: 8,
      ),
      decoration: BoxDecoration(
        color: config.theme.surface,
        border: Border(
          bottom: BorderSide(color: config.theme.surfaceBorder),
        ),
      ),
      child: Row(
        children: [
          // App name
          Flexible(
            child: Text(
              config.name,
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: config.theme.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // User info
          Icon(Icons.person_outline_rounded,
              size: 16, color: config.theme.textSecondary),
          const SizedBox(width: 4),
          Text(
            user.username,
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: config.theme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          // Role badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: _roleColor(user.role).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              user.role.toUpperCase(),
              style: GoogleFonts.dmMono(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _roleColor(user.role),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Logout
          IconButton(
            icon: Icon(Icons.logout_rounded,
                size: 18, color: config.theme.textSecondary),
            onPressed: _onLogout,
            tooltip: 'Sign out',
          ),
        ],
      ),
    );
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'admin':
        return Colors.redAccent;
      case 'operator':
        return Colors.amber;
      default:
        return Colors.cyan;
    }
  }
}

/// Startup flow phases.
enum _StartupPhase { splash, onboarding, ready }
