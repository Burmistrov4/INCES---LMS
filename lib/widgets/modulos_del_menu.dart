// Conecta el menú de un dashboard con el estado **real** de `system_modules`.
//
// ---------------------------------------------------------------------------
//  El hueco que cierra
// ---------------------------------------------------------------------------
//
// Los tres dashboards declaraban `disponible:` a mano. Esa bandera dice si la
// pantalla **existe**, y eso es un hecho del código; pero el interruptor que
// decide si un módulo vive es del **servidor**, y nadie lo leía. Consecuencia
// medida: apagar `m6_aula_virtual` desde el cPanel dejaba «Mis aulas» encendida
// en el menú del docente y del aprendiz, y el clic devolvía **403** — el menú
// afirmaba que había algo al otro lado.
//
// La bandera declarada y el estado del módulo son **dos hechos distintos** y
// por eso no se sustituyen: `disponible` sigue siendo el contrato de R-22
// («toda sección con panel tiene la bandera y su rama»), y el módulo se aplica
// **encima** en tiempo de ejecución. Un ítem puede estar construido y con el
// módulo apagado; nunca al revés.
//
// ---------------------------------------------------------------------------
//  Por qué se lee por PostgREST y no por la API
// ---------------------------------------------------------------------------
//
// Es ADR-003: la frontera de autorización es la RLS, no la API. La política
// `system_modules_read_authenticated` concede `select` a **cualquier**
// autenticado con `using (true)` —está escrita así a propósito, «cualquier
// autenticado necesita saber qué módulos existen para pintar su menú»—, así que
// el aprendiz y el docente pueden leerlo sin pasar por Fastify. No hay una ruta
// que dé esta lista a los tres roles, y no hace falta.

import 'package:flutter/widgets.dart';

import '../models/system_module.dart';
import '../repositories/modulo_repository.dart';
import 'andamiaje.dart';

/// Mensaje de una sección apagada porque su módulo está apagado.
///
/// Dice **quién** lo apagó y **dónde** se enciende: un gris sin explicación no
/// se distingue de una plataforma incompleta, y ésta es la diferencia entre «el
/// sistema no sirve» y «falta un interruptor». No lleva paréntesis porque
/// `test/menu_alcanzable_test.dart` delimita cada `ItemNavegacion(…)` con el
/// primer `),` que encuentra.
String motivoDeModuloApagado(String clave, Map<String, String> nombres) {
  final nombre = nombres[clave];
  return nombre == null
      ? 'El módulo $clave está apagado. Actívalo en el cPanel, en Módulos del '
          'Sistema.'
      : 'El módulo «$nombre» está apagado. Actívalo en el cPanel, en Módulos '
          'del Sistema.';
}

/// Devuelve los ítems con `disponible` recalculado según [apagadas].
///
/// Reglas, en orden:
///
///  1. Un ítem sin [ItemNavegacion.modulo] no se toca nunca. El perfil propio y
///     la ficha del aspirante no dependen de ningún interruptor.
///  2. Un ítem cuyo módulo está en [apagadas] se apaga y **explica por qué**,
///     pisando cualquier [ItemNavegacion.pendiente] que tuviera: la causa viva
///     —el módulo que alguien apagó— es más útil que la nota estática.
///  3. Un módulo **desconocido** —no está en [nombres] ni en [apagadas]— no
///     apaga nada.
///
/// La regla 3 es deliberada y es la que hace que la lectura pueda fallar sin
/// romper la aplicación. Si `system_modules` no se puede leer —sin red, sin
/// sesión, RLS que cambie—, [apagadas] llega **vacía** y el menú queda como
/// estaba: se enseña de más y el backend contesta con su 403, en vez de
/// esconderle a todo el mundo secciones que sí funcionan. Fallar cerrado aquí
/// convertiría un corte de red en «la aplicación está vacía».
List<ItemNavegacion> aplicarEstadoDeModulos(
  List<ItemNavegacion> items, {
  required Set<String> apagadas,
  Map<String, String> nombres = const <String, String>{},
}) {
  if (apagadas.isEmpty) return items;

  return [
    for (final item in items)
      if (item.modulo != null && apagadas.contains(item.modulo))
        item.apagadoPorModulo(motivoDeModuloApagado(item.modulo!, nombres))
      else
        item,
  ];
}

/// Carga `system_modules` al montar el dashboard y deja el menú gobernado por él.
///
/// Es un `mixin` y no un widget envoltorio por una razón concreta: el estado
/// tiene que llegar a `build()` del dashboard, que es quien construye la lista
/// de ítems y el `switch` del contenido. Un envoltorio obligaría a pasar los
/// ítems hacia arriba y el contenido hacia abajo, y a que los tres dashboards
/// repitieran la fontanería.
///
/// **Orden de los `initState`.** Dos de los tres dashboards ya definen su propio
/// `initState`. El de la clase gana sobre el del mixin, así que el mixin sólo
/// corre si el de la clase llama a `super.initState()` — que es lo que hace
/// cualquiera de los dos. Es la trampa clásica de los mixin en `State` y por eso
/// está escrita aquí.
mixin CargaDeModulos<T extends StatefulWidget> on State<T> {
  /// De dónde sale el estado. Cada dashboard devuelve el suyo —inyectable en
  /// las pruebas—; no se resuelve aquí para no atar el mixin a Supabase.
  ModuloRepository get repositorioDeModulos;

  Set<String> _clavesApagadas = const <String>{};
  Map<String, String> _nombresPorClave = const <String, String>{};

  /// Claves de los módulos apagados. Vacía = «no se sabe» o «ninguno», y las dos
  /// cosas significan lo mismo para el menú: no apagues nada.
  Set<String> get clavesApagadas => _clavesApagadas;

  /// Nombre legible de cada módulo, para redactar el motivo del apagado.
  Map<String, String> get nombresDeModulos => _nombresPorClave;

  /// Los ítems del menú con el estado del servidor ya aplicado.
  List<ItemNavegacion> menuConModulos(List<ItemNavegacion> items) =>
      aplicarEstadoDeModulos(
        items,
        apagadas: _clavesApagadas,
        nombres: _nombresPorClave,
      );

  @override
  void initState() {
    super.initState();
    cargarEstadoDeModulos();
  }

  /// Lee los módulos. Público para que las pruebas puedan esperarlo sin depender
  /// de cuántos `pump` hacen falta.
  Future<void> cargarEstadoDeModulos() async {
    final resultado = await repositorioDeModulos.obtenerModulos();

    resultado.when(
      success: (modulos) {
        if (!mounted) return;
        setState(() {
          _clavesApagadas = <String>{
            for (final SystemModule m in modulos)
              if (!m.habilitado) m.clave,
          };
          _nombresPorClave = <String, String>{
            for (final SystemModule m in modulos) m.clave: m.nombre,
          };
        });
      },
      failure: (_) {
        // Fallo silencioso y **a propósito**: ver la regla 3 de
        // [aplicarEstadoDeModulos]. El menú se queda como estaba —no se esconde
        // nada— y el backend sigue siendo el que decide, que es donde vive la
        // autorización de verdad.
      },
    );
  }
}
