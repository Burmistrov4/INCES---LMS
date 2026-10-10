/**
 * Limpieza del ciclo E2E de Aula Virtual (`e2e/tests/aula_virtual_ciclo.spec.ts`).
 *
 * POR QUÉ EXISTE
 * --------------
 * Ese spec **muta datos reales**: crea una tarea, hace que un aprendiz la
 * entregue y que el docente la califique y devuelva. No hay ruta HTTP de borrado
 * de tareas, así que hasta ahora la suite quedaba excluida «hasta demostrar
 * limpieza verificable». Este script es esa limpieza.
 *
 * CÓMO LIMPIA
 * -----------
 * Borra SÓLO las tareas del ciclo creadas dentro de una ventana temporal, y nada
 * más. `m6_entregas.tarea_id` referencia `m6_tareas(id) on delete cascade`, así
 * que borrar la tarea arrastra sus entregas. Nunca toca tareas ajenas ni datos
 * anteriores a la ventana.
 *
 * SEGURIDAD
 * ---------
 * Sin `--confirmar` **no borra nada**: sólo lista lo que borraría y el conteo.
 * Al terminar comprueba que no quedan entregas huérfanas.
 *
 * USO
 * ---
 *   node supabase/limpiar-ciclo-aula.mjs                     # lista (no borra)
 *   node supabase/limpiar-ciclo-aula.mjs --confirmar         # borra la última hora
 *   node supabase/limpiar-ciclo-aula.mjs --confirmar --desde "2026-10-09T12:45:00Z"
 *
 * FUERA DE CI A PROPÓSITO: escribe en la base real.
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = dirname(fileURLToPath(import.meta.url));
const RAIZ = join(AQUI, '..');
const CONFIRMAR = process.argv.includes('--confirmar');

const argDesde = (() => {
  const i = process.argv.indexOf('--desde');
  return i >= 0 ? process.argv[i + 1] : null;
})();
// Ventana por defecto: la última hora. Suficiente para una corrida del spec.
const DESDE = argDesde ?? new Date(Date.now() - 60 * 60 * 1000).toISOString();

/** Lee del entorno y, si no está, de `backend/.env`. */
function variable(nombre) {
  const delEntorno = (process.env[nombre] ?? '').trim();
  if (delEntorno.length > 0) return delEntorno;
  try {
    for (const linea of readFileSync(join(RAIZ, 'backend', '.env'), 'utf8').split('\n')) {
      const limpia = linea.trim();
      if (limpia.length === 0 || limpia.startsWith('#')) continue;
      const corte = limpia.indexOf('=');
      if (corte < 0) continue;
      if (limpia.slice(0, corte).trim() === nombre) return limpia.slice(corte + 1).trim();
    }
  } catch {
    // Sin .env legible: se tratará como variable ausente.
  }
  return '';
}

const PAT = variable('SUPABASE_ACCESS_TOKEN');
const REF = 'twdppwnxlnmxkiejbrei';

if (!PAT) {
  console.error('\n  Falta SUPABASE_ACCESS_TOKEN (en backend/.env).\n');
  process.exit(1);
}

async function consultar(sql) {
  const r = await fetch(`https://api.supabase.com/v1/projects/${REF}/database/query`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${PAT}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: sql }),
  });
  const texto = await r.text();
  let datos;
  try { datos = JSON.parse(texto); } catch { datos = texto; }
  if (!r.ok) throw new Error(`consulta falló (${r.status}): ${texto.slice(0, 200)}`);
  return datos;
}

const PATRON = "titulo like 'Tarea E2E [ciclo] %'";
// El instante se interpola como literal ISO entrecomillado; se escapan comillas
// simples para que un valor raro no rompa la consulta.
const DESDE_SQL = `'${DESDE.replace(/'/g, "''")}'`;

console.log(`\n  Proyecto : ${REF}`);
console.log(`  Ventana  : tareas del ciclo creadas desde ${DESDE}`);
console.log(`  Modo     : ${CONFIRMAR ? 'BORRAR' : 'LISTAR (no borra)'}\n`);

const antes = await consultar(
  `select
     (select count(*) from public.m6_tareas)::int as tareas,
     (select count(*) from public.m6_entregas)::int as entregas`,
);

const candidatas = await consultar(
  `select id, titulo, created_at from public.m6_tareas
    where ${PATRON} and created_at > ${DESDE_SQL}
    order by created_at`,
);

console.log(`  Tareas del ciclo en la ventana: ${candidatas.length}`);
for (const t of candidatas) console.log(`    · ${t.titulo}  (${t.created_at})`);

if (candidatas.length === 0) {
  console.log('\n  Nada que borrar.\n');
  process.exit(0);
}

if (!CONFIRMAR) {
  console.log('\n  Simulación: no se borró nada. Repite con --confirmar.\n');
  process.exit(0);
}

const borradas = await consultar(
  `delete from public.m6_tareas
    where ${PATRON} and created_at > ${DESDE_SQL}
    returning id`,
);

const despues = await consultar(
  `select
     (select count(*) from public.m6_tareas)::int as tareas,
     (select count(*) from public.m6_entregas)::int as entregas,
     (select count(*) from public.m6_entregas e
        left join public.m6_tareas t on t.id = e.tarea_id
       where t.id is null)::int as huerfanas`,
);

console.log(`\n  Borradas: ${borradas.length}`);
console.log(`  Tareas   : ${antes[0].tareas} → ${despues[0].tareas}`);
console.log(`  Entregas : ${antes[0].entregas} → ${despues[0].entregas}`);
console.log(`  Huérfanas: ${despues[0].huerfanas} (debe ser 0)\n`);

process.exit(despues[0].huerfanas === 0 ? 0 : 1);
