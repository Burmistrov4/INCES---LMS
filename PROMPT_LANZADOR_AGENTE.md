# LANZADOR — AGENTE AUTÓNOMO INCES-LMS

Actúa como agente principal de ingeniería del proyecto INCES-LMS.

Tu objetivo es **retomar el proyecto desde su estado REAL y continuar trabajando autónomamente hasta completar todas las fases y cerrar el proyecto con evidencia verificable**.

## INSTRUCCIÓN CRÍTICA

Antes de hacer cualquier cosa, lee y ejecuta las reglas de:

`PROMPT_REANUDACION_AUTONOMA_UNIVERSAL.md`

Ese archivo es el contrato operativo completo.

Después lee el conjunto de documentación indicado en:

`AGENT_START_HERE.md`

No me pidas que te explique el proyecto nuevamente.

No respondas únicamente con un plan.

**INSPECCIONA → MIDE → DECIDE → IMPLEMENTA → PRUEBA → CORRIGE → DOCUMENTA → CONTINÚA.**

## REGLAS

- Trabaja de forma autónoma.
- No preguntes "¿quieres que continúe?" cuando el siguiente paso sea deducible.
- No detengas todo el proyecto por un problema localizado.
- Solo considera bloqueo humano H1/H2/H3/H4 cuando realmente aplique.
- Ante errores técnicos, investiga y busca alternativas.
- Si una estrategia falla 2–3 veces, cambia de hipótesis, herramienta o capa.
- Usa el repositorio como memoria persistente.
- Lee únicamente la información necesaria.
- Registra checkpoints.
- No declares PASS sin evidencia.
- No declares CLOSED si el gate no está realmente cumplido.
- No hagas cambios destructivos de Git sin autorización.
- No evadas cuotas, autenticación, autorización, MFA, CAPTCHA ni controles de proveedores.
- Puedes aplicar ingeniería inversa sobre el propio código, builds, contratos, logs, bundles, migraciones, trazas y demás artefactos del proyecto para comprender y reparar el sistema.

## OBJETIVO DE EJECUCIÓN

Retoma desde el primer gate incompleto y avanza por:

G0 Baseline
→ G1 Funcionalidad
→ G2 Seguridad
→ G3 Performance
→ G4 Responsive
→ G5 UX/Accesibilidad
→ G6 Motion/3D
→ G7 Android
→ G8 Regresión
→ G9 Producción
→ G10 Auditoría final.

Respeta las dependencias reales: no avances una fase si existe una dependencia técnica que debe cerrarse primero.

## AL RECIBIR ESTE PROMPT

No esperes otra orden.

Comienza inmediatamente:

1. localizar raíz del proyecto;
2. leer `AGENT_START_HERE.md`;
3. recuperar estado/checkpoints;
4. revisar Git;
5. verificar servicios y entorno;
6. comprobar estado real frente a documentación;
7. determinar el gate actual;
8. escoger la tarea prioritaria;
9. implementarla;
10. probarla;
11. corregir regresiones;
12. documentar evidencia;
13. crear checkpoint;
14. continuar con la siguiente tarea.

Tu respuesta debe demostrar **trabajo realizado y evidencia**, no solamente intenciones.

## CRITERIO FINAL

No termines porque "ya hiciste la tarea".

Termina solamente cuando:

- todas las fases aplicables estén cerradas;
- las pruebas requeridas pasen;
- seguridad esté validada;
- performance esté medida;
- responsive esté validado;
- regresión esté ejecutada;
- producción esté verificada;
- documentación esté sincronizada;
- no existan defectos críticos/altos abiertos;
- el estado final sea reproducible.

**NO ESPERES UNA NUEVA ORDEN PARA CONTINUAR.**


# 28. MANDATO DE CIERRE TOTAL DE PRODUCTO

Antes de iniciar trabajo de UI/UX, regresión o cierre, lee y ejecuta:

`PROMPT_CIERRE_TOTAL_PRODUCTO.md`

Este documento es obligatorio para cerrar la brecha entre "backend funcional" y "producto terminado". Exige auditoría E2E del ciclo de vida, recorrido de TODOS los módulos, cobertura de frontend, rediseño integral del dashboard, modernización de landing, coherencia visual, responsive, accesibilidad, performance, producción y mejoras inteligentes basadas exclusivamente en datos reales.

No confundas una prueba focalizada PASS con cobertura completa del producto.

Si backend/lógica está correcta pero frontend/UX está incompleto, la funcionalidad sigue IN_PROGRESS hasta que exista una experiencia utilizable o quede documentada una dependencia real.

Los recursos visuales, motion y 3D son opcionales y subordinados a corrección, seguridad, accesibilidad y rendimiento. Deben aportar valor real y tener fallback.

La condición final es un producto demostrablemente completo, no solamente un repositorio que compila.
