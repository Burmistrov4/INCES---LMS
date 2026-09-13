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

Salida esperada: `TODO VERDE — 40 aserciones pasadas, 0 fallidas`.

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

| Bloque | Comprueba |
| --- | --- |
| Semilla | 9 módulos M0–M8, M9 descartado, estado inicial honesto |
| Cortacircuitos | `m0_cpanel` no se puede apagar ni borrar |
| Auditoría | cada cambio deja rastro con valor anterior y nuevo |
| Idempotencia | reaplicar la semilla no revive ni duplica nada |
| Onboarding | el trigger crea perfil y ficha atómicamente |
| RLS no-admin | lee módulos, no los edita, no ve la auditoría ni settings privados |
| RLS admin | edita módulos, lee todo |
| RLS anónimo | sólo parámetros públicos; sin acceso al catálogo de módulos |
| Restricciones | roles, formato de clave y tipo de parámetro validados |

## Límites

PGlite es Postgres de verdad, pero **no es Supabase**: no prueba PostgREST, ni
GoTrue, ni el comportamiento de `auth.jwt()`. La verificación final contra el
proyecto real sigue siendo necesaria. Esto atrapa lo caro antes de llegar ahí.
