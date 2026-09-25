import '../../models/inscripcion_campo.dart';

/// Contrato de administración del catálogo de la planilla de inscripción.
///
/// **Por qué es una interfaz aparte y no más métodos de `PlanillaGateway`.**
/// Son dos fronteras con dos audiencias:
///
///  * `PlanillaGateway` es la ruta **pública**: el aspirante que todavía no
///    tiene cuenta y necesita saber qué se le va a preguntar. Va por HTTP contra
///    el backend Fastify y **no** lleva token.
///  * Este es la ruta **administrativa**: va contra Supabase por PostgREST y su
///    frontera de autorización es la RLS (`inscripcion_campos_admin_escritura`,
///    ADR-003), no el backend.
///
/// Mezclarlas obligaría a que el formulario público cargara con los métodos de
/// escritura del catálogo, y a que un fallo de permisos del panel se leyera como
/// un fallo del formulario. El backend ya tiene su propia ruta pública de
/// catálogo; esta interfaz es la otra mitad, la que el backend nunca expone.
///
/// Las implementaciones **lanzan** excepciones; el repositorio las envuelve en
/// `Result`. Un `null` no aparece aquí en ningún sitio.
abstract interface class PlanillaAdminGateway {
  /// El catálogo **completo**, incluidos los campos desactivados.
  ///
  /// No es `PlanillaGateway.campos()` con otro nombre: aquél filtra
  /// `activo = true` en el backend, y con ese filtro el panel no podría
  /// reactivar nada — el campo apagado desaparecería de la lista justo al
  /// apagarlo, y el admin leería «se borró». La política
  /// `inscripcion_campos_admin_lectura` existe exactamente para este caso.
  Future<CatalogoInscripcion> catalogoCompleto();

  /// Añade un campo al catálogo y devuelve la fila que quedó almacenada.
  ///
  /// [campo] trae `codigo` y `tipo`, que en la creación **sí** se fijan. Puede
  /// fallar con `23505` si el `codigo` ya existe, con `23514` si no cumple
  /// `^[a-z][a-z0-9_]*$` o si el `tipo` no es uno de los nueve admitidos, y con
  /// `42501` si quien llama no es administrador. La traducción de esos códigos a
  /// un mensaje accionable la hace `AppException.from`, no esta capa.
  Future<CampoInscripcion> crear(CampoInscripcion campo);

  /// Actualiza **sólo** los campos mutables de un campo existente.
  ///
  /// `codigo` y `tipo` no están en la firma a propósito: son inmutables después
  /// de la creación. Renombrar el código es una migración de datos (es la clave
  /// con la que viajan los valores ya guardados) y cambiar el tipo cambiaría la
  /// forma del valor almacenado. Al no existir el parámetro, no hay forma de
  /// mandarlos por descuido.
  ///
  /// `null` significa «no toques esto», **no** «ponlo a NULL». Para *borrar* la
  /// ayuda hay que mandar cadena vacía: `CampoInscripcion.fromJson` normaliza
  /// `''` a `null` al leer, así que el efecto es el mismo y no hace falta
  /// inventar un centinela ni un `Optional` para un caso que se resuelve solo.
  ///
  /// `condicion` y `aplica_a` quedan fuera en esta versión: se muestran como
  /// inspección, no se editan.
  Future<CampoInscripcion> actualizar({
    required String codigo,
    String? etiqueta,
    String? ayuda,
    String? grupo,
    bool? obligatorio,
    bool? activo,
    int? orden,
  });

  /// Intercambia el `orden` de dos campos **vecinos**.
  ///
  /// Es el «subir/bajar un puesto» y no un arrastrar-y-soltar: el intercambio
  /// con el vecino es una operación entre dos filas ya conocidas, no hay que
  /// reindexar nada y el resultado es el mismo que el admin ve en pantalla.
  ///
  /// Se pasan los dos [CampoInscripcion] enteros —y no dos códigos— porque quien
  /// llama ya los tiene: son los dos ítems adyacentes de la lista que está
  /// pintando. Pedirle que los vuelva a buscar por código sería trabajo perdido
  /// y una consulta de más.
  ///
  /// **No comprueba que sean vecinos.** Comprobarlo exigiría una consulta extra
  /// para descubrir algo que el llamador ya sabe, y el resultado de intercambiar
  /// dos campos no adyacentes sigue siendo un catálogo válido (los dos cambian
  /// de puesto y el resto no se mueve), sólo que no es lo que el botón promete.
  /// La garantía vive en el panel, que sólo ofrece el botón hacia el vecino real.
  Future<void> intercambiarOrden({
    required CampoInscripcion actual,
    required CampoInscripcion vecino,
  });
}
