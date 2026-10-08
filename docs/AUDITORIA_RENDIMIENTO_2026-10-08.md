# Auditoría de rendimiento — INCES LMS

> Estado vivo de la fase Performance. Registra mediciones y decisiones, no intenciones.

**Fecha de corte:** 2026-10-08 00:56–01:00 (-04:00)
**Fase:** Performance — EN CURSO
**Regla:** medir → cambio mínimo → volver a medir → regresión.

## 1. Baseline funcional

- Aula Virtual E2E real: 7/7 PASS.
- Batería Flutter focalizada posterior a entregaId: 84/84 PASS, 29.55 s.
- Backend npm run verify: 658/658 PASS.
- Producción Pages: HTTP 200.
- API Render: HTTP 200 después de cold start; repetición inmediata ~1.32 s según plan de cierre.
- CORS Pages → API: 204 y origen exacto.
- Build release local: build/web-final, 39 archivos, ~41.43 MiB en disco.

## 2. Composición real del bundle

| Extensión | Archivos | Tamaño |
|---|---:|---:|
| .wasm | 6 | 27.50 MiB |
| .symbols | 6 | 8.18 MiB |
| .js | 10 | 4.01 MiB |
| otros | 17 | ~1.74 MiB |
| TOTAL | 39 | ~41.43 MiB |

Artefactos principales: main.dart.js 3.57 MiB; canvaskit.wasm 6.947 MiB; skwasm.wasm 3.427 MiB; chromium/canvaskit.wasm 5.177 MiB.

**Conclusión:** el mayor coste del bundle está en CanvasKit/WASM. No se debe atacar eliminando funcionalidad ni cambiando renderer sin A/B.

## 3. Producción: compresión y caché

HEAD real contra producción confirmó Brotli para main.dart.js, CanvasKit JS/WASM y flutter_bootstrap.js.

Hallazgo P-01: producción estaba respondiendo con:
public, max-age=0, must-revalidate

Eso obliga al navegador a revalidar los estáticos en cada visita.

### Cambio preparado

Se añadió web/_headers con:
- HTML, raíz y flutter_bootstrap.js: 5 min + revalidación.
- main.dart.js: 1 h + revalidación.
- flutter.js, CanvasKit, assets, iconos y favicon: 7 días.

No se marca P-01 cerrado hasta reconstruir, desplegar y verificar HEAD real.

## 4. Consultas Flutter

### Verde / razonable

- AulaVirtualDashboardScreen consume un gateway único.
- PanelMisAulas hace una lectura de /api/v1/mi-horario al montar; actualizar es explícito.
- Los tres dashboards cargan system_modules una vez mediante CargaDeModulos; no se detectó polling automático.
- cPanel de módulos usa Future.wait para módulos + auditoría y limita auditoría a 50.
- Auditoría de accesos tiene paginación/límite.
- Perfil propio usa columnas explícitas y maybeSingle.

### Amarillo / candidato P-02

supabase_service.dart mantiene lecturas amplias:
- porCedula(): select amplio, una ficha.
- todos(): devuelve todos los aspirantes sin límite.
- porId(): select amplio, una ficha.
- miFicha(): select amplio con relación programs(name).
- crear()/actualizar(): select amplio para devolver fila.
- modulos()/settings(): select completo, pero catálogos pequeños.

**No cambiar AspiranteModel a columnas parciales a ciegas.** Primero medir payload y revisar consumidores. todos() es prioritario si alimenta una lista administrativa.

## 5. Siguiente discriminador P-02

1. Identificar consumidores de obtenerTodos().
2. Medir filas y payload real.
3. Si es lista administrativa, paginar server-side y pedir columnas mínimas.
4. Mantener contratos de porCedula/porId/miFicha hasta tener lista segura de campos.
5. Ejecutar batería Flutter + backend/E2E relacionada.

## 6. Renderer

No cambiar renderer todavía. La evidencia demuestra peso CanvasKit/WASM y arranque funcional; no demuestra que otro renderer sea mejor para este proyecto.

Una futura A/B debe comparar:
- tiempo hasta flutter-view;
- primer contenido útil;
- errores de consola;
- C1 Aula Virtual;
- interacción semántica de pestañas;
- tamaño comprimido.

## 7. No tocar todavía

- F1 Resend/password recovery: DEFERIDA.
- Responsive: después de Performance.
- UI/UX: después de Responsive.
- 3D/animaciones: después de UI/UX y sólo con presupuesto.
- Android: al final.
- No borrar tareas E2E acumuladas con SQL destructivo.

## 8. Criterio de salida

Performance sólo se cierra con:
1. baseline antes/después;
2. caché de producción verificada;
3. consultas/payloads calientes auditados;
4. cargas iniciales de roles principales medidas;
5. al menos una mejora cuantificable sin regresión;
6. regresión funcional verde después del último cambio;
7. decisión documentada sobre renderer.

**Última acción:** auditoría estática + preparación de web/_headers. P-01 sigue abierto.

### P-01.1 Preparación del artefacto Pages

Flutter build web no copia automáticamente web/_headers al output: build/web-final-perf quedó con 21 archivos y HEADERS_PRESENT=NO.

Para no depender de memoria manual se creó devops/preparar-cloudflare-pages.mjs. Uso:

node devops/preparar-cloudflare-pages.mjs build/web

La prueba sobre build/web-final-perf copió _headers correctamente. El comando de despliegue de Cloudflare Pages deberá ejecutar el build y después este preparador, o equivalente.

### P-00.1 Payload comprimido observado en producción

Tres mediciones por recurso con curl + Accept-Encoding: br:

| Recurso | HTTP | Tamaño transferido observado | Tiempo observado |
|---|---:|---:|---:|
| / | 200 | 728 B | 0.230–0.308 s |
| flutter_bootstrap.js | 200 | 5,178 B | 0.263–0.347 s |
| main.dart.js | 200 | 1,075,185 B | 0.688–1.067 s |
| canvaskit/canvaskit.wasm | 200 | ~2.863–2.868 MB | 0.865–1.059 s |

Estas cifras son una medición desde la máquina de trabajo hacia Cloudflare; no equivalen a una métrica de usuario final ni a TTFB puro. Sirven como baseline reproducible para comparar después del cambio de caché.


### Verificación post-cambio

- Primer intento de flutter test falló antes de ejecutar pruebas por una variable de entorno ausente: PROGRAMFILES(X86). No fue fallo de código.
- Segundo intento, definiendo PROGRAMFILES(X86) sólo para el proceso, terminó **84/84 PASS**, exit 0, **27.75 s**.
- El build release con el cambio de headers terminó correctamente: flutter build web --release --dart-define-from-file=.env.json --output build/web-final-perf, **116.2 s**, exit 0.
- Wasm dry-run del build: PASS; sólo warning informativo que recomienda probar --wasm. No se cambia renderer en esta fase.
## P-02 — Consultas calientes y payloads — 2026-10-08

### Evidencia real Supabase

| Consulta | Filas | Bytes | Tiempo medido |
|---|---:|---:|---:|
| aspirantes select=* admin | 27 | 26,859 | 548.10 ms |
| aspirantes proyección mínima | 27 | 5,529 | 221.28 ms |
| profiles mínima | 63 | 9,008 | 180.15 ms |
| programs activos | 6 | 478 | 210.48 ms |
| system_modules | 11 | 3,627 | 430.99 ms |
| system_settings admin | 11 | 2,950 | 215.98 ms |
| audit limit 50 | 50 | 43,292 | 245.07 ms |

La consulta AspiranteGateway.todos() no tiene consumidores en lib/; por tanto NO se convirtió en una refactorización innecesaria.

### Ruta del aprendiz

Con sesión E2E real, aspirantes del usuario devolvió 1 fila. La medición de miFicha con relación devolvió 1,348 B.

Después de la corrección a proyección explícita: 1,348 B.

La comparación inmediata de tiempos fue variable (STAR 572.13 ms vs explícita 249.19 ms), por lo que NO se atribuye esa diferencia al cambio. La mejora es estructural: una columna futura en aspirantes no se añadirá silenciosamente al payload de cada apertura del dashboard.

### Cambio aplicado

SupabaseService.miFicha() ahora proyecta exactamente los campos consumidos por AspiranteModel, incluida datos_planilla, y conserva programs(name).

### Regresión

Suite focalizada después del cambio:

**85/85 PASS — 76.25 s — exit 0.**

Incluye onboarding, libro de calificaciones, Aula Virtual, perfil y dashboards relacionados.

### Decisión P-02

**VERIFICADO LOCAL / CERRADO como intervención estructural de payload.**

No se afirma una reducción de bytes en el dataset actual porque no la hubo: los 1,348 B son equivalentes. El beneficio es control de crecimiento del contrato.

### Próximo discriminador de Performance

Auditar las cargas reales de:
1. dashboard por rol;
2. Mis Aulas;
3. Aula Virtual;
4. Inscripciones/catálogo;
5. cPanel administrativo.
Buscar requests duplicados, secuencialidad evitable, payloads grandes y rutas backend que devuelvan más datos de los necesarios.


---

## CONTRATO AI v2 — IMPACTO SOBRE PERFORMANCE

La auditoría de rendimiento queda integrada en el protocolo de ejecución autónoma.

El agente futuro debe continuar desde el siguiente discriminador real y no reiniciar auditorías ya cerradas:

**Dashboard por rol → Mis Aulas → Aula Virtual → Inscripciones/catálogo → cPanel.**

Para cada ruta debe obtener baseline real, localizar requests/consultas/payloads innecesarios, aplicar cambios pequeños, medir después y ejecutar regresión.

P-02 permanece cerrado como intervención estructural de payload. P-01 permanece abierto hasta despliegue real y verificación de headers/cache en producción.

Responsive no debe comenzar hasta que Performance satisfaga su criterio de salida documentado.

