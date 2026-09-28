# Validación de migraciones

Este directorio **no forma parte del producto**. Es un arnés para comprobar que
las migraciones SQL aplican y que las políticas RLS hacen lo que dicen, sin
necesitar Docker ni una instancia de Supabase en la nube.

## Por qué existe

Un error en una política RLS no rompe la compilación: rompe la seguridad, y se
descubre en producción. `flutter analyze` no ve el SQL. Este arnés sí.

## Uso

```bash
cd supabase/tests
npm install
npm test
```

El script imprime el total de aserciones al terminar y sale con código distinto
de cero si alguna falla. **El número no se escribe aquí a propósito**: este README
decía «40 aserciones» mientras el script ya iba por **494**, y una cifra copiada
envejece sola. Lo mide `medir-conteos.mjs` y lo imprime `npm test`.

## Herramientas del directorio

| Archivo | Para qué |
| --- | --- |
| `validate.mjs` | El arnés. Aplica todas las migraciones y ejerce semilla, RLS y vistas. Es lo que corre `npm test` y **lo que corre CI** |
| `medir-conteos.mjs` | Sólo lectura. Imprime los conteos que `ESTADO_DEL_SISTEMA.md` afirma como «medidos», para no copiarlos hacia adelante |
| `vectores-codigo-qr.mjs` | Genera los **vectores dorados** del código de asistencia (M7) con PostgreSQL de verdad, como literal de Dart para `test/asistencia_service_test.dart`. Herramienta de mantenimiento: **no** la ejecuta CI |
| `supabase_shim.sql` | Emula lo que Supabase aporta de fábrica (`auth`, `auth.uid()`, roles y privilegios por defecto) |

## Cómo funciona

1. Levanta un **PostgreSQL real** mediante [PGlite](https://pglite.dev)
   (Postgres compilado a WASM, corre en Node).
2. Aplica `supabase_shim.sql`, que emula lo que Supabase aporta de fábrica:
   esquema `auth`, `auth.uid()`, roles `anon`/`authenticated`/`service_role` y
   los privilegios por defecto sobre tablas y funciones nuevas.
3. Aplica **todas** las migraciones de `supabase/migrations/` en orden
   alfabético.
4. Ejecuta aserciones sobre el resultado.

## Qué cubre

Las secciones del script, en su orden y con sus propios títulos. **Se copiaron del
script el 2026-09-27**; si añades una sección a `validate.mjs` y no la añades aquí,
este README empieza a mentir — que es exactamente lo que le había pasado.

| # | Bloque | Comprueba |
| --- | --- | --- |
| 1–6 | Núcleo | Aplicación de migraciones, semilla de `system_modules` y de `system_settings`, cortacircuitos del cPanel, auditoría de configuración e idempotencia de la semilla |
| 7 | Onboarding | El trigger crea perfil y ficha atómicamente, con datos de prueba |
| 8–11 | RLS y restricciones | Usuario autenticado sin privilegios, administrador, visitante anónimo, y restricciones de integridad (roles, formato de clave, tipo de parámetro) |
| 12 | D8 | Protección del último administrador activo |
| 13–16 | Módulo 2 | Currículo y Pensum, `programs` absorbiendo cursos (D12), `sections` rediseñada (D13) y las RPC del asistente |
| 17 | Módulo 3 | Aulas, períodos, guardias y cuadrante — incluida la comprobación de que el trigger funciona para un `authenticated` real y no para el dueño de la tabla |
| 18 | Módulo 4 | Inscripciones y cupos: cola FIFO, ofertas y reincorporación |
| 19 | Módulo 5 | Archivos (R2): RLS, RPCs y frontera de escritura |
| 20 | Módulo 6 | Aula Virtual: RLS, RPCs y el ciclo de calificación |
| 21–22 | Planilla (M4) | Catálogo de inscripción y `datos_planilla`, y la guardia de escritura de la planilla |
| 23 | HACER (M4) | Exportación: `v_exportacion_hacer` filtra por `ENROLLED`, aplana el catálogo y `anon` recibe `42501` |
| 24 | Módulo 7 | Asistencia QR: el INSERT del alumno **ejercido de verdad** con un `authenticated` real (código vigente, caducado, no matriculado, en cola, sesión cerrada, doble marca), el UPDATE del docente que cierra la sesión, y los cinco veredictos del resolutor de código de D21 |

> **La sección 24 es la que encontró dos fallos que llevaban desde el 2026-09-26.**
> Hasta que se ejerció el camino **feliz** del INSERT del alumno, nadie había
> ejecutado esa política: las 32 pruebas de M7 del backend usan repositorios
> falsos, y las aserciones negativas de este mismo arnés daban verde **por el
> motivo equivocado** —el `42501` de un permiso, no el de la política—, así que
> no medían nada. Un verde que no mide es peor que un rojo, porque no se busca.
> Ver `lecciones.md` y la migración `202609270001`.

> **Nota sobre la numeración de las secciones.** Los títulos del script tienen
> tres secciones numeradas **14** (`14. D12 cerrada…`, `14. Módulo 3…` y
> `14.8 El trigger funciona…`). No se renumeraron a propósito: hay referencias a
> «§14» y «§22» en `ESTADO_DEL_SISTEMA.md` que apuntan a esos números, y
> reordenarlos rompería esas citas para arreglar algo cosmético. Queda anotado.

## Límites

PGlite es Postgres de verdad, pero **no es Supabase**: no prueba PostgREST, ni
GoTrue, ni el comportamiento de `auth.jwt()`. La verificación final contra el
proyecto real sigue siendo necesaria. Esto atrapa lo caro antes de llegar ahí.

**Lo que este arnés no puede ver** y conviene no confundir con cobertura: que la
RLS decida bien *en la nube* (eso lo hace `verificar-esquema.mjs`), ni que las
pantallas de Flutter hagan lo que dicen (eso es `test/`, y para M7 está en
`test/asistencia_paneles_test.dart`).
