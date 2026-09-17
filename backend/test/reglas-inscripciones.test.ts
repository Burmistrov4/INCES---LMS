import { describe, expect, it } from 'vitest';
import {
  cuposOfrecibles,
  descripcionDeEstado,
  esAcaparamientoDeMateria,
  esEstadoInscripcion,
  esOfertaVencida,
  esReincorporacionSinHistorial,
  esRequiereReincorporacion,
  esSeccionArchivada,
  esSeccionInexistente,
  esSolicitudYaExistente,
  hayAsientoDisponible,
  ofertaVencida,
  puedeSolicitar,
} from '../src/dominio/reglas-inscripciones.js';

/**
 * Las reglas puras del Módulo 4.
 *
 * Se prueban sin montar nada porque son funciones puras: es exactamente el motivo
 * por el que viven fuera de los manejadores de ruta. Aquí se pueden ejercitar
 * casos que por HTTP casi no se alcanzan —una fecha de vencimiento ilegible, un
 * estado desconocido— sin levantar un servidor ni una base de datos.
 */

const AHORA = new Date('2026-09-17T12:00:00Z');

describe('estados de inscripción', () => {
  it('reconoce los cuatro estados válidos', () => {
    for (const estado of ['ENROLLED', 'WAITLISTED', 'PENDING_BID', 'DROPPED'] as const) {
      expect(esEstadoInscripcion(estado)).toBe(true);
    }
  });

  it('rechaza cualquier otra cosa, incluido un valor de otro tipo', () => {
    for (const valor of ['INSCRITO', 'enrolled', '', null, undefined, 3, {}, []]) {
      expect(esEstadoInscripcion(valor)).toBe(false);
    }
  });

  it('da un texto legible para cada estado', () => {
    expect(descripcionDeEstado('ENROLLED')).toBe('Inscrito');
    expect(descripcionDeEstado('WAITLISTED')).toBe('En lista de espera');
    expect(descripcionDeEstado('PENDING_BID')).toBe('Con una oferta de cupo pendiente');
    expect(descripcionDeEstado('DROPPED')).toBe('Dado de baja');
  });
});

describe('¿puede pedir un asiento?', () => {
  it('sí cuando no tiene fila en esa sección', () => {
    expect(puedeSolicitar(null)).toBe(true);
  });

  it('no en ninguno de los cuatro estados', () => {
    // Ni siquiera `DROPPED`: volver a entrar es una excepción de administración,
    // no una reinscripción libre. La fila se conserva como historial a propósito.
    for (const estado of ['ENROLLED', 'WAITLISTED', 'PENDING_BID', 'DROPPED'] as const) {
      expect(puedeSolicitar(estado)).toBe(false);
    }
  });
});

describe('vencimiento de una oferta', () => {
  it('una oferta sin fecha NO está vencida', () => {
    // `null` significa «no vence», no «vencida». Confundirlos entregaría el
    // asiento por la vía directa mientras la oferta sigue en el aire.
    expect(ofertaVencida(null, AHORA)).toBe(false);
  });

  it('una fecha futura no está vencida', () => {
    expect(ofertaVencida('2026-09-17T13:00:00Z', AHORA)).toBe(false);
  });

  it('una fecha pasada sí lo está', () => {
    expect(ofertaVencida('2026-09-17T11:00:00Z', AHORA)).toBe(true);
  });

  it('el instante exacto cuenta como vencido', () => {
    expect(ofertaVencida('2026-09-17T12:00:00Z', AHORA)).toBe(true);
  });

  it('una fecha ilegible se trata como NO vencida', () => {
    // El error seguro es no ofrecer el asiento de más, nunca de menos.
    expect(ofertaVencida('no-es-una-fecha', AHORA)).toBe(false);
  });
});

describe('la guarda contra la doble venta', () => {
  it('hay asiento con hueco y sin oferta viva', () => {
    expect(hayAsientoDisponible(1, 0, false)).toBe(true);
  });

  it('NO hay asiento si la sección está llena, aunque no haya oferta', () => {
    expect(hayAsientoDisponible(1, 1, false)).toBe(false);
  });

  it('NO hay asiento si hay hueco pero una oferta está en el aire', () => {
    // Éste es el caso que rompía todo: el contador dice 0/1 y el asiento ya está
    // comprometido. Sin esta mitad de la conjunción, dos personas acaban en un
    // asiento de una. La traza completa está en el comentario de la función.
    expect(hayAsientoDisponible(1, 0, true)).toBe(false);
  });

  it('tampoco hay asiento si está llena Y hay oferta', () => {
    expect(hayAsientoDisponible(1, 1, true)).toBe(false);
  });

  it('una sección con cupo 0 nunca tiene asiento', () => {
    expect(hayAsientoDisponible(0, 0, false)).toBe(false);
  });
});

describe('cupos que la interfaz puede ofrecer', () => {
  it('es la resta cuando no hay oferta en el aire', () => {
    expect(cuposOfrecibles(5, 2, false)).toBe(3);
  });

  it('es 0 cuando hay una oferta viva, aunque el contador diga que hay hueco', () => {
    // `cuposDisponibles` de la vista diría 1; ofrecerlo sería prometer algo que la
    // base va a negar. Por eso la pantalla no puede usar el contador como semáforo.
    expect(cuposOfrecibles(1, 0, true)).toBe(0);
  });

  it('nunca devuelve negativo cuando el admin reincorporó por encima del cupo', () => {
    // La regla institucional permite exceder la capacidad, así que ocupados puede
    // superar al efectivo. Un número negativo en la interfaz no significa nada.
    expect(cuposOfrecibles(1, 3, false)).toBe(0);
  });
});

describe('traducción de los mensajes de las RPC', () => {
  const MENSAJES = {
    acaparamiento:
      'El estudiante 22222222 ya tiene una sección de la materia aaaaaaaa en el lapso 2026-1. Un estudiante no puede acaparar cupos en dos secciones de la misma materia.',
    archivada: 'La sección cccccccc está archivada y no admite inscripciones.',
    inexistente: 'La sección cccccccc no existe.',
    ofertaVencida: 'La oferta de cupo para la sección cccccccc ya venció.',
    solicitudActiva: 'Ya tienes una solicitud activa (WAITLISTED) para la sección cccccccc.',
    yaCursaste: 'Ya cursaste la sección cccccccc: un administrador debe reincorporarte explícitamente.',
    sinHistorial: 'No existe una inscripción previa del estudiante 22222222 en la sección cccccccc.',
  };

  it('detecta el acaparamiento de dos secciones de la misma materia', () => {
    expect(esAcaparamientoDeMateria(MENSAJES.acaparamiento)).toBe(true);
    expect(esAcaparamientoDeMateria(MENSAJES.ofertaVencida)).toBe(false);
  });

  it('detecta la sección archivada', () => {
    expect(esSeccionArchivada(MENSAJES.archivada)).toBe(true);
    expect(esSeccionArchivada(MENSAJES.inexistente)).toBe(false);
  });

  it('detecta la sección inexistente', () => {
    expect(esSeccionInexistente(MENSAJES.inexistente)).toBe(true);
    expect(esSeccionInexistente(MENSAJES.archivada)).toBe(false);
  });

  it('no confunde «archivada» con «no existe» en ninguna dirección', () => {
    // Son dos 409 y un 404 con códigos distintos: si los patrones se solaparan, el
    // cliente recibiría el código equivocado y mostraría el mensaje equivocado.
    expect(esSeccionArchivada(MENSAJES.inexistente)).toBe(false);
    expect(esSeccionInexistente(MENSAJES.archivada)).toBe(false);
  });

  it('detecta la oferta vencida', () => {
    expect(esOfertaVencida(MENSAJES.ofertaVencida)).toBe(true);
    expect(esOfertaVencida(MENSAJES.solicitudActiva)).toBe(false);
  });

  it('detecta una solicitud que ya existía', () => {
    expect(esSolicitudYaExistente(MENSAJES.solicitudActiva)).toBe(true);
    expect(esSolicitudYaExistente(MENSAJES.acaparamiento)).toBe(false);
  });

  it('detecta el caso que exige reincorporación explícita', () => {
    expect(esRequiereReincorporacion(MENSAJES.yaCursaste)).toBe(true);
    expect(esRequiereReincorporacion(MENSAJES.solicitudActiva)).toBe(false);
  });

  it('detecta la reincorporación sin historial previo', () => {
    expect(esReincorporacionSinHistorial(MENSAJES.sinHistorial)).toBe(true);
    expect(esReincorporacionSinHistorial(MENSAJES.yaCursaste)).toBe(false);
  });

  it('sigue funcionando si alguien reescribe el mensaje sin tildes', () => {
    // Los patrones escriben `[oó]` y `[aá]` a propósito: si una migración futura
    // reescribiera el texto sin acento, la detección no debe romperse.
    expect(esSeccionArchivada('La seccion xxxx esta archivada y no admite inscripciones.')).toBe(true);
    expect(esOfertaVencida('La oferta de cupo para la seccion xxxx ya vencio.')).toBe(true);
    expect(esAcaparamientoDeMateria('ya tiene una seccion de la materia xxxx en el lapso 2026-1')).toBe(true);
  });

  it('no se dispara con un mensaje ajeno', () => {
    const otro = 'Los datos no cumplen una regla del sistema.';
    expect(esAcaparamientoDeMateria(otro)).toBe(false);
    expect(esSeccionArchivada(otro)).toBe(false);
    expect(esSeccionInexistente(otro)).toBe(false);
    expect(esOfertaVencida(otro)).toBe(false);
    expect(esSolicitudYaExistente(otro)).toBe(false);
    expect(esRequiereReincorporacion(otro)).toBe(false);
    expect(esReincorporacionSinHistorial(otro)).toBe(false);
  });
});
