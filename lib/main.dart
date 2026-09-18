import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  MapboxOptions.setAccessToken('pk.eyJ1IjoiaGFsbGV5eWUiLCJhIjoiY210dXF3bjI4MG40cDJ4bXp4bDF6N3NpMiJ9.oLyUDF6qh_kY9jBIOT2Ong');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  MapboxMap? mapboxMap;
  PointAnnotationManager? pointAnnotationManager;

  void _onMapCreated(MapboxMap controller) async {
    mapboxMap = controller;

    pointAnnotationManager =
        await controller.annotations.createPointAnnotationManager();

    _addSampleMarker(Point(coordinates: Position(-86.2684, 12.1364)));
  }

  void _addSampleMarker(Point point) {
    pointAnnotationManager?.create(
      PointAnnotationOptions(
        geometry: point,
        iconSize: 1.5,
      ),
    );
  }

  void _moveToLocation(double lng, double lat) {
    mapboxMap?.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(lng, lat)),
        zoom: 14.0,
      ),
      MapAnimationOptions(duration: 1500),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapbox Sandbox'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: () => _moveToLocation(-86.2684, 12.1364),
            tooltip: 'Centrar',
          ),
        ],
      ),
      body: MapWidget(
        viewport: CameraViewportState(
          center: Point(coordinates: Position(-86.2684, 12.1364)),
          zoom: 12.0,
        ),
        styleUri: MapboxStyles.MAPBOX_STREETS,
        onMapCreated: _onMapCreated,
      ),
    );
  }
}
