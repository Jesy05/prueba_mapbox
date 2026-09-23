# flutter_mapbox

Prueba Flutter de captura de ubicación, cola local y mapa Mapbox para Vygo.

## Estado de los objetivos

- **Datos locales:** `lib/main.dart`, clases `LocationRecord` y `LocationDatabase`.
	Las ubicaciones quedan en SQLite con estado pendiente hasta recibir una respuesta
	HTTP exitosa.
- **Conectividad:** `VygoHomePage._refreshConnectivity` consulta el estado inicial y
	`onConnectivityChanged` reintenta al recuperar conexión.
- **Sincronización:** `VygoHomePage._syncPendingLocations` hace `POST` a
	`<VYGO_API_BASE_URL>/locations`. Si el backend no está configurado o falla, los
	datos permanecen pendientes.
- **Mapas:** `main` configura el token y `_nativeMap` crea el `MapWidget` de Mapbox
	en Android/iOS. En web, `_webMapPreview` usa `flutter_map` con tiles reales,
	zoom, arrastre y marcador para facilitar las pruebas en Chrome.
- **Segundo plano:** todavía requiere una decisión de producto: sincronización
	periódica con WorkManager/BackgroundTasks o tracking continuo con foreground
	service y permisos de ubicación en segundo plano.
- **Tracking continuo:** ya está integrado en `VygoHomePage._toggleTracking`.
	`Iniciar tracking` solicita actualizaciones cada 5 segundos, guarda cada punto
	en SQLite y reutiliza la sincronización HTTP. Android muestra una notificación
	persistente; iOS usa `UIBackgroundModes=location`.
- **Jornada de trabajo:** `VygoHomePage._toggleWorkday` permite iniciar y terminar
	la jornada. Al iniciar se activa el tracking; si pasan 30 minutos sin recibir
	actividad de ubicación, `_stopWorkday` detiene automáticamente la jornada y el
	tracking. El umbral se cambia en `_inactivityLimit`.

El intervalo de 5 segundos es una solicitud al sistema operativo. Android suele
respetarlo mientras el foreground service está activo, pero iOS puede espaciar o
limitar las actualizaciones por batería, permisos, cobertura o políticas del
sistema. La validación final debe hacerse en dispositivos físicos con la pantalla
apagada.

## Ejecutar con backend

```bash
flutter run --dart-define=VYGO_API_BASE_URL=https://api.example.com \
	--dart-define=MAPBOX_ACCESS_TOKEN=pk.example
```

El endpoint debe aceptar `POST /locations` con un objeto `{ "locations": [...] }`
y responder con un código HTTP 2xx únicamente después de guardar los datos.

En Android/iOS el token se configura con `MAPBOX_ACCESS_TOKEN`; no debe volver a
escribirse directamente en `lib/main.dart`.

La documentación detallada de archivos, flujo, permisos y sincronización está en
[`docs/IMPLEMENTACION.md`](docs/IMPLEMENTACION.md).

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
