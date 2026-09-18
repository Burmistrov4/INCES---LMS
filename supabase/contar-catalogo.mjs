#!/usr/bin/env node
/**
 * contar-catalogo.mjs — recuenta los objetos del esquema contra la base REAL.
 *
 * POR QUÉ EXISTE
 * --------------
 * `ESTADO_DEL_SISTEMA.md` afirma: «Estas cifras están medidas, no estimadas».
 * Pero medirlas a mano cada vez es justo lo que se olvida, y entonces el
 * documento se desincroniza en silencio (es el defecto que produjo D11, y volvió
 * a pasar el 2026-09-18: las cifras de M4 llevaban un día viejas).
 *
 * Este script cierra ese hueco: cuenta los objetos y los imprime listos para
 * pegar en el §2 del documento. **Es de SOLO LECTURA** — no escribe nada.
 *
 * USO
 * ---
 *   SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/contar-catalogo.mjs
 *
 * Necesita un token de la Management API (sbp_), NO la service key: la service
 * key da 401 contra esta ruta. Es el mismo requisito que apply-migrations.mjs.
 *
 * Nota: `supabase db push` no sirve en este proyecto (la conexión directa es
 * sólo IPv6), y por eso todo va por HTTPS contra la Management API.
 */

const token = process.env.SUPABASE_ACCESS_TOKEN;
const ref = process.env.SUPABASE_PROJECT_REF ?? 'twdppwnxlnmxkiejbrei';

if (!token) {
  console.error('Falta SUPABASE_ACCESS_TOKEN (token sbp_ de la Management API).');
  process.exit(1);
}

/** Una sola consulta: así todas las cifras vienen del mismo instante. */
const CONSULTA = `
select
  (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r')                     as tablas,
  (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r' and c.relrowsecurity) as tablas_con_rls,
  (select count(*) from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'v')                     as vistas,
  (select count(*) from pg_proc p
     join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public')                                         as funciones,
  (select count(*) from pg_trigger t
     join pg_class c on c.oid = t.tgrelid
     join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and not t.tgisinternal)                  as triggers,
  (select count(*) from pg_policies where schemaname = 'public')        as politicas_rls,
  (select count(*) from public.system_modules)                          as modulos,
  (select count(*) from public.system_modules where habilitado)         as modulos_habilitados,
  (select count(*) from public.system_settings)                         as parametros,
  (select count(*) from public.academic_periods)                        as lapsos,
  (select count(*) from public.programs where type = 'CURSO_LIBRE')     as cursos_libres,
  (select count(*) from public.schema_migrations)                       as migraciones;
`;

try {
  const respuesta = await fetch(
    `https://api.supabase.com/v1/projects/${ref}/database/query`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ query: CONSULTA }),
    },
  );

  const texto = await respuesta.text();

  if (!respuesta.ok) {
    console.error(`ERROR HTTP ${respuesta.status}: ${texto.slice(0, 500)}`);
    process.exit(1);
  }

  const crudo = JSON.parse(texto);
  const f = Array.isArray(crudo) ? crudo[0] : crudo;

  const n = (clave) => Number(f[clave] ?? 0);

  console.log(`Proyecto : ${ref}`);
  console.log('');
  console.log(
    `  ${n('tablas')} tablas con RLS activo en las ${n('tablas_con_rls')}, ` +
      `${n('vistas')} vistas, ${n('funciones')} funciones, ` +
      `${n('triggers')} triggers y ${n('politicas_rls')} políticas RLS, más ` +
      `${n('modulos')} módulos sembrados, ${n('parametros')} parámetros, ` +
      `${n('lapsos')} lapso(s) y ${n('cursos_libres')} cursos.`,
  );
  console.log('');
  console.log(`  Migraciones aplicadas: ${n('migraciones')}`);
  console.log(`  Módulos habilitados  : ${n('modulos_habilitados')} de ${n('modulos')}`);
  console.log('');
  console.log('Pega la primera línea en ESTADO_DEL_SISTEMA.md §2.');
  console.log('Si la aritmética no cierra contra el cambio que aplicaste, algo se');
  console.log('coló sin documentar — y eso es exactamente lo que busca este script.');
} catch (error) {
  console.error('ERROR:', error?.message ?? error);
  process.exit(1);
}
