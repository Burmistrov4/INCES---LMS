/// Reglas de currículo, como funciones puras.
///
/// Es el espejo en Dart de `backend/src/dominio/reglas-curriculo.ts`. La
/// decisión vive en una función probada sin montar HTTP ni repositorios, y la
/// interfaz la usa para **avisar antes** de enviar: que el backend también lo
/// compruebe es la segunda barrera, no la única.
library;

import '../models/pensum.dart';

/// Agrupa un pensum por período.
///
/// Los períodos salen ordenados y **sin grupos vacíos**: un pensum con los
/// períodos 1, 2 y 5 devuelve tres grupos, no cinco con dos huecos. Rellenar
/// los huecos obligaría a la interfaz a decidir si un período vacío es un error
/// o una intención, y no es ninguna de las dos cosas.
List<GrupoPensum<T>> agruparPensum<T extends EntradaPensum>(List<T> entradas) {
  final porPeriodo = <int, List<T>>{};
  for (final entrada in entradas) {
    porPeriodo.putIfAbsent(entrada.periodo, () => <T>[]).add(entrada);
  }

  final periodos = porPeriodo.keys.toList()..sort();

  return [
    for (final periodo in periodos)
      GrupoPensum<T>(periodo: periodo, materias: porPeriodo[periodo]!),
  ];
}

/// Devuelve el identificador de la primera materia repetida, o `null`.
///
/// Devuelve el identificador y no un booleano porque el mensaje tiene que
/// nombrar la materia culpable: «hay una materia repetida» obliga al
/// administrador a buscarla a mano en un pensum de treinta líneas.
String? materiaRepetida(Iterable<EntradaPensum> entradas) {
  final vistas = <String>{};
  for (final entrada in entradas) {
    if (!vistas.add(entrada.materiaId)) return entrada.materiaId;
  }
  return null;
}

/// Decide si el pensum se puede tocar.
///
/// `seccionesActivas > 0` bloquea: hay secciones del período vigente cursando el
/// programa, y reordenar o quitar materias dejaría esas secciones apuntando a un
/// plan que ya no existe. El número es real desde que `sections` tiene
/// `program_id`.
bool pensumEditable(int seccionesActivas) => seccionesActivas == 0;

/// ¿Se puede activar un programa con este tamaño de pensum?
///
/// Activar uno sin materias choca contra el constraint trigger diferido del
/// backend (400 `RESTRICCION_VIOLADA`). Se comprueba aquí para deshabilitar el
/// interruptor **con la razón a la vista**, en vez de dejar que el
/// administrador pulse y reciba un error que ya se sabía.
bool puedeActivarse({required int totalMaterias}) => totalMaterias > 0;

/// El período que sigue al mayor de los indicados.
///
/// Un pensum vacío empieza en el 1. Se usa para el botón «añadir período» del
/// asistente, que debe proponer el siguiente sin saltarse ninguno.
int siguientePeriodo(Iterable<int> periodos) {
  var mayor = 0;
  for (final periodo in periodos) {
    if (periodo > mayor) mayor = periodo;
  }
  return mayor + 1;
}
