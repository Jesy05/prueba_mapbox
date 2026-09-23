# Documentacion de la implementacion Vygo

## 1. Objetivo

Esta prueba Flutter permite registrar ubicaciones, conservarlas localmente cuando no hay backend o conectividad, sincronizarlas cuando sea posible y operar una jornada de trabajo con tracking continuo.

El flujo soporta dos experiencias:

- Android/iOS: mapa nativo de Mapbox y tracking con Geolocator.
- Web: mapa interactivo con `flutter_map` y una simulacion de actividad para probar la jornada sin depender del GPS del navegador.

## 2. Archivos editados

### `lib/main.dart`

Es el archivo principal y contiene el modelo, persistencia, conectividad, tracking, jornada, sincronizacion y UI.

#### Configuracion por ambiente

Se agregaron estas constantes:

- `_apiBaseUrl`: lee `VYGO_API_BASE_URL` con `--dart-define`.
- `_mapboxAccessToken`: lee `MAPBOX_ACCESS_TOKEN` con `--dart-define`.
- `_inactivityLimit`: usa `INACTIVITY_LIMIT_SECONDS` y por defecto equivale a 30 minutos.

Esto permite cambiar backend, token y tiempo de prueba sin editar el codigo.

#### Datos locales

`LocationRecord` representa una ubicacion con identificador, latitud, longitud, fecha UTC y bandera `synced`.

`LocationDatabase` abre `vygo.db` y crea la tabla `locations`. Sus operaciones son:

- `save`: inserta una ubicacion pendiente.
- `pending`: consulta pendientes ordenadas por fecha.
- `markSynced`: marca un lote como sincronizado dentro de una transaccion SQLite.

El resultado es una cola offline-first. Una ubicacion no se elimina ni se marca como enviada hasta que el backend confirme correctamente.

#### Conectividad

`_refreshConnectivity` consulta el estado al iniciar la pantalla con `checkConnectivity()`.

Tambien se registra `Connectivity().onConnectivityChanged`. Cuando vuelve una red disponible, la app llama a `_syncPendingLocations`.

La conectividad solo indica la interfaz de red. La comprobacion final ocurre al intentar la peticion HTTP al backend.

#### Registro manual

`_captureLocation` solicita permisos, obtiene la posicion actual, llama a `_savePosition`, mueve el mapa hacia la coordenada y trata de sincronizar.

Esta funcion permite probar una captura aislada aunque la jornada no este activa.

#### Tracking continuo

`_toggleTracking` inicia o detiene `Geolocator.getPositionStream`.

En Android configura:

- precision alta;
- `distanceFilter: 0`;
- intervalo solicitado de 5 segundos;
- notificacion foreground;
- wake lock.

En iOS configura:

- precision alta;
- actividad de navegacion automotriz;
- sin pausa automatica;
- indicador de ubicacion en segundo plano.

Cada posicion recibida sigue este flujo:

1. llama a `_registerActivity`;
2. guarda la posicion mediante `_savePosition`;
3. actualiza el contador de pendientes;
4. intenta sincronizar si hay conectividad.

El intervalo de cinco segundos es una solicitud al sistema operativo. Android suele aproximarse al intervalo mientras el servicio foreground esta activo. iOS puede espaciarlo por bateria, cobertura, permisos o politicas del sistema.

#### Jornada de trabajo

`_toggleWorkday` controla los botones `Iniciar jornada` y `Terminar jornada`.

`_startWorkday`:

1. guarda la hora actual en `_lastActivityAt`;
2. crea un temporizador que revisa inactividad cada minuto;
3. marca `_isWorking` como verdadero;
4. inicia el tracking;
5. revierte el estado si el tracking no puede comenzar.

`_stopWorkday`:

1. cancela el temporizador;
2. limpia `_lastActivityAt`;
3. detiene el stream de ubicacion;
4. marca la jornada como inactiva;
5. muestra el motivo al usuario.

`_registerActivity` actualiza la hora de actividad cada vez que llega una posicion. Si la diferencia supera `_inactivityLimit`, el temporizador llama a `_stopWorkday` y detiene automaticamente la jornada.

Para probar la auto-desactivacion rapidamente se puede usar:

```powershell
flutter run -d chrome --dart-define=INACTIVITY_LIMIT_SECONDS=30
```

#### Sincronizacion HTTP

`_syncPendingLocations` envia:

```http
POST <VYGO_API_BASE_URL>/locations
Content-Type: application/json
```

El cuerpo es un lote:

```json
{
  "locations": [
    {
      "id": 1,
      "latitude": 12.1364,
      "longitude": -86.2684,
      "created_at": "2026-09-23T12:00:00.000Z"
    }
  ]
}
```

La app marca registros como sincronizados unicamente cuando recibe HTTP `2xx`. Si la URL no existe, hay timeout o el servidor devuelve error, los registros conservan `synced = 0` y se reintentaran posteriormente.

#### Mapas

- `_nativeMap` crea `MapWidget` de `mapbox_maps_flutter` para Android/iOS.
- `_webMapPreview` usa `flutter_map` con tiles de OpenStreetMap para que el navegador muestre un mapa real con zoom, arrastre y marcador.
- La expresion `kIsWeb ? _webMapPreview() : _nativeMap()` selecciona la implementacion segun plataforma.

El mapa web no es el SDK nativo de Mapbox. Se eligio esta alternativa para que el mapa aparezca en Chrome sin depender de la implementacion nativa de Mapbox.

#### Interfaz

`_deliveryPanel` muestra:

- estado de la ruta;
- cantidad de ubicaciones pendientes;
- boton `Iniciar jornada` o `Terminar jornada`;
- indicador del limite de inactividad;
- boton `Simular actividad` en web;
- boton de registro manual;
- boton independiente de tracking.

`_brandMark`, `_connectionPill` y `_mapLegend` usan la paleta solicitada:

- verde brillante: `#39FF14`;
- verde amarillento: `#ADFF2F`;
- verde muy oscuro: `#0A0A0A`;
- fondo general blanco.

### `pubspec.yaml`

Se agregaron dependencias:

- `http`: cliente HTTP para enviar ubicaciones.
- `flutter_map`: mapa interactivo para web.
- `latlong2`: tipo de coordenada usado por `flutter_map`.

Al ejecutar `flutter pub get`, tambien se actualizo `pubspec.lock` con las versiones resueltas y dependencias transitivas.

### `android/app/src/main/AndroidManifest.xml`

Se agregaron permisos para tracking con pantalla apagada:

- `ACCESS_BACKGROUND_LOCATION`;
- `FOREGROUND_SERVICE`;
- `FOREGROUND_SERVICE_LOCATION`;
- `POST_NOTIFICATIONS`.

Estos permisos declaran la capacidad, pero el usuario aun debe conceder los permisos en el dispositivo. La app muestra la notificacion requerida por el foreground service.

### `ios/Runner/Info.plist`

Se agregaron:

- `NSLocationAlwaysAndWhenInUseUsageDescription`: explica el uso de ubicacion con la app minimizada o pantalla apagada.
- `UIBackgroundModes` con `location`: declara la capacidad de ubicacion en segundo plano.

En iOS la persona puede tener que cambiar manualmente el permiso a `Siempre` desde Configuracion. El sistema puede limitar la frecuencia real.

### `README.md`

Se mantuvo como guia corta de estado, ejecucion y contrato del backend. La documentacion exhaustiva esta en este archivo para no mezclar instrucciones de arranque con el detalle tecnico.

## 3. Flujo completo

```text
Usuario pulsa Iniciar jornada
        |
        v
Se solicita permiso de ubicacion
        |
        v
Se inicia Geolocator.getPositionStream
        |
        v
Llega una posicion, aproximadamente cada 5 segundos
        |
        +--> actualiza la ultima actividad
        +--> guarda LocationRecord en SQLite como pendiente
        +--> actualiza el contador de la interfaz
        +--> intenta POST si hay conexion y backend configurado
        |
        v
El backend responde 2xx?
     |                         |
    Si                         No, timeout o sin backend
     |                         |
marca synced = 1         conserva synced = 0
     |                         |
     +------------ reintenta al recuperar conectividad

Temporizador revisa inactividad cada minuto
        |
        +--> llega actividad: reinicia la ventana de inactividad
        +--> se supera el limite: detiene jornada y tracking

Usuario pulsa Terminar jornada
        |
        v
Se cancela el temporizador y el stream de ubicacion
```

## 4. Ejecucion

Con backend y token Mapbox:

```powershell
flutter run --dart-define=VYGO_API_BASE_URL=https://api.example.com --dart-define=MAPBOX_ACCESS_TOKEN=pk.example
```

Para probar la pantalla en Chrome:

```powershell
flutter run -d chrome
```

Para probar auto-desactivacion en 30 segundos:

```powershell
flutter run -d chrome --dart-define=INACTIVITY_LIMIT_SECONDS=30
```

En la version web, pulsa `Iniciar jornada` y usa `Simular actividad` para reiniciar el contador. El mapa permite arrastrar y acercar.

## 5. Contrato requerido del backend

El backend debe exponer `POST /locations`, aceptar el lote JSON indicado y responder con un codigo `2xx` solo despues de guardar las ubicaciones. La app no marca registros como sincronizados por recibir una respuesta de error.

## 6. Validacion

Se ejecutaron las siguientes comprobaciones durante la implementacion:

- `flutter analyze`: sin errores.
- `flutter test`: prueba existente aprobada.
- `flutter build web --no-pub`: build web generado correctamente.

La prueba definitiva de pantalla apagada debe realizarse en dispositivos fisicos Android e iOS, porque emuladores y navegadores no reproducen exactamente las politicas de bateria, permisos y ejecucion en segundo plano.
