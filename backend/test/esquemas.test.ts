import { describe, expect, it } from 'vitest';
import { ErrorApi } from '../src/dominio/errores.js';
import { ROLES, modulosVisibles } from '../src/dominio/tipos.js';
import {
  esquemaCambiosModulo,
  esquemaCambioRol,
  rolSchema,
  validarValorSegunTipo,
} from '../src/http/esquemas.js';
import { modulo } from './support/arnes.js';

describe('esquemas de entrada', () => {
  it('la lista de roles del esquema y la del dominio siguen coincidiendo', () => {
    // Si alguien añade un rol en `tipos.ts` y olvida el esquema (o al revés),
    // la API aceptaría o rechazaría roles de forma incoherente.
    expect([...rolSchema.options].sort()).toEqual([...ROLES].sort());
  });

  it('rechaza campos desconocidos en lugar de ignorarlos', () => {
    const resultado = esquemaCambiosModulo.safeParse({
      habilitado: true,
      es_critico: false,
    });

    expect(resultado.success).toBe(false);
  });

  it('rechaza un cuerpo sin ningún cambio', () => {
    expect(esquemaCambiosModulo.safeParse({}).success).toBe(false);
  });

  it('acepta un cambio parcial válido', () => {
    const resultado = esquemaCambiosModulo.safeParse({ orden: 42 });
    expect(resultado.success).toBe(true);
    if (resultado.success) expect(resultado.data.orden).toBe(42);
  });

  it('rechaza un rol inexistente', () => {
    expect(esquemaCambioRol.safeParse({ rol: 'superadmin' }).success).toBe(false);
  });
});

describe('validación del valor según el tipo declarado', () => {
  it('acepta un número cuando el parámetro es de tipo number', () => {
    expect(() => validarValorSegunTipo('number', 5, 'max_faltas')).not.toThrow();
  });

  it('rechaza texto cuando el parámetro es de tipo number', () => {
    expect(() => validarValorSegunTipo('number', 'cinco', 'max_faltas')).toThrowError(
      /espera un valor de tipo number/,
    );
  });

  it('rechaza NaN y Infinity, que pasarían un `typeof` ingenuo', () => {
    expect(() => validarValorSegunTipo('number', Number.NaN, 'max_faltas')).toThrow();
    expect(() =>
      validarValorSegunTipo('number', Number.POSITIVE_INFINITY, 'max_faltas'),
    ).toThrow();
  });

  it('rechaza el número 1 para un parámetro booleano', () => {
    expect(() => validarValorSegunTipo('boolean', 1, 'modo_mantenimiento')).toThrow();
  });

  it('acepta cualquier valor para un parámetro de tipo json', () => {
    expect(() =>
      validarValorSegunTipo('json', { a: [1, 2, 3] }, 'configuracion_libre'),
    ).not.toThrow();
  });

  it('avisa si el parámetro declara un tipo desconocido', () => {
    expect(() => validarValorSegunTipo('inventado', 1, 'raro')).toThrowError(
      /tipo desconocido/,
    );
  });

  it('el error es un ErrorApi de validación, no un Error genérico', () => {
    try {
      validarValorSegunTipo('number', 'cinco', 'max_faltas');
      expect.unreachable('debió lanzar');
    } catch (error) {
      expect(error).toBeInstanceOf(ErrorApi);
      expect((error as ErrorApi).codigo).toBe('PETICION_INVALIDA');
      expect((error as ErrorApi).estado).toBe(400);
    }
  });
});

describe('visibilidad de módulos por rol', () => {
  it('oculta los módulos apagados', () => {
    const visibles = modulosVisibles(
      [
        modulo({ clave: 'a', habilitado: true, orden: 1 }),
        modulo({ clave: 'b', habilitado: false, orden: 2 }),
      ],
      'estudiante',
    );

    expect(visibles.map((m) => m.clave)).toEqual(['a']);
  });

  it('trata una lista de roles vacía como «visible para todos»', () => {
    const visibles = modulosVisibles(
      [modulo({ clave: 'a', rolesPermitidos: [] })],
      'estudiante',
    );

    expect(visibles).toHaveLength(1);
  });

  it('respeta la lista blanca de roles', () => {
    const modulos = [modulo({ clave: 'panel', rolesPermitidos: ['admin'] })];

    expect(modulosVisibles(modulos, 'admin')).toHaveLength(1);
    expect(modulosVisibles(modulos, 'estudiante')).toHaveLength(0);
  });

  it('ordena por `orden` y, a igualdad, por clave', () => {
    const visibles = modulosVisibles(
      [
        modulo({ clave: 'z', orden: 10 }),
        modulo({ clave: 'a', orden: 10 }),
        modulo({ clave: 'primero', orden: 1 }),
      ],
      'admin',
    );

    expect(visibles.map((m) => m.clave)).toEqual(['primero', 'a', 'z']);
  });
});
