# Sprint 2 — Módulo 6 «Aula Virtual»: cierre

**Fecha:** 2026-09-22 · **Estado:** verde · **`m6_aula_virtual` ENCENDIDO**

---

## TL;DR

El bucle docente↔alumno del Aula Virtual quedó **completo y demostrable**. Antes el
alumno veía contenido pero el docente no tenía ninguna palanca: no podía crear un
anuncio, ni una tarea, ni calificar. Ahora puede, y el módulo está encendido.

```
el docente publica → se siembran las entregas de cada alumno
                   → el alumno entrega
                   → el docente califica y devuelve
                   → el alumno por fin ve su nota
```

---

## Verificación (medida, no estimada)

| Suite | Resultado |
| --- | --- |
| Backend `npm run verify` | **540 / 540** en 21 archivos |
| Flutter `flutter test` | **456 / 456** (+10 en este sprint) |
| PGlite `supabase/tests/validate.mjs` | **402 / 402** aserciones |
| `flutter analyze` | Sin avisos |
| `node supabase/tests/medir-conteos.mjs` | 20 migraciones · 60 rutas / 68 operaciones / 108 esquemas |

Cero regresiones: cada fase se verificó antes de commitear.

---

## Las cinco fases

| # | Commit | Qué se hizo |
| --- | --- | --- |
| 1 | `25f9b8d` | Parche caliente: `202609220002` con `CREATE OR REPLACE m6_crear_tarea` (`p_puntos_maximos` por defecto `null`) |
| 2 | `7bbcc46` | `resolverPuertaDeContenido`: el aula se abre en **producción** |
| 3 | `495c1d2` | Centro de Mando del Docente: 3 paneles nuevos + 10 pruebas de widget |
| 4 | `e1fed9a` | `202609220003` enciende el módulo; 3 aserciones invertidas |
| 5 | `5f99015` | Auditoría de documentos vivos + script de medición |

### Por qué la Fase 1 no editó la migración 001

`202609220001` ya estaba **aplicada en producción** con el default equivocado
(`20`). Una migración aplicada no se edita: el libro mayor la detecta por
checksum. Se creó una nueva con `CREATE OR REPLACE`, que además **conserva el
`GRANT EXECUTE`**, así que no hay que re-conceder permisos.

### La regla sutil de la Fase 2

Un `?? BackendAulaGateway()` ingenuo habría roto las pruebas: `resolverPuertaDeContenido`
devuelve `null` cuando **sólo** se inyectó el listado (caso de las pruebas de
widget), para que la tarjeta no se vuelva pulsable y la prueba no salga a la red.
Sólo en producción, donde nadie inyecta nada, devuelve el servicio real.

---

## El Centro de Mando del Docente (Fase 3)

Tres pantallas nuevas, cada una con su prueba de widget (TDD estricto):

- **`crear_anuncio_panel.dart`** — publica en el tablón de la sección.
- **`crear_tarea_panel.dart`** — diferencia **TAREA** de **MATERIAL**: el campo de
  puntos sólo aparece para TAREA, y para MATERIAL se envía `null` (no un `0`, que
  rompería el `CHECK` de la base).
- **`libro_calificaciones_panel.dart`** — una fila por alumno con calificar y
  devolver; reusa el patrón de rejilla con doble scroll de `cuadrante_grid.dart`.

---

## Cinco trampas que mordieron (y que quedan documentadas)

1. **Un panel que se abre como ruta necesita su propio `Scaffold`.**
   `ContenidoSeccion` no trae `Material` → el `TextFormField` reventaba con
   *«No Material widget found»* **también en producción**.
2. **`ContenidoSeccion` no desplaza.** El botón quedaba fuera de pantalla y el
   `tap()` no acertaba, disfrazándose de «el gateway no recibió nada».
3. **`DropdownButtonFormField` no relee el valor desde fuera** → para un selector
   controlado, `DropdownButton`.
4. **`AppException.from` traduce el error**: `Exception('sin red')` se muestra
   como «Ocurrió un error inesperado». Buscar el texto crudo nunca funciona.
5. **`Result.when` no espera callbacks `async`** — destapó un bug real de carrera
   al encadenar crear + publicar.

---

## Encender se probó por mutación

No bastaba con que las pruebas pasaran. Se puso `habilitado = false` y la suite
PGlite dio **400 pasadas / 2 fallidas** — exactamente las dos aserciones nuevas.
Sostienen peso; no son decorado.

---

## ⚠️ Pendiente de una persona (no se puede hacer desde aquí)

**La nube va 4 migraciones por detrás del repositorio** (20 en el repo, 16
aplicadas). Hay que aplicarlas en orden:

1. `202609210002_mod5_habilitar_modulo.sql`
2. `202609220001_mod6_aula_virtual.sql`
3. `202609220002_mod6_fix_material_default.sql`
4. `202609220003_mod6_habilitar_modulo.sql`

Hasta entonces `verificar-esquema.mjs` y `backend/test-humo.mjs` (**23/25**)
darán rojo. **No es una regresión: es la comprobación funcionando.** No bajar las
aserciones. Ninguno de los dos es ejecutable en este entorno (exigen
`SUPABASE_ACCESS_TOKEN` y un backend desplegado).

**También:** las credenciales de Cloudflare que compartiste no deben vivir en el
repositorio — sólo en un `.env` ignorado por git — y conviene **revocar el token
anterior** si sigue activo.

---

## Archivos del sprint

**Nuevos:** `lib/screens/crear_anuncio_panel.dart` ·
`lib/screens/crear_tarea_panel.dart` ·
`lib/screens/libro_calificaciones_panel.dart` ·
`test/crear_anuncio_panel_test.dart` · `test/crear_tarea_panel_test.dart` ·
`test/libro_calificaciones_panel_test.dart` ·
`supabase/migrations/202609220002_mod6_fix_material_default.sql` ·
`supabase/migrations/202609220003_mod6_habilitar_modulo.sql` ·
`supabase/tests/medir-conteos.mjs`

**Modificados:** `lib/core/gateways/aula_gateway.dart` ·
`lib/services/aula_service.dart` · `lib/screens/aula_virtual_dashboard.dart` ·
`test/support/fake_aula_gateway.dart` · `supabase/tests/validate.mjs` ·
`supabase/verificar-esquema.mjs` · `backend/test-humo.mjs` ·
`ESTADO_DEL_SISTEMA.md` · `HANDOVER.md`
