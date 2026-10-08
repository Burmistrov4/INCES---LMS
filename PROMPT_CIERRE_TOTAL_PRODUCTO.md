# MANDATO DE CIERRE TOTAL — INCES-LMS
## Producto funcional + ciclo de vida completo + UX/UI moderna + frontend terminado

Este mandato complementa PROMPT_REANUDACION_AUTONOMA_UNIVERSAL.md. No sustituye sus reglas de seguridad, autonomía, evidencia, checkpoints ni recuperación.

### MISIÓN

Lleva INCES-LMS desde el estado real actual hasta un estado de producto terminado y demostrable.

No basta con que backend, endpoints y pruebas focalizadas funcionen. El sistema debe resultar convincente para un usuario real y para una evaluación académica/técnica: coherente, completo, moderno, organizado, usable y verificablemente funcional de extremo a extremo.

La prioridad es:

1. CORRECCIÓN Y CICLO DE VIDA COMPLETO
2. SEGURIDAD
3. CONSISTENCIA FUNCIONAL
4. EVIDENCIA E2E
5. PERFORMANCE
6. RESPONSIVE
7. UX/UI Y ACCESIBILIDAD
8. ESTÉTICA, MOTION Y 3D SOLO CUANDO APORTEN VALOR

No sacrifiques funcionalidad, seguridad, accesibilidad ni rendimiento por estética.

---

## 1. AUDITORÍA REAL DEL CICLO DE VIDA

No asumas que porque existen 658 tests backend, 85 tests Flutter o pruebas de módulos concretos todo el sistema está probado.

Construye y ejecuta una MATRIZ E2E del ciclo de vida completo.

Como mínimo debe cubrir, según las funcionalidades realmente existentes:

APRENDIZ/ASPIRANTE
→ landing
→ registro
→ onboarding
→ autenticación
→ perfil/datos
→ inscripción
→ selección de programa/sección
→ cupos
→ cola de espera
→ confirmaciones
→ estado académico
→ aula virtual
→ clases/materiales
→ asistencia
→ evaluaciones
→ notas
→ prácticas/pasantías si corresponden
→ egreso
→ certificado/título
→ QR/verificación
→ cierre del ciclo.

PERSONAL/PROFESOR
→ autenticación
→ dashboard
→ gestión de aulas/secciones
→ clases
→ materiales
→ asistencia
→ evaluaciones
→ calificaciones
→ seguimiento de aprendices.

ADMINISTRADOR
→ autenticación
→ dashboard
→ módulos
→ parámetros
→ auditoría
→ auditoría de accesos
→ usuarios/roles
→ programas
→ inscripciones/cupos
→ campos de inscripción
→ secciones
→ lapsos
→ cuadrante/horarios
→ demás módulos existentes.

Para cada flujo registra:
- actor;
- precondición;
- acción;
- request real;
- respuesta;
- estado de UI;
- persistencia;
- siguiente estado;
- permisos;
- error esperado;
- evidencia;
- PASS/FAIL/BLOCKED.

Si falta una prueba, créala.

Si una funcionalidad existe en backend pero no tiene UI utilizable, considérala INCOMPLETA hasta resolverla o documentar claramente su alcance.

---

## 2. AUDITORÍA MÓDULO POR MÓDULO

Recorre TODOS los módulos reales del sistema.

No te limites al menú.

Para cada módulo verifica:

- navegación;
- permisos;
- carga inicial;
- loading;
- empty state;
- success state;
- error state;
- formularios;
- validaciones;
- tablas/listas;
- filtros;
- búsqueda;
- paginación si aplica;
- crear;
- editar;
- eliminar/desactivar si corresponde;
- confirmaciones;
- feedback;
- persistencia;
- auditoría;
- responsive;
- accesibilidad;
- coherencia visual;
- integración con backend;
- regresión.

Genera una matriz de cobertura persistente en documentación.

No marques un módulo CLOSED porque su endpoint funcione si la experiencia frontend está incompleta.

---

## 3. DASHBOARD — REHACERLO COMO PRODUCTO, NO COMO PLACEHOLDER

El dashboard actual no debe quedarse como una colección de tarjetas que simplemente muestran números.

Audítalo y rediseñalo.

Debe comunicar rápidamente:

- dónde estoy;
- qué está ocurriendo;
- qué requiere atención;
- qué acciones son prioritarias;
- métricas importantes;
- actividad reciente;
- alertas;
- estado académico/operativo según rol;
- accesos rápidos;
- tendencias cuando tengan sentido.

Crear una arquitectura visual clara:

1. encabezado contextual;
2. resumen ejecutivo;
3. métricas realmente útiles;
4. acciones prioritarias;
5. actividad/recientes;
6. alertas o pendientes;
7. información contextual;
8. accesos rápidos.

Evita:
- números sin significado;
- tarjetas repetitivas;
- espacios vacíos;
- widgets decorativos sin función;
- gráficos que no ayuden a decidir;
- bloques visualmente desconectados.

El dashboard debe cambiar inteligentemente según rol:

ADMINISTRADOR:
operación, usuarios, matrículas, cupos, auditoría, incidencias, actividad.

PROFESOR:
sus secciones, clases próximas, asistencia pendiente, evaluaciones pendientes, últimas calificaciones.

APRENDIZ:
progreso académico, próximas clases, asistencia, evaluaciones, avisos, pendientes, progreso del programa.

Si algún dato no existe realmente, NO lo inventes. Usa estados vacíos útiles o crea la consulta/endpoint necesario.

---

## 4. HACER LA APP MÁS INTELIGENTE

"Inteligente" significa que reduce trabajo y anticipa necesidades, no que añada IA decorativa.

Implementa donde sea técnicamente justificable:

- recomendaciones contextuales;
- acciones rápidas;
- estados derivados;
- alertas de pendientes;
- detección de inconsistencias;
- avisos de cupos;
- próximos eventos;
- progreso;
- recordatorios;
- filtros persistentes;
- búsquedas útiles;
- navegación contextual;
- validación preventiva;
- mensajes de error accionables;
- sugerencias basadas en datos reales;
- resumen de actividad;
- indicadores de salud operativa.

Ejemplo:
si un profesor tiene evaluaciones pendientes de calificar, el dashboard debe mostrarlo y llevarlo directamente a la acción.

Si un aprendiz tiene una clase próxima, una evaluación pendiente o un documento incompleto, debe poder verlo claramente.

No implementes "IA" ficticia ni datos inventados.

---

## 5. UI/UX GLOBAL

Audita TODA la interfaz, no solo dashboard.

Debe existir un lenguaje visual consistente:

- tipografía;
- jerarquía;
- espaciado;
- bordes;
- radios;
- iconografía;
- botones;
- inputs;
- tablas;
- badges;
- modales;
- toasts;
- estados;
- colores semánticos;
- navegación.

Corrige:
- componentes desalineados;
- textos cortados;
- espacios excesivos;
- botones ambiguos;
- formularios poco claros;
- tablas difíciles de leer;
- feedback insuficiente;
- estados vacíos pobres;
- errores genéricos;
- modales incómodos;
- inconsistencias entre páginas.

La interfaz debe parecer un mismo producto.

---

## 6. LANDING PAGE — RECONSTRUIRLA

La landing actual necesita una revisión profunda.

Debe comunicar en pocos segundos:

- qué es INCES-LMS;
- para quién es;
- qué problema resuelve;
- beneficios;
- funcionalidades;
- experiencia;
- confianza;
- cómo empezar;
- acceso al sistema.

Construye una composición moderna, limpia y profesional.

Secciones posibles, según contenido real:

- Hero;
- propuesta de valor;
- capacidades principales;
- ciclo del aprendiz;
- experiencia de aula;
- gestión administrativa;
- beneficios;
- estadísticas reales si existen;
- CTA;
- información institucional;
- footer.

No rellenes con marketing falso.

Usa contenido coherente con INCES La Isabelica y el proyecto real.

---

## 7. IMÁGENES Y RECURSOS VISUALES

Si hacen falta imágenes, ilustraciones, iconos, fondos o recursos visuales, incorpóralos de forma profesional y con licencia/uso apropiado.

Preferir:
- recursos propios;
- SVG;
- ilustraciones generadas/permitidas;
- iconografía consistente;
- assets optimizados.

No agregues imágenes gigantes solamente para "verse bonito".

Optimiza:
- peso;
- formato;
- lazy loading;
- responsive;
- accesibilidad;
- alt text.

---

## 8. 3D / MOTION

Puedes introducir 3D, motion, microinteracciones o efectos visuales si elevan realmente el producto.

Pero deben cumplir:

- aportar jerarquía o identidad;
- no bloquear interacción;
- no afectar navegación;
- no afectar performance;
- tener fallback;
- respetar reduced motion;
- funcionar en equipos modestos;
- no convertirse en una demostración técnica sin propósito.

Ejemplos apropiados:
- elemento 3D sutil en hero;
- ilustración institucional animada;
- microinteracciones en tarjetas;
- transición de páginas;
- feedback de progreso;
- estados de carga elegantes.

NO conviertas el LMS en un videojuego.

La percepción buscada es:
"producto académico profesional moderno",
no:
"sitio experimental pesado".

---

## 9. RESPONSIVE REAL

Después de estabilizar funcionalidad/performance, validar cada vista importante en:

375
768
1024
1280
1440 px.

Comprobar:
- navegación;
- sidebar;
- tablas;
- formularios;
- dashboard;
- cards;
- modales;
- gráficos;
- landing;
- login;
- aula virtual;
- touch targets;
- scroll;
- overflow.

No aceptes "responsive" porque solamente desaparece el overflow.

---

## 10. ACCESIBILIDAD

Auditar:

- teclado;
- focus visible;
- labels;
- semántica;
- contraste;
- aria cuando corresponda;
- navegación lógica;
- estados de error;
- mensajes;
- reduced motion;
- tamaños de interacción.

---

## 11. PRODUCCIÓN

Cada cambio frontend importante debe verificarse en producción cuando sea posible.

No basta con localhost.

Comprobar:
- Pages;
- API;
- Supabase;
- CORS;
- autenticación;
- assets;
- rutas;
- cache;
- HEAD real desplegado;
- errores de consola/network relevantes.

Si aparece un error de login como el observado recientemente, reproducirlo y capturar la causa exacta antes de declarar PASS.

---

## 12. EVIDENCIA

Crea/actualiza una documentación de cierre con:

- matriz de módulos;
- matriz E2E;
- bugs encontrados;
- causa raíz;
- correcciones;
- pruebas;
- screenshots cuando sean útiles;
- métricas de performance;
- responsive;
- accesibilidad;
- producción;
- pendientes reales.

No ocultes fallos.

Un BLOCKED debe seguir siendo BLOCKED.

---

## 13. CRITERIO FINAL

No cierres el proyecto hasta que:

- todas las funcionalidades críticas tengan cobertura E2E;
- todos los módulos hayan sido recorridos;
- frontend y backend estén alineados;
- dashboard esté completo;
- landing esté modernizada;
- UI/UX sea consistente;
- responsive esté validado;
- accesibilidad esté revisada;
- performance esté medida;
- seguridad esté validada;
- producción esté verificada;
- regresión integral esté ejecutada;
- documentación esté actualizada;
- no existan errores críticos/altos conocidos sin justificar.

Si descubres que una funcionalidad "ya estaba implementada" pero nunca fue realmente probada, NO la marques como cerrada: pruébala.

Si descubres que el backend funciona pero el frontend no ofrece una experiencia completa, corrígelo.

Si descubres una inconsistencia entre documentación, backend, frontend, base de datos o producción, investiga la causa raíz y corrígela.

### REGLA DE CONTINUIDAD

No preguntes qué hacer después.

Cuando cierres una tarea:
→ verifica
→ documenta
→ encuentra la siguiente deficiencia
→ corrígela
→ prueba
→ continúa.

Si una integración externa está bloqueada:
→ registra el bloqueo
→ prepara todo lo demás
→ continúa con módulos independientes.

**No quiero un informe de lo que podrías hacer. Quiero que lo hagas.**

**EJECUTA ESTE MANDATO AHORA Y CONTINÚA HASTA EL CIERRE REAL DEL PRODUCTO.**
