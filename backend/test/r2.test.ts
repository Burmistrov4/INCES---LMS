import { describe, expect, it } from 'vitest';

import { cargarEnv, configuracionR2 } from '../src/config/env.js';
import { ErrorApi } from '../src/dominio/errores.js';
import {
  TAMANO_MAXIMO_BYTES,
  cabeceraDisposicion,
  construirClave,
  extensionDe,
  normalizarPrefijo,
  prefijoDeArchivo,
  validarClave,
  validarTamano,
} from '../src/dominio/almacenamiento.js';
import { crearAlmacenamiento, crearAlmacenamientoR2 } from '../src/infra/r2_service.js';

/** Entorno mínimo válido para construir la configuración. */
function entorno(extra: Record<string, string> = {}) {
  return cargarEnv({
    SUPABASE_URL: 'https://prueba.supabase.co',
    SUPABASE_ANON_KEY: 'clave-anonima-de-prueba-1234567890',
    SUPABASE_SERVICE_ROLE_KEY: 'clave-de-servicio-de-prueba-1234567890',
    ...extra,
  });
}

const R2_COMPLETO = {
  CLOUDFLARE_ACCOUNT_ID: 'cuenta-de-prueba',
  R2_ACCESS_KEY_ID: 'acceso-de-prueba',
  R2_SECRET_ACCESS_KEY: 'secreto-de-prueba',
  R2_BUCKET: 'inces-lms-archivos',
};

/** Servicio real, con credenciales falsas. Firmar es local: no hay red. */
function almacen() {
  const config = configuracionR2(entorno(R2_COMPLETO));
  if (config === null) throw new Error('la configuración de prueba no se resolvió');
  return crearAlmacenamientoR2(config);
}

/** Lee un parámetro de la query string de una URL firmada. */
function parametro(url: string, nombre: string): string | null {
  return new URL(url).searchParams.get(nombre);
}

describe('claves de almacenamiento', () => {
  it('normaliza el prefijo y rechaza mayúsculas y barras sobrantes', () => {
    expect(normalizarPrefijo('/M5_Archivos/2026/')).toBe('m5_archivos/2026');
  });

  it('rechaza un prefijo con recorrido de rutas', () => {
    expect(() => normalizarPrefijo('m5_archivos/../..')).toThrowError(/«\.\.»/);
  });

  it('rechaza un prefijo vacío', () => {
    expect(() => normalizarPrefijo('   ')).toThrowError(/no puede estar vacío/);
  });

  it('acepta las extensiones permitidas y rechaza el resto', () => {
    expect(extensionDe('informe.PDF')).toBe('.pdf');
    expect(() => extensionDe('script.exe')).toThrowError(/Extensión no permitida/);
  });

  it('rechaza un archivo sin extensión', () => {
    expect(() => extensionDe('LEEME')).toThrowError(/no tiene extensión/);
  });

  it('compone la clave con el prefijo, un identificador y la extensión', () => {
    const clave = construirClave('m5_archivos/2026', 'informe.pdf', () => 'fijo');

    expect(clave).toBe('m5_archivos/2026/fijo.pdf');
  });

  it('reparte los archivos por propietario, año y mes', () => {
    const prefijo = prefijoDeArchivo('A1B2-C3D4', new Date('2026-09-12T00:00:00Z'));

    expect(prefijo).toBe('m5_archivos/a1b2-c3d4/2026/09');
  });

  it('sanea el identificador del propietario antes de usarlo como carpeta', () => {
    const prefijo = prefijoDeArchivo('../../etc/passwd');

    expect(prefijo).not.toContain('..');
    expect(prefijo.startsWith('m5_archivos/')).toBe(true);
  });

  it('rechaza una clave absoluta o con recorrido de rutas', () => {
    expect(() => validarClave('/etc/passwd')).toThrowError(/absoluta/);
    expect(() => validarClave('m5_archivos/../../secreto.pdf')).toThrowError(/«\.\.»/);
  });

  it('conserva los acentos al fijar el nombre de descarga', () => {
    const cabecera = cabeceraDisposicion('Constancia José.pdf');

    // La forma simple es ASCII; la extendida (RFC 5987) lleva el original.
    expect(cabecera).toContain('filename="Constancia Jos_.pdf"');
    expect(cabecera).toContain("filename*=UTF-8''Constancia%20Jos%C3%A9.pdf");
  });

  it('impide que un nombre de archivo cierre la cabecera e inyecte otra', () => {
    const cabecera = cabeceraDisposicion('a".pdf\r\nX-Inyectado: si');

    // El salto de línea es lo único que separa una cabecera de la siguiente.
    // Sin él, «X-Inyectado» es texto inerte dentro del nombre, no una cabecera:
    // por eso no se prohíbe la subcadena, se prohíbe el salto.
    expect(cabecera).not.toMatch(/[\r\n]/);
    // Sin comillas el valor no puede cerrarse antes de tiempo, así que la
    // cabecera sigue siendo una sola.
    expect(cabecera.match(/filename="/g)).toHaveLength(1);
  });
});

describe('límite de tamaño (validarTamano)', () => {
  it('expone 10 MB como valor por defecto', () => {
    expect(TAMANO_MAXIMO_BYTES).toBe(10 * 1024 * 1024);
  });

  it('acepta un archivo que cabe y también el límite exacto', () => {
    expect(() => validarTamano(0, TAMANO_MAXIMO_BYTES)).not.toThrow();
    expect(() => validarTamano(1, TAMANO_MAXIMO_BYTES)).not.toThrow();
    // El límite es «hasta», no «menos que»: justo en el borde debe pasar.
    expect(() => validarTamano(TAMANO_MAXIMO_BYTES, TAMANO_MAXIMO_BYTES)).not.toThrow();
  });

  it('rechaza un archivo que supera el límite por un solo byte, con 413', () => {
    // 413 y no 400, y el código importa: el cliente reacciona distinto ante un
    // archivo grande —vuelve a subir algo más pequeño— que ante un dato mal
    // formado. Un 400 para las dos cosas dejaba al cliente adivinando.
    try {
      validarTamano(TAMANO_MAXIMO_BYTES + 1, TAMANO_MAXIMO_BYTES);
      expect.unreachable('validarTamano debía rechazar el archivo');
    } catch (error) {
      expect(error).toBeInstanceOf(ErrorApi);
      expect((error as ErrorApi).estado).toBe(413);
      expect((error as ErrorApi).codigo).toBe('ARCHIVO_DEMASIADO_GRANDE');
      expect((error as ErrorApi).message).toMatch(/máximo permitido/);
    }
  });

  it('rechaza un tamaño negativo, NaN o infinito como dato corrupto, con 400', () => {
    // Aquí sí es 400: lo que está mal es el dato, no lo que pesa el archivo. Es
    // la otra mitad de la distinción que introdujo el 413.
    const corruptos = [-1, Number.NaN, Number.POSITIVE_INFINITY, Number.NEGATIVE_INFINITY];

    for (const tamano of corruptos) {
      try {
        validarTamano(tamano, TAMANO_MAXIMO_BYTES);
        expect.unreachable(`validarTamano debía rechazar ${String(tamano)}`);
      } catch (error) {
        expect(error).toBeInstanceOf(ErrorApi);
        expect((error as ErrorApi).estado, `tamaño ${String(tamano)}`).toBe(400);
        expect((error as ErrorApi).message).toMatch(/no es un número válido/);
      }
    }
  });

  it('rechaza un límite de configuración inválido en vez de dejar pasar todo', () => {
    // Un límite NaN haría que `tamanoBytes > maximoBytes` fuera SIEMPRE falso
    // —toda comparación con NaN lo es— y cualquier archivo pasaría. Es el
    // agujero que este guard cierra.
    expect(() => validarTamano(1, Number.NaN)).toThrowError(/límite de tamaño configurado/);
    expect(() => validarTamano(1, -5)).toThrowError(/límite de tamaño configurado/);
  });

  it('el mensaje del exceso es legible (MB con un decimal)', () => {
    expect(() => validarTamano(11 * 1024 * 1024, TAMANO_MAXIMO_BYTES)).toThrowError(/11\.0 MB/);
  });
});

describe('configuración de R2', () => {
  it('devuelve `null` cuando no hay ninguna variable: el módulo está apagado', () => {
    expect(configuracionR2(entorno())).toBeNull();
  });

  it('lanza cuando la configuración está a medias, en vez de degradarse', () => {
    expect(() =>
      configuracionR2(entorno({ CLOUDFLARE_ACCOUNT_ID: 'cuenta-de-prueba' })),
    ).toThrowError(/R2 incompleta/);
  });

  it('nombra las variables que faltan para poder corregirlo sin adivinar', () => {
    expect(() =>
      configuracionR2(entorno({ CLOUDFLARE_ACCOUNT_ID: 'cuenta-de-prueba' })),
    ).toThrowError(/R2_ACCESS_KEY_ID/);
  });

  it('resuelve la configuración cuando están las cuatro variables', () => {
    const config = configuracionR2(entorno(R2_COMPLETO));

    expect(config?.bucket).toBe('inces-lms-archivos');
    expect(config?.ttlSubidaSegundos).toBe(300);
    expect(config?.ttlDescargaSegundos).toBe(900);
  });

  it('no construye el servicio si el módulo está apagado', () => {
    expect(crearAlmacenamiento(entorno())).toBeNull();
  });
});

describe('URLs prefirmadas', () => {
  it('firma una subida contra el endpoint de R2, con estilo de ruta', async () => {
    const { clave, url, expiraEnSegundos } = await almacen().urlDeSubida({
      prefijo: 'm5_archivos/a1b2/2026/09',
      nombreOriginal: 'informe.pdf',
    });

    const destino = new URL(url);

    // Sin `forcePathStyle` el host sería `<bucket>.<cuenta>...`, que no existe.
    expect(destino.host).toBe('cuenta-de-prueba.r2.cloudflarestorage.com');
    expect(destino.pathname).toBe(`/inces-lms-archivos/${clave}`);
    expect(expiraEnSegundos).toBe(300);
    expect(parametro(url, 'X-Amz-Expires')).toBe('300');
    expect(parametro(url, 'X-Amz-Signature')).toBeTruthy();
  });

  it('firma el tipo de contenido, para que el objeto no se guarde con otro', async () => {
    const { url } = await almacen().urlDeSubida({
      prefijo: 'm5_archivos/a1b2/2026/09',
      nombreOriginal: 'informe.pdf',
    });

    // Si el tipo va en los encabezados firmados, el cliente no puede cambiarlo.
    expect(parametro(url, 'X-Amz-SignedHeaders')).toContain('content-type');
  });

  it('firma una descarga con caducidad de 15 minutos', async () => {
    const { url, expiraEnSegundos } = await almacen().urlDeDescarga(
      'm5_archivos/a1b2/2026/09/fijo.pdf',
    );

    expect(expiraEnSegundos).toBe(900);
    expect(parametro(url, 'X-Amz-Expires')).toBe('900');
  });

  it('aplica el nombre legible sólo al descargar, no a la clave', async () => {
    const clave = 'm5_archivos/a1b2/2026/09/fijo.pdf';
    const { url } = await almacen().urlDeDescarga(clave, 'Constancia José.pdf');

    expect(parametro(url, 'response-content-disposition')).toContain('Jos%C3%A9');
    expect(new URL(url).pathname).toContain(clave);
  });

  it('no deja que el cliente elija la clave: dos subidas del mismo nombre no colisionan', async () => {
    const primera = await almacen().urlDeSubida({
      prefijo: 'm5_archivos/a1b2/2026/09',
      nombreOriginal: 'informe.pdf',
    });
    const segunda = await almacen().urlDeSubida({
      prefijo: 'm5_archivos/a1b2/2026/09',
      nombreOriginal: 'informe.pdf',
    });

    expect(primera.clave).not.toBe(segunda.clave);
  });

  it('neutraliza un nombre con recorrido de rutas: la clave no sale del prefijo', async () => {
    // Este es el ataque que evita construir la clave en el servidor: si la
    // propusiera el cliente, esta URL firmada podría sobrescribir cualquier
    // objeto del bucket.
    const { clave } = await almacen().urlDeSubida({
      prefijo: 'm5_archivos/a1b2/2026/09',
      nombreOriginal: '../../../../recursos/logo.png',
    });

    expect(clave.startsWith('m5_archivos/a1b2/2026/09/')).toBe(true);
    expect(clave).not.toContain('..');
    expect(clave).not.toContain('recursos');
  });

  it('rechaza una extensión no permitida antes de firmar nada', async () => {
    await expect(
      almacen().urlDeSubida({
        prefijo: 'm5_archivos/a1b2/2026/09',
        nombreOriginal: 'payload.exe',
      }),
    ).rejects.toThrowError(/Extensión no permitida/);
  });

  it('rechaza una descarga de una clave manipulada', async () => {
    await expect(
      almacen().urlDeDescarga('../../secreto.pdf'),
    ).rejects.toThrowError(/«\.\.»/);
  });
});
