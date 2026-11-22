import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/navegacion.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/sesion_storage.dart';
import '../../data/api/auth_api.dart';

/// Estado de sesión de la app. `null` significa "nadie ha entrado".
///
/// Al arrancar lee el almacenamiento cifrado: si hay un token guardado, se
/// entra directo sin volver a pedir credenciales. En obra, tener que loguearse
/// cada vez que se abre la app es inaceptable.
class SesionController extends AsyncNotifier<SesionUsuario?> {
  SesionStorage get _storage => ref.read(sesionStorageProvider);
  AuthApi get _api => ref.read(authApiProvider);

  @override
  Future<SesionUsuario?> build() => _storage.leer();

  Future<void> entrarConCorreo({
    required String email,
    required String pin,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sesion = await _api.login(email: email.trim(), pin: pin);
      await _storage.guardar(sesion);
      _recordar();
      ref.read(avisoDeAccesoProvider.notifier).state = null;
      return sesion;
    });
    _salirDelAcceso();
  }

  Future<void> entrarConPin({
    required int usuarioId,
    required int empresaId,
    required String pin,
  }) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final sesion = await _api.loginPorPin(
        usuarioId: usuarioId,
        empresaId: empresaId,
        pin: pin,
      );
      await _storage.guardar(sesion);
      _recordar();
      ref.read(avisoDeAccesoProvider.notifier).state = null;
      return sesion;
    });
    _salirDelAcceso();
  }

  /// Tras entrar, la app del rol reemplaza a la raíz, pero lo que estaba
  /// apilado encima sigue ahí. Con el PIN se notaba: la pantalla del teclado
  /// quedaba tapando la app con los cuatro puntos llenos, y había que apretar
  /// "atrás" para llegar al inicio.
  void _salirDelAcceso() {
    if (state.valueOrNull != null) {
      navegadorRaiz.currentState?.popUntil((ruta) => ruta.isFirst);
    }
  }

  /// El login guarda a quien entró como "recordado", pero el provider que lo
  /// lee queda en caché. Sin esta invalidación, tras "No soy Jorge" quedaba en
  /// `null`: el siguiente login guardaba a la persona nueva, la pantalla de
  /// acceso seguía leyendo el `null` viejo y al cerrar sesión mostraba el
  /// formulario de correo en vez de "Hola de nuevo". Solo se arreglaba al
  /// reiniciar la app, por eso parecía intermitente.
  void _recordar() => ref.invalidate(usuarioRecordadoProvider);

  /// Cambia la clave de quien tiene la sesión y pasa a usar la sesión nueva
  /// que devuelve el servidor, ya sin la obligación de cambiarla.
  ///
  /// No pasa por `AsyncLoading`: eso reemplazaría la pantalla por el indicador
  /// de carga de la raíz. Un fallo (clave actual mal escrita, bloqueo por
  /// intentos) se relanza para que la pantalla lo muestre donde está.
  Future<void> cambiarClave({
    required String claveActual,
    required String claveNueva,
  }) async {
    final sesion = await _api.cambiarClave(
      claveActual: claveActual,
      claveNueva: claveNueva,
    );
    await _storage.guardar(sesion);
    _recordar();
    state = AsyncValue.data(sesion);
  }

  /// El servidor respondió `DEBE_CAMBIAR_PIN` a una petición: la cuenta tiene
  /// una clave provisoria. Se marca la sesión y la raíz muestra el cambio de
  /// clave en vez de la app. Puede llegar varias veces seguidas (varias
  /// peticiones en vuelo); solo la primera actúa.
  Future<void> exigirCambioDeClave() async {
    final sesion = state.valueOrNull;
    if (sesion == null || sesion.debeCambiarClave) return;
    final marcada = sesion.conCambioPendiente();
    // Se saca a la persona de donde esté: lo que estaba apilado no se puede
    // usar hasta que cambie la clave.
    navegadorRaiz.currentState?.popUntil((ruta) => ruta.isFirst);
    await _storage.guardar(marcada);
    state = AsyncValue.data(marcada);
  }

  /// Cierra la sesión pero recuerda al usuario, para que pueda volver a
  /// entrar solo con su PIN.
  ///
  /// Con [revocar] (lo normal) también le avisa al servidor para que revoque el
  /// refresh token: sin eso, quien se llevara una copia podría seguir
  /// renovando. Es **después** de cerrar la sesión local y sin esperarlo: si
  /// falla —sin señal en la obra— el cierre ya ocurrió, y el refresh vence solo.
  Future<void> salir({bool revocar = true}) async {
    navegadorRaiz.currentState?.popUntil((ruta) => ruta.isFirst);
    final refresh = revocar ? state.valueOrNull?.refreshToken : null;
    await _storage.cerrarSesion();
    state = const AsyncValue.data(null);
    if (refresh != null) _revocarEnElServidor(refresh);
  }

  void _revocarEnElServidor(String refresh) {
    // Sin await a propósito. El error no se puede mostrar a nadie: la pantalla
    // ya es la de acceso.
    unawaited(_api.cerrarSesion(refresh).catchError((Object _) {}));
  }

  /// Una renovación del token de acceso: la sesión sigue siendo la misma
  /// persona, con token y refresh nuevos. Si mientras tanto entró otra cuenta,
  /// se descarta (no se le pisa la sesión a quien entró después).
  void aplicarRenovada(SesionUsuario nueva) {
    final actual = state.valueOrNull;
    if (actual == null ||
        actual.usuarioId != nueva.usuarioId ||
        actual.empresaId != nueva.empresaId) {
      return;
    }
    state = AsyncValue.data(nueva);
  }

  /// El servidor rechazó el token guardado: venció o lo revocaron.
  ///
  /// Se saca a la persona de donde esté —puede estar tres pantallas adentro— y
  /// se la deja en el acceso por PIN, que la recuerda. Varias peticiones en
  /// vuelo pueden recibir el 401 a la vez; solo la primera actúa.
  Future<void> expirar() async {
    if (state.valueOrNull == null) return;
    navegadorRaiz.currentState?.popUntil((ruta) => ruta.isFirst);
    // El servidor ya dijo que la sesión no vale: no hay nada que revocar.
    await salir(revocar: false);
    mensajeroRaiz.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Tu sesión expiró. Vuelve a entrar con tu PIN.'),
        ),
      );
  }

  /// La empresa de quien tiene la sesión está suspendida (el servidor respondió
  /// 403 `EMPRESA_SUSPENDIDA`). La sesión ya no se puede usar mientras dure la
  /// suspensión, así que se cierra y la persona queda en el acceso **con el
  /// aviso a la vista**: un snackbar de cuatro segundos se pierde, y entonces
  /// no sabría por qué no puede entrar. Varias peticiones en vuelo pueden
  /// recibir el 403 a la vez; solo la primera actúa.
  Future<void> suspenderPorEmpresa() async {
    if (state.valueOrNull == null) return;
    ref.read(avisoDeAccesoProvider.notifier).state = mensajeEmpresaSuspendida;
    navegadorRaiz.currentState?.popUntil((ruta) => ruta.isFirst);
    // No se revoca el refresh: el servidor rechaza todo de esta empresa, y esa
    // llamada tampoco llegaría.
    await salir(revocar: false);
  }

  /// Olvida también al usuario recordado — el "Cambiar" de la pantalla de PIN.
  Future<void> cambiarDeUsuario() async {
    await _storage.olvidarTodo();
    ref.invalidate(usuarioRecordadoProvider);
    state = const AsyncValue.data(null);
  }
}

/// Un aviso para la pantalla de acceso: por qué se llegó ahí. Se muestra hasta
/// que alguien entra o lo descarta.
final avisoDeAccesoProvider = StateProvider<String?>((ref) => null);

final sesionProvider = AsyncNotifierProvider<SesionController, SesionUsuario?>(
  SesionController.new,
);

/// Último usuario que entró en este teléfono, si lo hay.
///
/// Se lee del almacenamiento y queda en caché, así que quien lo escribe tiene
/// que invalidarlo: el login (ver `_recordar`) y "No soy…".
final usuarioRecordadoProvider = FutureProvider<UsuarioRecordado?>(
  (ref) => ref.watch(sesionStorageProvider).leerUsuarioRecordado(),
);

/// Nombre legible de cada valor del enum `RolUsuario` del backend.
String nombreDeRol(String rol) => switch (rol) {
  'ADMIN' => 'Administrador',
  'JEFE_TERRENO' => 'Jefe de terreno',
  'BODEGUERO' => 'Bodeguero',
  'TRABAJADOR' => 'Trabajador',
  _ => rol,
};
