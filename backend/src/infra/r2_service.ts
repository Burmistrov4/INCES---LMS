/**
 * Implementación de almacenamiento sobre Cloudflare R2.
 *
 * R2 es compatible con la API de S3, así que se usa el SDK oficial de AWS
 * apuntando al endpoint de R2. Son dos ajustes los que hacen que funcione, y
 * ninguno es opcional:
 *
 *   · `region: 'auto'`      — R2 no tiene regiones; con otra cosa firma mal.
 *   · `forcePathStyle: true` — R2 no soporta direccionamiento virtual-host, así
 *     que sin esto el cliente resolvería `<bucket>.<cuenta>.r2.cloudflarestorage.com`,
 *     que no existe.
 *
 * El resto del archivo es traducción de errores: un fallo de R2 no debe llegar
 * al usuario como un 500 genérico, igual que ya se hizo con PostgreSQL.
 */
import {
  DeleteObjectCommand,
  GetObjectCommand,
  HeadObjectCommand,
  PutObjectCommand,
  S3Client,
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import type { ConfigR2, Env } from '../config/env.js';
import { configuracionR2 } from '../config/env.js';
import {
  cabeceraDisposicion,
  construirClave,
  extensionDe,
  tipoContenidoDe,
  validarClave,
  type PeticionUrlSubida,
  type UrlFirmada,
} from '../dominio/almacenamiento.js';
import { ErrorApi } from '../dominio/errores.js';
import type { PuertaAlmacenamiento } from '../dominio/puertos.js';
import { mensajeDe, pareceMensajeDeRed } from './traducir-error.js';

/** Nombres con los que el SDK de S3 señala que el objeto no está. */
const NO_ENCONTRADO = new Set(['NotFound', 'NoSuchKey', 'NoSuchBucket']);

/** Nombres que delatan credenciales o permisos incorrectos. */
const DENEGADO = new Set([
  'AccessDenied',
  'InvalidAccessKeyId',
  'SignatureDoesNotMatch',
  'RequestTimeTooSkewed',
]);

function nombreDe(error: unknown): string {
  if (typeof error === 'object' && error !== null && 'name' in error) {
    const nombre = (error as { name?: unknown }).name;
    if (typeof nombre === 'string') return nombre;
  }
  return '';
}

function esNoEncontrado(error: unknown): boolean {
  return NO_ENCONTRADO.has(nombreDe(error));
}

/**
 * Convierte un fallo del SDK en un [ErrorApi] con código estable.
 *
 * Se comprueba primero el transporte, por la misma razón que en
 * `traducir-error.ts`: un fallo de red llega envuelto en un error con forma de
 * error del servicio, y si se mirara antes el nombre, nunca se detectaría.
 */
function traducirFallo(error: unknown, operacion: string): never {
  if (error instanceof ErrorApi) throw error;

  if (pareceMensajeDeRed(mensajeDe(error))) {
    throw ErrorApi.servicioNoDisponible(
      'No pudimos comunicarnos con el almacenamiento. Inténtalo de nuevo.',
    );
  }

  if (esNoEncontrado(error)) {
    throw ErrorApi.noEncontrado(
      'ARCHIVO_NO_ENCONTRADO',
      'El archivo no existe en el almacenamiento.',
    );
  }

  if (DENEGADO.has(nombreDe(error))) {
    throw ErrorApi.prohibido(
      'ALMACENAMIENTO_DENEGADO',
      'El almacenamiento rechazó la operación.',
      { operacion },
    );
  }

  throw new ErrorApi(
    500,
    'ERROR_ALMACENAMIENTO',
    'Ocurrió un error al acceder al almacenamiento.',
    { operacion },
  );
}

export function crearAlmacenamientoR2(config: ConfigR2): PuertaAlmacenamiento {
  const cliente = new S3Client({
    region: 'auto',
    endpoint: `https://${config.accountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: config.accessKeyId,
      secretAccessKey: config.secretAccessKey,
    },
    forcePathStyle: true,
  });

  return {
    async urlDeSubida(peticion: PeticionUrlSubida): Promise<UrlFirmada> {
      // La clave se construye aquí. `nombreOriginal` sólo aporta la extensión:
      // si el cliente pudiera proponer la clave, esta URL firmada sería una
      // autorización para sobrescribir cualquier objeto del bucket.
      const clave = construirClave(peticion.prefijo, peticion.nombreOriginal);
      const tipoContenido = tipoContenidoDe(extensionDe(peticion.nombreOriginal));

      const comando = new PutObjectCommand({
        Bucket: config.bucket,
        Key: clave,
        ContentType: tipoContenido,
      });

      const url = await getSignedUrl(cliente, comando, {
        expiresIn: config.ttlSubidaSegundos,
        // Sin `signableHeaders`, el SDK firma SÓLO `host` y el `ContentType` del
        // comando se descarta: el cliente podría subir el objeto declarando
        // cualquier tipo. Firmarlo obliga a que el navegador envíe exactamente
        // este `Content-Type` o R2 rechace la firma.
        signableHeaders: new Set(['content-type']),
      }).catch((error: unknown) => traducirFallo(error, 'firmar subida'));

      return {
        clave,
        url,
        expiraEnSegundos: config.ttlSubidaSegundos,
        tipoContenido,
      };
    },

    async urlDeDescarga(
      clave: string,
      nombreDescarga?: string,
    ): Promise<UrlFirmada> {
      const limpia = validarClave(clave);

      const comando = new GetObjectCommand({
        Bucket: config.bucket,
        Key: limpia,
        // `Content-Disposition` fuerza la descarga con el nombre legible en vez
        // de mostrar el UUID que usa el objeto. El nombre original vive en la
        // base de datos; aquí sólo se aplica.
        ...(nombreDescarga === undefined
          ? {}
          : { ResponseContentDisposition: cabeceraDisposicion(nombreDescarga) }),
      });

      const url = await getSignedUrl(cliente, comando, {
        expiresIn: config.ttlDescargaSegundos,
      }).catch((error: unknown) => traducirFallo(error, 'firmar descarga'));

      return {
        clave: limpia,
        url,
        expiraEnSegundos: config.ttlDescargaSegundos,
        tipoContenido: tipoContenidoDe(extensionDe(limpia)),
      };
    },

    async estadisticas(clave: string): Promise<{ tamanoBytes: number } | null> {
      const limpia = validarClave(clave);

      const salida = await cliente
        .send(new HeadObjectCommand({ Bucket: config.bucket, Key: limpia }))
        .catch((error: unknown) => {
          // «No existe» es una respuesta legítima, no un fallo: una subida
          // interrumpida deja la fila PENDING sin objeto que confirmar.
          if (esNoEncontrado(error)) return null;
          traducirFallo(error, 'comprobar existencia');
        });

      if (salida === null) return null;

      const tamano = salida.ContentLength;

      // `ContentLength` es opcional en el tipo del SDK aunque `HeadObject`
      // siempre lo devuelva. Si faltara, tomarlo por 0 haría pasar la
      // comprobación de tamaño a un objeto que nadie midió: es un dato corrupto,
      // y se falla en alto en vez de dejar entrar un archivo sin medir.
      if (typeof tamano !== 'number' || !Number.isFinite(tamano) || tamano < 0) {
        throw new ErrorApi(
          500,
          'ERROR_ALMACENAMIENTO',
          'El almacenamiento no informó del tamaño del objeto.',
          { operacion: 'comprobar existencia', clave: limpia },
        );
      }

      return { tamanoBytes: tamano };
    },

    async eliminar(clave: string): Promise<void> {
      const limpia = validarClave(clave);

      try {
        await cliente.send(
          new DeleteObjectCommand({ Bucket: config.bucket, Key: limpia }),
        );
      } catch (error) {
        traducirFallo(error, 'eliminar objeto');
      }
    },
  };
}

/**
 * Construye el almacenamiento a partir del entorno, o `null` si no está activo.
 *
 * Devolver `null` es intencional: R2 es una capacidad opcional y el backend debe
 * arrancar sin ella. Quien consuma el puerto decide qué hacer cuando es `null`
 * —típicamente responder 503 en la ruta de M5—, en lugar de que el proceso no
 * levante por un módulo que todavía no se usa.
 */
export function crearAlmacenamiento(env: Env): PuertaAlmacenamiento | null {
  const config = configuracionR2(env);
  return config === null ? null : crearAlmacenamientoR2(config);
}
