/// Reglas del cuadrante, como funciones puras.
///
/// Es el espejo en Dart de `backend/src/dominio/reglas-cuadrante.ts`. La decisión
/// vive en una función probada sin montar HTTP ni repositorios, y la interfaz la
/// usa para **avisar antes** de enviar: que el backend también lo compruebe con
/// Zod es la segunda barrera, no la única.
///
/// Estas reglas **no son la única barrera, y no pretenden serlo**. La invariante
/// de verdad —que un docente no esté en dos sitios a la vez— la impone un trigger
/// en la base, porque sólo él puede ver las dos tablas que cruza. Lo de aquí
/// existe para nombrar el campo culpable antes de gastar un viaje de red.
library;

import '../models/cuadrante.dart';

/// Código de error con el que el backend señala un choque de agenda.
///
/// Un choque **no es un dato inválido**: los datos están bien y el **estado
/// actual** es el que no admite la operación. Por eso el backend lo separa de
/// `RESTRICCION_VIOLADA` y responde `409`, para que la interfaz pueda decir «ese
/// docente ya está en el taller a esa hora» en vez de un genérico «datos
/// inválidos».
const String codigoChoqueDeAgenda = 'CHOQUE_DE_AGENDA';

/// Códigos que el backend usa para decir «eso ya existe».
const String codigoRegistroDuplicado = 'REGISTRO_DUPLICADO';

/// Códigos de recurso inexistente, por tipo, para el 404.
const String codigoAulaInexistente = 'AULA_INEXISTENTE';
const String codigoGuardiaInexistente = 'GUARDIA_INEXISTENTE';
const String codigoClaseInexistente = 'CLASE_INEXISTENTE';

/// Código del backend cuando el rol del llamante no tiene horario propio.
const String codigoPerfilSinRol = 'PERFIL_SIN_ROL';

/// ¿El fallo es un choque de agenda?
///
/// Se comprueba el **código**, no el tipo de error: `ApiClient` clasifica todo
/// `409` como `AppErrorType.validacion`, así que el tipo no distingue un choque
/// de un dato mal formado. Es el código el que lo hace, y es lo que permite dar
/// un mensaje útil en lugar de uno genérico.
bool esChoqueDeAgenda(String? codigo) => codigo == codigoChoqueDeAgenda;

/// Longitud máxima del código de un lapso, igual que la columna `varchar(10)`.
const int largoMaximoCodigoLapso = 10;

/// Longitud máxima del nombre de un espacio, igual que la columna `varchar(80)`.
const int largoMaximoNombreAula = 80;

/// Longitud máxima del nombre de un lapso.
const int largoMaximoNombreLapso = 120;

/// Formato del código de un lapso: letra o dígito, y luego letras, dígitos o
/// guiones, hasta 10 caracteres.
///
/// Es la identidad del lapso: `2026-1`, `SA26-2`. Cambiarla rompería cualquier
/// documento que lo cite, así que la interfaz la valida **antes** de enviar en
/// vez de dejar que el `unique` de la base la rechace con un mensaje genérico.
final RegExp patronCodigoLapso = RegExp(r'^[A-Za-z0-9][A-Za-z0-9-]{0,9}$');

/// ¿El código de lapso tiene la forma correcta?
bool esCodigoDeLapso(String valor) => patronCodigoLapso.hasMatch(valor.trim());

/// ¿Es una fecha ISO `YYYY-MM-DD` que existe en el calendario?
///
/// Comprobar el formato no basta: `2027-02-30` tiene la forma correcta y no
/// existe. Se construye la fecha y se comprueba que los componentes sobreviven
/// la ida y vuelta, que es lo que descarta el 30 de febrero y el 31 de abril.
///
/// Las fechas viajan como **texto** y no como `DateTime` porque convertir un
/// `DateTime` a ISO completo desplaza un día por zona horaria al ir y volver.
bool esFechaISO(String valor) {
  final coincidencia =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(valor.trim());
  if (coincidencia == null) return false;

  final anio = int.parse(coincidencia.group(1)!);
  final mes = int.parse(coincidencia.group(2)!);
  final dia = int.parse(coincidencia.group(3)!);

  if (mes < 1 || mes > 12) return false;
  if (dia < 1 || dia > 31) return false;

  final fecha = DateTime.utc(anio, mes, dia);
  return fecha.year == anio && fecha.month == mes && fecha.day == dia;
}

/// ¿El rango de fechas de un lapso es coherente?
///
/// La restricción real de la base es `end_date > start_date` **cuando ambas
/// están**, y por eso las dos son opcionales: el centro no ha cargado las fechas
/// del lapso en curso e inventarlas sería fabricar un dato institucional (R-17).
/// Un rango a medias —sólo una de las dos— es válido.
bool rangoDeFechasValido({String? inicio, String? fin}) {
  final desde = inicio?.trim();
  final hasta = fin?.trim();

  final tieneInicio = desde != null && desde.isNotEmpty;
  final tieneFin = hasta != null && hasta.isNotEmpty;

  if (!tieneInicio && !tieneFin) return true;

  if (tieneInicio && !esFechaISO(desde)) return false;
  if (tieneFin && !esFechaISO(hasta)) return false;

  if (!tieneInicio || !tieneFin) return true;

  return hasta.compareTo(desde) > 0;
}

/// ¿El nombre de un espacio es aceptable?
bool nombreDeAulaValido(String nombre) {
  final limpio = nombre.trim();
  return limpio.isNotEmpty && limpio.length <= largoMaximoNombreAula;
}

/// ¿La capacidad declarada es aceptable?
///
/// Cero es válido y significa «sin cupo declarado» —una zona, un pasillo—, que
/// **no** es lo mismo que desconocido. Un negativo no tiene lectura posible.
bool capacidadValida(int capacidad) => capacidad >= 0;

/// ¿El día está dentro del rango del centro?
bool diaValido(int dia) => dia >= 1 && dia <= diaMaximo;

/// ¿El bloque está dentro del rango del día?
bool bloqueValido(int bloque) => bloque >= 1 && bloque <= bloqueMaximo;

/// Los bloques que pertenecen a un turno, en orden.
///
/// La usa la rejilla para pintar las filas de cada franja sin repetir la
/// frontera: si estuviera escrita en la pantalla, mover el corte en la base
/// dejaría la rejilla pintando un bloque en la franja equivocada.
List<int> bloquesDelTurno(Turno turno) => switch (turno) {
      Turno.manana => [for (var b = 1; b <= bloquesDeManana; b++) b],
      Turno.tarde => [
          for (var b = bloquesDeManana + 1; b <= bloqueMaximo; b++) b,
        ],
    };

/// Cómo se nombra a un docente que llegó sin nombre.
///
/// No es cosmética: por **R-21** el canal de invitación nunca captura
/// `nombres`/`apellidos`, así que `nombre_para_mostrar()` devuelve NULL y la
/// columna del docente en el cuadrante sale vacía. Un hueco mudo se lee como un
/// fallo de la aplicación; nombrarlo señala el hueco y a quién hay que
/// preguntar.
String nombreDeDocente(String? nombre) {
  final limpio = nombre?.trim() ?? '';
  return limpio.isEmpty ? 'Docente sin nombre' : limpio;
}
