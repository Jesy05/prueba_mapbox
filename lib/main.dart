import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_map/flutter_map.dart' as flutter_map;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart' as geolocator;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

const _neonGreen = Color(0xFF39FF14);
const _lime = Color(0xFFADFF2F);
const _ink = Color(0xFF0A0A0A);
final _mapCenter = Position(-86.2684, 12.1364);
const _apiBaseUrl = String.fromEnvironment('VYGO_API_BASE_URL');
const _mapboxAccessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');
const _inactivityLimit = Duration(
  seconds: int.fromEnvironment('INACTIVITY_LIMIT_SECONDS', defaultValue: 1800),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && _mapboxAccessToken.isNotEmpty) {
    MapboxOptions.setAccessToken(_mapboxAccessToken);
  }
  runApp(const VygoApp());
}

class VygoApp extends StatelessWidget {
  const VygoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vygo',
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _neonGreen,
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: Colors.white,
      ),
      home: const VygoHomePage(),
    );
  }
}

class LocationRecord {
  const LocationRecord({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.synced,
  });

  final int? id;
  final double latitude;
  final double longitude;
  final String createdAt;
  final bool synced;

  Map<String, Object?> toMap() => {
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'created_at': createdAt,
    'synced': synced ? 1 : 0,
  };

  factory LocationRecord.fromMap(Map<String, Object?> map) => LocationRecord(
    id: map['id'] as int?,
    latitude: map['latitude'] as double,
    longitude: map['longitude'] as double,
    createdAt: map['created_at'] as String,
    synced: map['synced'] == 1,
  );
}
class LocationDatabase {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    final databasesPath = await getDatabasesPath();
    _database = await openDatabase(
      path.join(databasesPath, 'vygo.db'),
      version: 1,
      onCreate: (database, version) => database.execute('''
        CREATE TABLE locations(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          latitude REAL NOT NULL,
          longitude REAL NOT NULL,
          created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      '''),
    );
    return _database!;
  }

  Future<int> save(LocationRecord record) async =>
      (await database).insert('locations', record.toMap());

  Future<List<LocationRecord>> pending() async {
    final rows = await (await database).query(
      'locations',
      where: 'synced = ?',
      whereArgs: [0],
      orderBy: 'created_at ASC',
    );
    return rows.map(LocationRecord.fromMap).toList();
  }

  Future<void> markSynced(Iterable<int> ids) async {
    final databaseInstance = await database;
    await databaseInstance.transaction((transaction) async {
      for (final id in ids) {
        await transaction.update(
          'locations',
          {'synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    });
  }
}

class VygoHomePage extends StatefulWidget {
  const VygoHomePage({super.key});

  @override
  State<VygoHomePage> createState() => _VygoHomePageState();
}

class _VygoHomePageState extends State<VygoHomePage> {
  final _database = LocationDatabase();
  MapboxMap? _map;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<geolocator.Position>? _locationSubscription;
  Timer? _inactivityTimer;
  int _pendingCount = 0;
  bool _isOnline = true;
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isTracking = false;
  bool _isWorking = false;
  DateTime? _lastActivityAt;
  String _message = 'Listo para comenzar';

  @override
  void initState() {
    super.initState();
    _loadQueue();
    _refreshConnectivity();
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      final online = results.any((result) => result != ConnectivityResult.none);
      if (!mounted) return;
      setState(() => _isOnline = online);
      if (online) {
        _syncPendingLocations();
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _locationSubscription?.cancel();
    _inactivityTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadQueue() async {
    if (kIsWeb) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      return;
    }
    final pending = await _database.pending();
    if (!mounted) return;
    setState(() {
      _pendingCount = pending.length;
      _isLoading = false;
    });
  }

  Future<void> _refreshConnectivity() async {
    final results = await Connectivity().checkConnectivity();
    final online = results.any((result) => result != ConnectivityResult.none);
    if (!mounted) return;
    setState(() => _isOnline = online);
    if (online) await _syncPendingLocations();
  }

  Future<void> _captureLocation() async {
    setState(() => _message = 'Buscando ubicación...');
    var permission = await geolocator.Geolocator.checkPermission();
    if (permission == geolocator.LocationPermission.denied) {
      permission = await geolocator.Geolocator.requestPermission();
    }
    if (permission == geolocator.LocationPermission.denied ||
        permission == geolocator.LocationPermission.deniedForever) {
      setState(() => _message = 'Permiso de ubicación requerido');
      return;
    }

    final position = await geolocator.Geolocator.getCurrentPosition();
    await _savePosition(position);
    _map?.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position(position.longitude, position.latitude),
        ),
        zoom: 15,
      ),
      MapAnimationOptions(duration: 900),
    );
    await _loadQueue();
    if (mounted) {
      setState(
        () => _message = _isOnline
            ? 'Ubicación guardada y en cola'
            : 'Guardada sin conexión',
      );
    }
    if (_isOnline) {
      await _syncPendingLocations();
    }
  }

  Future<void> _savePosition(geolocator.Position position) async {
    if (!kIsWeb) {
      await _database.save(
        LocationRecord(
          id: null,
          latitude: position.latitude,
          longitude: position.longitude,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          synced: false,
        ),
      );
    }
  }

  Future<void> _toggleTracking() async {
    if (_isTracking) {
      await _locationSubscription?.cancel();
      _locationSubscription = null;
      if (mounted) {
        setState(() {
          _isTracking = false;
          _message = 'Tracking detenido';
        });
      }
      return;
    }

    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _isTracking = true;
          _message = 'Tracking de prueba activo';
        });
      }
      return;
    }

    var permission = await geolocator.Geolocator.checkPermission();
    if (permission == geolocator.LocationPermission.denied) {
      permission = await geolocator.Geolocator.requestPermission();
    }
    if (permission != geolocator.LocationPermission.always &&
        permission != geolocator.LocationPermission.whileInUse) {
      if (mounted) setState(() => _message = 'Permiso de ubicación requerido');
      return;
    }
    if (!await geolocator.Geolocator.isLocationServiceEnabled()) {
      if (mounted) setState(() => _message = 'Activa el servicio de ubicación');
      return;
    }

    final locationSettings = switch (defaultTargetPlatform) {
      TargetPlatform.android => geolocator.AndroidSettings(
        accuracy: geolocator.LocationAccuracy.high,
        distanceFilter: 0,
        intervalDuration: const Duration(seconds: 5),
        foregroundNotificationConfig:
            const geolocator.ForegroundNotificationConfig(
          notificationTitle: 'Vygo está registrando tu ruta',
          notificationText: 'La ubicación se actualiza cada 5 segundos',
          enableWakeLock: true,
        ),
      ),
      TargetPlatform.iOS => geolocator.AppleSettings(
        accuracy: geolocator.LocationAccuracy.high,
        activityType: geolocator.ActivityType.automotiveNavigation,
        distanceFilter: 0,
        pauseLocationUpdatesAutomatically: false,
        showBackgroundLocationIndicator: true,
      ),
      _ => const geolocator.LocationSettings(
        accuracy: geolocator.LocationAccuracy.high,
        distanceFilter: 0,
      ),
    };

    _locationSubscription = geolocator.Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((position) async {
      _registerActivity();
      await _savePosition(position);
      await _loadQueue();
      if (_isOnline) {
        await _syncPendingLocations();
      }
      if (mounted) {
        setState(
          () => _message = 'Tracking activo: última ubicación guardada',
        );
      }
    });
    if (mounted) {
      setState(() {
        _isTracking = true;
        _message = 'Tracking activo cada 5 segundos';
      });
    }
  }

  Future<void> _toggleWorkday() async {
    if (_isWorking) {
      await _stopWorkday('Jornada terminada');
      return;
    }
    await _startWorkday();
  }

  Future<void> _startWorkday() async {
    if (_isWorking) return;
    _lastActivityAt = DateTime.now();
    _inactivityTimer?.cancel();
    _inactivityTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final lastActivity = _lastActivityAt;
      if (lastActivity != null &&
          DateTime.now().difference(lastActivity) >= _inactivityLimit) {
        _stopWorkday('Jornada terminada por inactividad');
      }
    });
    if (mounted) {
      setState(() {
        _isWorking = true;
        _message = 'Jornada activa';
      });
    }
    await _toggleTracking();
    if (!_isTracking) {
      await _stopWorkday('No se pudo iniciar el tracking');
    }
  }

  Future<void> _stopWorkday(String message) async {
    _inactivityTimer?.cancel();
    _inactivityTimer = null;
    _lastActivityAt = null;
    if (_isTracking) await _toggleTracking();
    if (mounted) {
      setState(() {
        _isWorking = false;
        _message = message;
      });
    }
  }

  void _registerActivity() {
    if (_isWorking) _lastActivityAt = DateTime.now();
  }

  void _simulateActivity() {
    if (!_isWorking) return;
    _registerActivity();
    setState(() => _message = 'Actividad simulada; jornada continúa activa');
  }

  Future<void> _syncPendingLocations() async {
    if (!_isOnline || kIsWeb || _isSyncing) return;
    if (_apiBaseUrl.isEmpty) {
      if (mounted) {
        setState(() => _message = 'Pendiente: configura VYGO_API_BASE_URL');
      }
      return;
    }
    final pending = await _database.pending();
    if (pending.isEmpty) return;
    _isSyncing = true;
    try {
      final response = await http
          .post(
            Uri.parse('$_apiBaseUrl/locations'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode({
              'locations': pending
                  .map(
                    (item) => {
                      'id': item.id,
                      'latitude': item.latitude,
                      'longitude': item.longitude,
                      'created_at': item.createdAt,
                    },
                  )
                  .toList(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      await _database.markSynced(
        pending.where((item) => item.id != null).map((item) => item.id!),
      );
      await _loadQueue();
      if (mounted) setState(() => _message = 'Ruta sincronizada con Vygo');
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Sincronización pendiente; se reintentará');
      }
    } finally {
      _isSyncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          kIsWeb ? _webMapPreview() : _nativeMap(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Row(
                children: [_brandMark(), const Spacer(), _connectionPill()],
              ),
            ),
          ),
          Positioned(left: 18, right: 18, bottom: 18, child: _deliveryPanel()),
          if (_isLoading)
            const Center(child: CircularProgressIndicator(color: _neonGreen)),
        ],
      ),
    );
  }

  Widget _nativeMap() => MapWidget(
    key: const ValueKey('vygo-map'),
    viewport: CameraViewportState(
      center: Point(coordinates: _mapCenter),
      zoom: 12,
    ),
    styleUri: MapboxStyles.MAPBOX_STREETS,
    onMapCreated: (mapboxMap) => _map = mapboxMap,
  );

  Widget _webMapPreview() => Container(
    color: const Color(0xFFEAF4E8),
    child: Stack(
      children: [
        flutter_map.FlutterMap(
          options: flutter_map.MapOptions(
            initialCenter: LatLng(12.1364, -86.2684),
            initialZoom: 13,
          ),
          children: [
            flutter_map.TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.flutter_mapbox',
            ),
            flutter_map.MarkerLayer(
              markers: [
                flutter_map.Marker(
                  point: LatLng(12.1364, -86.2684),
                  width: 56,
                  height: 56,
                  child: Icon(
                    Icons.location_on,
                    color: _isWorking ? _neonGreen : _lime,
                    size: 52,
                  ),
                ),
              ],
            ),
          ],
        ),
        Positioned(
          top: 96,
          left: 18,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .94),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 14),
              ],
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.map_outlined, color: _ink, size: 18),
                SizedBox(width: 8),
                Text(
                  'Mapa interactivo · arrastra y acerca',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          right: 18,
          top: 96,
          child: _mapLegend(),
        ),
      ],
    ),
  );

  Widget _mapLegend() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(14),
      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 14)],
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: _isWorking ? _neonGreen : _lime),
        const SizedBox(width: 6),
        Text(
          _isWorking ? 'Jornada activa' : 'Jornada inactiva',
          style: const TextStyle(color: _ink, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );

  Widget _brandMark() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _neonGreen.withValues(alpha: .5)),
    ),
    child: const Text(
      'VYGO',
      style: TextStyle(
        color: _ink,
        fontSize: 22,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
      ),
    ),
  );

  Widget _connectionPill() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .96),
      border: Border.all(color: _ink.withValues(alpha: .12)),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, size: 9, color: _isOnline ? _neonGreen : _lime),
        const SizedBox(width: 7),
        Text(
          _isOnline ? 'EN LÍNEA' : 'SIN CONEXIÓN',
          style: const TextStyle(
            color: _ink,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );

  Widget _deliveryPanel() => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .97),
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: _ink.withValues(alpha: .1)),
      boxShadow: const [
        BoxShadow(color: Colors.black26, blurRadius: 22, offset: Offset(0, 8)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Tu ruta de hoy',
                style: TextStyle(
                  color: _ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_pendingCount > 0) _pendingBadge(),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _message,
          style: TextStyle(
            color: _ink.withValues(alpha: .64),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton.icon(
            onPressed: _toggleWorkday,
            icon: Icon(_isWorking ? Icons.stop_circle : Icons.play_circle),
            label: Text(_isWorking ? 'Terminar jornada' : 'Iniciar jornada'),
            style: FilledButton.styleFrom(
                backgroundColor: _isWorking ? Colors.redAccent : _lime,
              foregroundColor: _ink,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isWorking
              ? 'Se desactiva tras ${_inactivityLimit.inMinutes} min sin actividad'
              : 'Inicia la jornada para comenzar el tracking',
          style: TextStyle(
            color: _ink.withValues(alpha: .55),
            fontSize: 12,
          ),
        ),
        if (kIsWeb) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: TextButton.icon(
              onPressed: _isWorking ? _simulateActivity : null,
              icon: const Icon(Icons.touch_app),
              label: const Text('Simular actividad'),
              style: TextButton.styleFrom(
                foregroundColor: _ink,
                backgroundColor: _neonGreen.withValues(alpha: .16),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: _toggleTracking,
            icon: Icon(_isTracking ? Icons.stop : Icons.my_location),
            label: Text(_isTracking ? 'Detener tracking' : 'Iniciar tracking'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: FilledButton.icon(
            onPressed: _captureLocation,
            icon: const Icon(Icons.location_searching),
            label: const Text(
              'Registrar ubicación',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _neonGreen,
              foregroundColor: _ink,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pendingBadge() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _lime,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      '$_pendingCount pendiente${_pendingCount == 1 ? '' : 's'}',
      style: const TextStyle(
        color: _ink,
        fontSize: 11,
        fontWeight: FontWeight.bold,
      ),
    ),
  );
}

