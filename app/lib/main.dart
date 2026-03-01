import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/config_loader.dart';
import 'config/dashboard_config.dart';
import 'config/hmi_theme_engine.dart';
import 'screens/dashboard_screen.dart';
import 'screens/device_list_screen.dart';
import 'screens/history_screen.dart';
import 'screens/plc_detail_screen.dart';
import 'services/api_service.dart';
import 'services/websocket_service.dart';
import 'stores/dashboard_store.dart';

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
  int _currentIndex = 0;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final config =
          await ConfigLoader.load('configs/chemical_plant.json');
      final store = DashboardStore(
        config: config,
        ws: WebSocketService(url: config.server.wsUrl),
        api: ApiService(baseUrl: config.server.httpUrl),
      );
      store.init();
      setState(() {
        _config = config;
        _store = store;
      });
    } catch (e) {
      setState(() => _loadError = e.toString());
    }
  }

  @override
  void dispose() {
    _store?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Still loading
    if (_config == null && _loadError == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
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
    final theme = HmiThemeEngine(config.theme).build();
    final api = ApiService(baseUrl: config.server.httpUrl);

    return ActiveTheme(
      colors: config.theme,
      child: MaterialApp(
        title: config.name,
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              DashboardScreen(store: store, config: config),
              PlcDetailScreen(store: store),
              HistoryScreen(store: store),
              DeviceListScreen(api: api),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (i) => setState(() => _currentIndex = i),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_rounded),
                label: 'Dashboard',
              ),
              NavigationDestination(
                icon: Icon(Icons.precision_manufacturing_rounded),
                label: 'PLC Detail',
              ),
              NavigationDestination(
                icon: Icon(Icons.history_rounded),
                label: 'History',
              ),
              NavigationDestination(
                icon: Icon(Icons.devices_other_rounded),
                label: 'Devices',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
