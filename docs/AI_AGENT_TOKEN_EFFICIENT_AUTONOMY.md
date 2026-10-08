# AUTONOMÍA EFICIENTE EN TOKENS — INCES LMS

## Objetivo
Maximizar trabajo útil por unidad de contexto/tokens sin intentar eludir cuotas, límites de uso o mecanismos de control del proveedor.

## Principio de estado persistente
El agente NO debe reconstruir toda la historia en cada ciclo. El repositorio es la memoria.

Leer sólo:
1. AGENT_START_HERE.md;
2. estado vigente;
3. fase activa;
4. archivo objetivo;
5. evidencia necesaria.

No releer documentos completos si una sección concreta basta.

## Ciclo económico
OBJETIVO → EVIDENCIA MÍNIMA → CAMBIO PEQUEÑO → PRUEBA ESPECÍFICA → REGRESIÓN → CHECKPOINT

Evitar exploraciones masivas sin hipótesis.

## Presupuesto de contexto
Antes de abrir archivos:
- buscar símbolos;
- buscar referencias;
- buscar consumidores;
- buscar tests;
- leer sólo rangos relevantes;
- ampliar contexto únicamente si la evidencia lo exige.

Preferir search/find → read rango → patch → test sobre leer el proyecto completo.

## Checkpoints
Después de cada hito, persistir:
- estado;
- evidencia;
- siguiente discriminador;
- archivos tocados;
- comandos;
- resultado.

Así una nueva sesión puede continuar sin repetir investigación.

## Anti-repetición
No repetir una búsqueda ya resuelta, una hipótesis refutada, una prueba cuya evidencia no cambió o una lectura completa innecesaria.

Mantener una tabla de hipótesis:
| Hipótesis | Estado | Evidencia |
|---|---|---|
| H | VIVA/REFUTADA/CONFIRMADA | referencia |

## Compresión semántica
Preferir tablas, listas, hashes/IDs de commits, comandos reproducibles, métricas y referencias a archivos. Evitar narración duplicada.

## Trabajo por lotes
Agrupar búsquedas, lecturas pequeñas y verificaciones independientes cuando el instrumento lo permita. No agrupar cambios que puedan interferirse.

## Fallos
Registrar una vez: comando, error, causa y próxima acción. No copiar el mismo stack trace repetidamente.

## Límite de intentos
Tras 2–3 intentos equivalentes, cambiar de hipótesis, instrumento o capa.

## Regla
El objetivo no es hacer menos trabajo. Es gastar contexto en decisiones, cambios y evidencia, no en repetir información ya persistida.
