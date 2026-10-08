# AGENT START HERE — INCES LMS

## Misión

Tomar el estado real del repositorio y continuar autónomamente hasta cerrar todo lo técnicamente posible.

No depender del historial conversacional.

## Lectura obligatoria

Leer en este orden:

1. ESTADO_DEL_SISTEMA.md
2. PLAN_MAESTRO.md
3. PLAN_CIERRE_100_FUNCIONAL_2026.md
4. docs/AI_AGENT_OPERATING_PROTOCOL.md
5. docs/AI_AGENT_AUTONOMY_AND_ENVIRONMENT_RECOVERY.md
6. AUTONOMOUS_AGENT_MASTER_PROMPT.md
7. MEMORY.md, si existe
8. auditorías/documentos de la fase activa

## Verificación inicial

Ejecutar y medir:

- git status --short
- rama actual
- últimos commits
- procesos y puertos relevantes
- estado del backend
- estado del frontend/build
- migraciones aplicadas vs escritas
- pruebas de la fase activa

No confiar en números históricos sin volver a medirlos.

## Regla de autonomía

No preguntar qué hacer cuando el siguiente paso sea deducible.

Cerrar un hito no termina la sesión.

Después de cada cierre:

ESTADO → SIGUIENTE DISCRIMINADOR → IMPLEMENTAR → PROBAR → REGRESAR → DOCUMENTAR → REPETIR.

## Si una herramienta falla

No declarar imposibilidad.

Usar esta escalera:

1. cambiar herramienta;
2. reducir el caso;
3. bajar de capa;
4. inspeccionar artefactos propios;
5. utilizar ingeniería inversa del sistema propio;
6. crear un adaptador reversible;
7. probar equivalencia;
8. documentar.

## Ingeniería inversa

Permitida para código, artefactos, bundles propios, sourcemaps, OpenAPI, migraciones, contratos, trazas, APIs legítimamente accesibles y artefactos CI.

No utilizarla para evadir autenticación, MFA, CAPTCHA, RLS, autorización, secretos o controles de terceros.

## Únicos bloqueadores humanos

H1 — credencial externa que sólo el propietario puede proporcionar.

H2 — autorización para una acción irreversible.

H3 — decisión de producto genuinamente ambigua y no deducible.

H4 — infraestructura externa que exige login interactivo, MFA, CAPTCHA o aprobación física.

Un H1–H4 no detiene el resto del proyecto.

## Evidencia

Nunca declarar PASS por:
- pantalla abierta;
- HTTP 200 aislado;
- mock;
- retry;
- prueba sin precondición;
- no-op.

La prueba debe demostrar la operación real que afirma medir.

## Estado conocido al 2026-10-08

- P-02: CERRADO.
- P-01: ABIERTO hasta despliegue real + HEAD.
- Performance: EN CURSO.
- Responsive: todavía no iniciar hasta cumplir el gate de Performance.
- F1 correo: DEFERIDA por Resend HTTP 401.
- F2 planilla oficial: CERRADA.
- F4 R2: 52/52 PASS en humo real.
- Aula Virtual E2E específico: 7/7 PASS.
- Backend verify: 658/658 PASS.
- Flutter focalizado reciente: 85/85 PASS.
- Producción Pages: HTTP 200.
- API Render: HTTP 200 después de cold start.
- CORS Pages → API: verificado.

Estos datos son una fotografía, no una fuente superior al código o a una medición nueva.

## Siguiente trabajo esperado

Mientras una medición nueva no cambie la prioridad:

1. Performance de cargas reales por rol.
2. Mis Aulas.
3. Aula Virtual.
4. Inscripciones.
5. cPanel.
6. cerrar P-01 con despliegue real y HEAD.
7. Responsive.
8. UI/UX.
9. accesibilidad.
10. motion/3D si el presupuesto de rendimiento lo permite.
11. Android.
12. regresión total.
13. producción.
14. documentación final.

## Handoff

Al detenerse por límite real del entorno, escribir:

- fecha;
- fase;
- hito;
- estado;
- evidencia;
- archivos;
- comandos;
- resultados;
- regresiones;
- H1/H2/H3/H4;
- deudas;
- siguiente discriminador;
- comando exacto;
- criterio de cierre.

Nunca dejar únicamente "continuar".

## Documentos añadidos el 2026-10-08

Para ejecución eficiente con agentes de larga duración:
- docs/AI_AGENT_TOKEN_EFFICIENT_AUTONOMY.md
- docs/PROJECT_PHASE_GATES.md
- PROMPT_ANTIGRAVITY_AUTONOMOUS_CLOSURE.md

Uso recomendado en Antigravity: cargar o pegar PROMPT_ANTIGRAVITY_AUTONOMOUS_CLOSURE.md como prompt operativo y dejar que el agente reconstruya el estado desde el repositorio.

El prompt está diseñado para continuar automáticamente, persistir checkpoints y minimizar lecturas repetidas. No intenta evadir cuotas o controles del proveedor.
