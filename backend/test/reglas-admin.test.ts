import { describe, expect, it } from 'vitest';

import { ErrorApi } from '../src/dominio/errores.js';
import { revisarCambioDeRol, type CambioDeRol } from '../src/dominio/reglas-admin.js';
import type { Perfil, Rol } from '../src/dominio/tipos.js';
import { ID_ADMIN, ID_ALUMNO, PERFIL_ADMIN, PERFIL_ALUMNO } from './support/arnes.js';

function perfil(id: string, rol: Rol, activo = true): Perfil {
  return {
    id,
    email: `${id}@inces.test`,
    cedula: null,
    nombres: 'Prueba',
    apellidos: 'Prueba',
    rol,
    activo,
  };
}

/** Ejecuta la regla y devuelve el error, o falla si no lanzó ninguno. */
function capturar(cambio: CambioDeRol): ErrorApi {
  try {
    revisarCambioDeRol(cambio);
  } catch (error) {
    if (error instanceof ErrorApi) return error;
    throw error;
  }
  throw new Error('la regla no lanzó ningún error');
}

describe('revisarCambioDeRol — quitarse el rol a uno mismo', () => {
  it('rechaza que un administrador se degrade a sí mismo', () => {
    const error = capturar({
      actorId: ID_ADMIN,
      objetivoId: ID_ADMIN,
      nuevoRol: 'docente',
      objetivo: PERFIL_ADMIN,
      adminsActivos: 3,
    });

    expect(error.codigo).toBe('AUTO_DEGRADACION');
    expect(error.estado).toBe(409);
  });

  it('el mensaje dice qué hacer, no sólo que no se puede', () => {
    const error = capturar({
      actorId: ID_ADMIN,
      objetivoId: ID_ADMIN,
      nuevoRol: 'estudiante',
      objetivo: PERFIL_ADMIN,
      adminsActivos: 5,
    });

    expect(error.message).toMatch(/Pídeselo a otro administrador/);
  });

  it('permite confirmarse a sí mismo como administrador', () => {
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: ID_ADMIN,
        nuevoRol: 'admin',
        objetivo: PERFIL_ADMIN,
        adminsActivos: 1,
      }),
    ).not.toThrow();
  });
});

describe('revisarCambioDeRol — ascensos', () => {
  it('permite ascender a administrador aunque no quede ninguno más', () => {
    // Promover nunca reduce el número de administradores, así que no hay nada
    // que proteger: es justo la acción que repara un sistema sin administradores.
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: ID_ALUMNO,
        nuevoRol: 'admin',
        objetivo: PERFIL_ALUMNO,
        adminsActivos: 1,
      }),
    ).not.toThrow();
  });

  it('no exige que el objetivo exista para ascender', () => {
    // El ascenso sale antes de mirar el perfil, así que un objetivo ausente no
    // se convierte en un error inesperado.
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: 'inexistente',
        nuevoRol: 'admin',
        objetivo: null,
        adminsActivos: 1,
      }),
    ).not.toThrow();
  });
});

describe('revisarCambioDeRol — degradar a otro', () => {
  it('rechaza un objetivo inexistente con un código propio, no un fallo crudo', () => {
    const error = capturar({
      actorId: ID_ADMIN,
      objetivoId: '00000000-0000-0000-0000-000000000000',
      nuevoRol: 'docente',
      objetivo: null,
      adminsActivos: 2,
    });

    expect(error.codigo).toBe('PERFIL_INEXISTENTE');
    expect(error.estado).toBe(404);
  });

  it('permite degradar a un administrador cuando queda otro', () => {
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: ID_ALUMNO,
        nuevoRol: 'docente',
        objetivo: perfil(ID_ALUMNO, 'admin', true),
        adminsActivos: 2,
      }),
    ).not.toThrow();
  });

  it('rechaza degradar al último administrador activo', () => {
    // Caso que la API no alcanza en su funcionamiento normal —quien actúa es a
    // su vez un administrador activo— pero que la regla debe cubrir: es la
    // invariante del sistema y una ruta futura de desactivación podría llegar a
    // él.
    const error = capturar({
      actorId: ID_ADMIN,
      objetivoId: ID_ALUMNO,
      nuevoRol: 'docente',
      objetivo: perfil(ID_ALUMNO, 'admin', true),
      adminsActivos: 1,
    });

    expect(error.codigo).toBe('ULTIMO_ADMIN');
    expect(error.estado).toBe(409);
    expect(error.message).toMatch(/Promueve a otra persona/);
    expect(error.detalles).toEqual({ administradoresActivos: 1 });
  });

  it('permite degradar a un administrador DESACTIVADO: no reduce los activos', () => {
    // Un administrador inactivo no puede entrar al sistema, así que quitarle el
    // rol no deja a nadie sin acceso: no hay nada que proteger.
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: ID_ALUMNO,
        nuevoRol: 'estudiante',
        objetivo: perfil(ID_ALUMNO, 'admin', false),
        adminsActivos: 1,
      }),
    ).not.toThrow();
  });

  it('permite degradar a quien no era administrador', () => {
    expect(() =>
      revisarCambioDeRol({
        actorId: ID_ADMIN,
        objetivoId: ID_ALUMNO,
        nuevoRol: 'estudiante',
        objetivo: PERFIL_ALUMNO,
        adminsActivos: 1,
      }),
    ).not.toThrow();
  });
});
