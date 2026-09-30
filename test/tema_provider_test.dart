import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:inces_lms_app/providers/tema_provider.dart';

import 'support/fake_preferencias_tema.dart';

/// Pruebas de la preferencia de tema (Bloque D).
///
/// Son pruebas **sin árbol de widgets**, como `paleta_inces_test.dart`: lo que
/// se comprueba aquí es la lógica —traducción del valor guardado, valor por
/// defecto, persistencia, degradación cuando el almacén falla—, y montar la
/// aplicación para eso escondería el fallo detrás de un layout.
void main() {
  group('modoDeTemaDesde · la traducción del texto guardado', () {
    test('los tres nombres válidos se traducen a su modo', () {
      expect(modoDeTemaDesde('system'), ThemeMode.system);
      expect(modoDeTemaDesde('light'), ThemeMode.light);
      expect(modoDeTemaDesde('dark'), ThemeMode.dark);
    });

    test('sin valor guardado cae al modo del sistema', () {
      // Es el caso de un usuario que nunca tocó el selector, y también el de un
      // almacén que no se pudo leer: el contrato del puerto convierte los dos en
      // `null`, así que comparten esta rama y no hace falta probarlos por
      // separado.
      expect(modoDeTemaDesde(null), ThemeMode.system);
    });

    test('una cadena desconocida cae al modo del sistema y no lanza', () {
      // Los casos reales: un valor escrito por una versión anterior, una
      // preferencia corrupta, o alguien editando `localStorage` a mano.
      expect(modoDeTemaDesde('oscuro'), ThemeMode.system);
      expect(modoDeTemaDesde(''), ThemeMode.system);
      expect(modoDeTemaDesde('claro'), ThemeMode.system);
    });

    test('el nombre se compara sin normalizar, y eso es deliberado', () {
      // Se compara contra `ThemeMode.name` tal cual. Normalizar mayúsculas
      // parecería amable, pero inventaría un segundo vocabulario que no coincide
      // con el que se escribe: lo que se guarda es `modo.name`, así que lo que
      // se lee tiene que ser exactamente eso.
      expect(modoDeTemaDesde('DARK'), ThemeMode.system);
      expect(modoDeTemaDesde('Dark'), ThemeMode.system);
    });

    test('todo ThemeMode tiene nombre reconocible', () {
      // Guardia contra el futuro: si Flutter añade un `ThemeMode`, esta prueba
      // lo delata en vez de dejar que caiga siempre al modo del sistema sin que
      // nadie se entere. Sin esto, la cobertura parecería completa con tres
      // modos y dejaría de serlo con cuatro.
      expect(ThemeMode.values, hasLength(3));
      for (final modo in ThemeMode.values) {
        expect(
          modoDeTemaDesde(modo.name),
          modo,
          reason: 'el modo «${modo.name}» debe poder restaurarse de su nombre',
        );
      }
    });
  });

  group('TemaProvider · el valor vigente', () {
    test('arranca en el modo del sistema antes de leer nada', () {
      // Es el valor que la aplicación tenía antes de que esta preferencia
      // existiera, y el único que no puede estar visiblemente equivocado
      // mientras la lectura asíncrona está en camino.
      final proveedor = TemaProvider(preferencias: FakePreferenciasTema());

      expect(proveedor.modo, ThemeMode.system);
      expect(proveedor.falloAlRecordar, isFalse);
    });

    test('cargar restaura lo que había guardado', () async {
      final proveedor = TemaProvider(
        preferencias: FakePreferenciasTema(guardado: 'dark'),
      );

      await proveedor.cargar();

      expect(proveedor.modo, ThemeMode.dark);
    });

    test('cargar con una preferencia corrupta deja el modo del sistema', () async {
      final proveedor = TemaProvider(
        preferencias: FakePreferenciasTema(guardado: 'no-existe'),
      );

      await proveedor.cargar();

      expect(proveedor.modo, ThemeMode.system);
    });

    test('cargar no avisa si el valor guardado es el que ya estaba', () async {
      // El comentario de `cargar` afirma que sólo notifica cuando cambia. Sin
      // esta prueba, esa afirmación no la sostiene nada.
      final proveedor = TemaProvider(preferencias: FakePreferenciasTema());
      var avisos = 0;
      proveedor.addListener(() => avisos++);

      await proveedor.cargar();

      expect(avisos, 0, reason: 'no había nada que cambiar');
    });

    test('cargar sí avisa cuando el valor guardado cambia el modo', () async {
      final proveedor = TemaProvider(
        preferencias: FakePreferenciasTema(guardado: 'light'),
      );
      var avisos = 0;
      proveedor.addListener(() => avisos++);

      await proveedor.cargar();

      expect(avisos, 1);
    });
  });

  group('TemaProvider · elegir un tema', () {
    test('cambiar aplica el modo y lo persiste', () async {
      final almacen = FakePreferenciasTema();
      final proveedor = TemaProvider(preferencias: almacen);

      await proveedor.cambiar(ThemeMode.dark);

      expect(proveedor.modo, ThemeMode.dark);
      expect(
        almacen.guardado,
        'dark',
        reason: 'se guarda el NOMBRE del modo y no su índice: un índice se '
            'rompería en silencio al reordenar el enum',
      );
    });

    test('cambiar avisa a quien escucha', () async {
      final proveedor = TemaProvider(preferencias: FakePreferenciasTema());
      var avisos = 0;
      proveedor.addListener(() => avisos++);

      await proveedor.cambiar(ThemeMode.light);

      expect(avisos, 1);
    });

    test('elegir el modo que ya estaba no escribe ni avisa', () async {
      final almacen = FakePreferenciasTema(guardado: 'dark');
      final proveedor = TemaProvider(preferencias: almacen);
      await proveedor.cargar();

      var avisos = 0;
      proveedor.addListener(() => avisos++);
      await proveedor.cambiar(ThemeMode.dark);

      expect(almacen.escrituras, 0);
      expect(avisos, 0);
    });

    test('se puede ir y volver, y lo último guardado es lo que queda', () async {
      final almacen = FakePreferenciasTema();
      final proveedor = TemaProvider(preferencias: almacen);

      await proveedor.cambiar(ThemeMode.dark);
      await proveedor.cambiar(ThemeMode.light);
      await proveedor.cambiar(ThemeMode.system);

      expect(proveedor.modo, ThemeMode.system);
      expect(almacen.guardado, 'system');
      expect(almacen.escrituras, 3);
    });
  });

  group('TemaProvider · cuando el almacén falla', () {
    test('el tema cambia igual aunque no se pueda recordar', () async {
      // La degradación es deliberada: el tema ya cambió —que es lo que el
      // usuario pidió y lo que está viendo— y sólo se pierde que se recuerde
      // para la próxima sesión. Revertirlo castigaría al usuario por un
      // problema del almacenamiento.
      final proveedor = TemaProvider(
        preferencias: FakePreferenciasTema(fallaAlGuardar: true),
      );

      await proveedor.cambiar(ThemeMode.dark);

      expect(proveedor.modo, ThemeMode.dark);
      expect(
        proveedor.falloAlRecordar,
        isTrue,
        reason: 'la degradación es invisible para el usuario, así que tiene que '
            'ser medible desde fuera',
      );
    });

    test('un guardado posterior que sí funciona limpia la marca de fallo', () async {
      // Sin esta prueba, la marca podría quedarse pegada en `true` para
      // siempre y nadie lo notaría: la primera prueba seguiría pasando.
      final almacen = FakePreferenciasTema(fallaAlGuardar: true);
      final proveedor = TemaProvider(preferencias: almacen);

      await proveedor.cambiar(ThemeMode.dark);
      expect(proveedor.falloAlRecordar, isTrue);

      almacen.fallaAlGuardar = false;
      await proveedor.cambiar(ThemeMode.light);

      expect(proveedor.modo, ThemeMode.light);
      expect(proveedor.falloAlRecordar, isFalse);
      expect(almacen.guardado, 'light');
    });

    test('el fallo no revierte lo que ya se había guardado antes', () async {
      final almacen = FakePreferenciasTema(guardado: 'light');
      final proveedor = TemaProvider(preferencias: almacen);
      await proveedor.cargar();

      almacen.fallaAlGuardar = true;
      await proveedor.cambiar(ThemeMode.dark);

      expect(
        almacen.guardado,
        'light',
        reason: 'lo que había sigue ahí: no se borra una preferencia válida '
            'porque la siguiente escritura falle',
      );
    });
  });
}
