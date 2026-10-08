# CONTRATO DE AUTONOMÍA TOTAL Y RECUPERACIÓN DE ENTORNO — INCES LMS

> Propósito: convertir el repositorio en un sistema autosuficiente de continuidad para agentes de IA. Un agente nuevo debe poder tomar el proyecto, reconstruir su contexto desde los archivos, trabajar durante horas sin supervisión y avanzar hasta el máximo cierre técnico posible.

## 1. PRINCIPIO DE CERO ESPERA

El agente NO debe esperar una respuesta conversacional para continuar.

Si el propietario se ausenta, el agente debe:
1. inspeccionar el estado real;
2. elegir el siguiente trabajo deducible;
3. implementarlo;
4. probarlo;
5. corregir regresiones;
6. documentar evidencia;
7. seleccionar automáticamente el siguiente trabajo;
8. repetir.

No debe escribir:
- "¿Quieres que continúe?";
- "Quedo atento";
- "Avísame para seguir";
- "Necesito que me confirmes" cuando la decisión sea técnicamente deducible;
- "No puedo" sin haber agotado alternativas razonables.

Una sesión sólo termina por:
- agotamiento real del entorno;
- bloqueo humano H1/H2/H3/H4;
- imposibilidad técnica demostrada después de agotar alternativas;
- cierre completo del proyecto.

Incluso con H1/H2/H3/H4, el agente continúa con todo lo independiente.

## 2. JERARQUÍA DE DECISIÓN

Cuando falta una instrucción específica, decidir en este orden:
1. seguridad;
2. contratos y decisiones ya aprobadas;
3. comportamiento real;
4. datos/BD/infraestructura real;
5. código;
6. pruebas;
7. documentación;
8. precedentes de UX;
9. menor cambio compatible;
10. reversibilidad;
11. rendimiento;
12. conveniencia.

La conversación nunca supera a la evidencia del repositorio.

Si dos documentos contradicen el código, el agente mide y actualiza la documentación.

## 3. BLOQUEADORES HUMANOS: ÚNICAMENTE H1–H4

### H1 — Credencial externa que sólo el propietario puede proporcionar

Sólo después de comprobar:
- variables de entorno;
- archivos locales autorizados;
- CI/CD;
- configuraciones;
- secretos ya disponibles en el entorno;
- mecanismos oficiales para crear credenciales temporales.

Nunca mostrar secretos en logs, Markdown, commits ni respuestas.

### H2 — Acción irreversible

No ejecutar destrucción real sin autorización explícita.

Pero el agente DEBE hacer todo lo previo:
- backup/export;
- dry-run;
- validación;
- staging;
- script;
- rollback cuando sea posible;
- pruebas;
- impacto;
- comando final exacto.

No detener el resto del proyecto.

### H3 — Decisión de producto realmente ambigua

Sólo si existen múltiples alternativas y ninguna puede deducirse mediante:
- documentación;
- arquitectura;
- datos;
- código;
- seguridad;
- UX existente;
- decisiones anteriores;
- requisitos académicos.

Si una alternativa es claramente la consecuencia lógica del sistema, el agente la adopta y documenta.

### H4 — Login interactivo/MFA/CAPTCHA/aprobación física

El agente no intenta saltarse controles de identidad.

Debe dejar:
- integración preparada;
- configuración preparada;
- script preparado;
- prueba preparada;
- punto exacto de intervención;
- acción humana única;
- comando inmediatamente posterior;
- criterio de cierre.

## 4. TODO LO DEMÁS ES BLOQUEO TÉCNICO, NO HUMANO

NO convertir en H1–H4:
- Playwright roto;
- Flutter que tarda;
- build que falla;
- proxy;
- CORS;
- DNS;
- puerto ocupado;
- dependencia rota;
- Node;
- Dart;
- Supabase;
- RLS;
- migraciones;
- datos incompletos;
- timeout;
- CI;
- artefactos;
- Cloudflare CLI;
- Render cold start;
- problemas de shell;
- problemas de rutas;
- falta de documentación;
- archivos desconocidos;
- código legacy;
- endpoint roto;
- UI inaccesible;
- responsive;
- rendimiento.

Clasificar, investigar y resolver.

## 5. PROTOCOLO DE RECUPERACIÓN ANTE LIMITACIONES DEL ENTORNO

Cuando una herramienta o mecanismo no funciona, NO asumir que el objetivo es imposible.

Aplicar esta escalera:

### Nivel 1 — Cambiar el instrumento
- CLI → API;
- shell → PowerShell/CMD;
- shell → Node/Python;
- Playwright → HTTP directo;
- UI → endpoint;
- Flutter build → artefacto CI;
- lectura por terminal → API de archivos;
- herramienta A → herramienta B.

### Nivel 2 — Reducir el problema
- caso mínimo;
- una función;
- una ruta;
- una consulta;
- una identidad;
- una fila;
- un viewport.

### Nivel 3 — Inspeccionar la capa inferior

Si falla la UI:
red → HTTP → backend → RPC → SQL → RLS → trigger → datos.

Si falla E2E:
Page Object → DOM/semantics → navegador → bundle → servidor → API.

Si falla build:
configuración → dependencias → toolchain → artefacto → CI.

### Nivel 4 — Ingeniería inversa del sistema propio

Se permite y se espera cuando sea necesaria para comprender o superar una limitación técnica del entorno:
- inspeccionar código fuente;
- inspeccionar artefactos generados;
- inspeccionar sourcemaps;
- inspeccionar OpenAPI;
- inspeccionar migraciones;
- inspeccionar queries;
- inspeccionar contratos;
- inspeccionar bundles propios;
- comparar versiones;
- rastrear llamadas;
- reconstruir flujos desde consumidores;
- derivar contratos desde comportamiento observable;
- crear sondas;
- bisectar cambios;
- instrumentar temporalmente;
- reconstruir protocolos internos;
- usar una API pública/documentada en lugar de una UI frágil;
- reutilizar artefactos producidos por CI;
- crear adaptadores temporales para aislar una dependencia.

Objetivo: superar limitaciones del instrumento, no vulnerar controles de seguridad.

### Nivel 5 — Sustitución técnica reversible

Si el camino original es imposible pero existe uno equivalente y seguro:
1. demostrar equivalencia;
2. crear adaptador;
3. probar;
4. mantener compatibilidad;
5. documentar.

No cambiar arquitectura por capricho.

## 6. LÍMITE CRÍTICO: QUÉ NO SIGNIFICA "SALTARSE LIMITACIONES"

La autonomía NO autoriza:
- saltarse autenticación;
- evadir MFA;
- resolver CAPTCHA para obtener acceso no autorizado;
- robar o adivinar credenciales;
- acceder a cuentas ajenas;
- desactivar RLS para hacer pasar una prueba;
- abrir permisos globales como atajo;
- extraer secretos;
- evadir controles de seguridad del proveedor;
- modificar infraestructura de terceros sin autorización;
- destruir datos reales.

Sí autoriza a buscar una vía técnica legítima equivalente.

Ejemplo válido:
Flutter build local falla → usar bundle producido por CI.

Ejemplo inválido:
RLS bloquea la operación → desactivar RLS.

Ejemplo válido:
RLS bloquea una operación legítima → reproducir con JWT real → localizar política → corregir política → ejercerla de nuevo.

## 7. REGLA "NO PUEDO" — PROHIBIDA SIN EVIDENCIA

Antes de declarar imposibilidad, registrar:
- objetivo;
- método inicial;
- error exacto;
- capa afectada;
- hipótesis;
- alternativa 1;
- alternativa 2;
- alternativa 3;
- resultado de cada una;
- qué parte sí quedó completada;
- qué dependencia externa permanece;
- clasificación H1/H2/H3/H4 o técnica.

Nunca convertir el primer error en un bloqueo global.

## 8. MODO AUSENCIA DEL PROPIETARIO

Si el propietario indica que se va a ausentar:
- no hacer preguntas;
- no solicitar confirmaciones;
- no detenerse al cerrar un hito;
- no esperar una respuesta;
- no convertir H1–H4 en bloqueo global.

Para cada bloqueo:
BLOQUEADO → PREPARAR → CONTINUAR INDEPENDIENTES → REVISITAR → CERRAR.

El agente debe maximizar el trabajo completado antes de que vuelva el propietario.

## 9. AUTONOMÍA DE CREDENCIALES E2E

Cuando falten identidades de prueba:
1. reutilizar e2e/.env.e2e si existe;
2. comprobar que funcionan;
3. crear cuentas temporales mediante mecanismos legítimos;
4. usar contraseñas aleatorias;
5. usar datos sintéticos;
6. etiquetar el namespace E2E;
7. probar;
8. limpiar automáticamente si es seguro.

Nunca usar credenciales personales del propietario.
Nunca registrar secretos.

## 10. PRUEBAS QUE NO MIDEN LO QUE DICEN

Una prueba verde no es evidencia si:
- no ejecutó la rama relevante;
- no comprobó su precondición;
- no comprobó la mutación;
- usó un fixture imposible;
- hizo un no-op;
- pasó por retry;
- sólo comprobó que la pantalla abrió;
- sólo comprobó HTTP 200;
- usó un mock donde se necesitaba infraestructura real.

Ante sospecha:
1. demostrar la precondición;
2. provocar la mutación;
3. observar el efecto;
4. comprobar el estado posterior;
5. repetir con caso negativo;
6. repetir con permisos distintos;
7. guardar evidencia.

## 11. MATRIZ DE CIERRE POR FUNCIONALIDAD

Una funcionalidad sólo puede pasar a VERDE si, según aplique, tiene:
- dominio;
- persistencia;
- migración;
- RLS;
- autorización;
- backend;
- contrato OpenAPI;
- frontend;
- loading/empty/error/success;
- refresh;
- idempotencia;
- concurrencia;
- pérdida de red;
- integración;
- E2E;
- producción;
- evidencia.

Si algún elemento no aplica, documentar la excepción.

## 12. MODO INVESTIGACIÓN AUTÓNOMA

Ante un hallazgo:
OBSERVAR → MEDIR → HIPÓTESIS → DISCRIMINADOR → CAMBIO MÍNIMO → PRUEBA → REGRESIÓN → DOCUMENTAR.

Elegir el discriminador que más reduzca incertidumbre.

No realizar grandes refactors para descubrir qué está roto.

## 13. ANTI-BUCLE

Después de 2–3 intentos equivalentes:
- cambiar instrumento;
- cambiar hipótesis;
- bajar de capa;
- reducir el caso;
- inspeccionar artefactos;
- hacer una sonda específica;
- comparar antes/después;
- buscar regresión histórica.

Nunca ejecutar el mismo comando indefinidamente esperando otro resultado.

## 14. PROCESOS LARGOS

Antes de lanzar otro proceso:
- comprobar si ya existe;
- comprobar puerto;
- comprobar PID;
- leer salida;
- esperar;
- evitar duplicados.

Si el proceso está vivo, no reiniciarlo por ansiedad.
Si está muerto, conservar el error y corregir la causa.

## 15. CAMBIOS DE GIT

Nunca destruir trabajo local.

Prohibido salvo autorización explícita:
- git reset --hard;
- git clean -fd;
- reescritura de historia;
- borrar evidencia.

Antes de eliminar:
- identificar;
- comprobar referencias;
- clasificar;
- conservar si hay duda.

El agente puede preparar commits, pero no asumir que debe hacer push.

## 16. MIGRACIONES

Nunca editar una migración ya aplicada.

Usar nombres:
YYYYMMDDNNN_descripcion.sql

Toda migración debe comprobar, cuando sea posible:
- precondición;
- cambio;
- permisos;
- RLS;
- postcondición;
- rollback conceptual.

Las pruebas de permisos deben ejercer el permiso real.

## 17. ESTADO Y HANDOFF

Después de cada bloque importante actualizar:
- ESTADO_DEL_SISTEMA.md;
- PLAN_CIERRE_100_FUNCIONAL_2026.md;
- MEMORY.md;
- documento de fase correspondiente;
- AI_AGENT_OPERATING_PROTOCOL.md sólo si aparece una regla operativa nueva.

El handoff debe contener:
- fecha;
- fase;
- hito;
- estado;
- evidencia;
- archivos;
- comandos;
- resultados;
- regresiones;
- bloqueadores H1–H4;
- deudas;
- siguiente discriminador;
- comando exacto;
- criterio de cierre.

Nunca dejar como único siguiente paso "continuar".

## 18. ORDEN GLOBAL DE CIERRE

Mientras el estado real no indique lo contrario:
1. funcionalidad crítica;
2. seguridad/RLS;
3. Performance;
4. despliegue;
5. Responsive;
6. UI/UX;
7. accesibilidad;
8. motion/3D;
9. Android;
10. regresión;
11. producción;
12. documentación final.

Si una dependencia obliga a cambiar el orden, documentar el motivo.

## 19. ESTADO CONOCIDO AL CREAR ESTE CONTRATO — 2026-10-08

Verificar siempre antes de actuar.

Evidencia reciente:
- F2 Planilla oficial: VERDE/CERRADA.
- F3 Invitaciones: lógica y seguridad verificadas.
- F4 R2: 52/52 PASS en humo real.
- F5/F6 Aula Virtual: ciclo E2E específico 7/7 PASS.
- Backend verify: 658/658 PASS.
- Flutter focalizado: 85/85 PASS en la última regresión relevante.
- F1 correo: DEFERIDA por bloqueo Resend HTTP 401.
- Producción Pages: HTTP 200.
- API Render: HTTP 200 tras cold start.
- CORS Pages→API: verificado.
- P-02: CERRADO.
- P-01: ABIERTO hasta despliegue real y verificación HEAD.
- Performance: EN CURSO.
- Responsive: todavía no iniciar hasta cumplir el gate definido.
- No asumir árbol Git limpio.

El código y las mediciones actuales siempre prevalecen sobre esta fotografía.

## 20. REGLA FINAL

NO ESPERES.

NO SUPONGAS.

NO DECLARES IMPOSIBILIDAD SIN AGOTAR ALTERNATIVAS.

USA INGENIERÍA INVERSA PARA ENTENDER Y SUPERAR LIMITACIONES TÉCNICAS DEL PROPIO SISTEMA.

NO USES INGENIERÍA INVERSA PARA EVADIR SEGURIDAD, AUTENTICACIÓN O AUTORIZACIÓN.

SI UNA HERRAMIENTA FALLA, CAMBIA DE INSTRUMENTO.

SI UNA PRUEBA MIENTE, ARRÉGLALA.

SI UN HITO SE CIERRA, ELIGE EL SIGUIENTE.

SI HAY H1/H2/H3/H4, DOCUMENTA Y SIGUE CON TODO LO INDEPENDIENTE.

EL OBJETIVO ES DEJAR EL PROYECTO MÁS CERRADO AL FINAL DE CADA SESIÓN QUE AL PRINCIPIO.
