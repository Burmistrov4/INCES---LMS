# Sistema de producto y diseño premium — INCES LMS

**Estado:** estrategia documentada; implementación visual pendiente de ejecución y validación.  
**Fecha:** 2026-10-08  
**Propósito:** elevar la experiencia del LMS del INCES de La Isabelica con calidad de plataforma universitaria de referencia, sin copiar la identidad gráfica de Harvard ni afirmar afiliación.

## 1. Principios de producto

1. **Institucional y propio.** Priorizar el nombre, escudo y activos oficiales del INCES cuando exista un archivo oficial verificable. No dibujar un escudo ficticio ni reutilizar el logotipo, tipografía de marca o recursos de Harvard.
2. **Primero la tarea.** Cada pantalla debe responder: dónde estoy, qué requiere atención, qué puedo hacer ahora y qué ocurrió con mi última acción.
3. **Un sistema, tres experiencias.** Compartir componentes, navegación y lenguaje visual; adaptar el contenido al rol de estudiante/aprendiz, docente y administrador.
4. **Datos con procedencia.** Métricas y avisos deben proceder de endpoints reales, mostrar cuándo se actualizaron y ofrecer estados de carga, vacío, error y reintento. Nunca fabricar estadísticas para decorar.
5. **Accesible por defecto.** Objetivo de diseño WCAG 2.2 AA; es una meta de aceptación, no una certificación hasta completar auditoría manual y automática.
6. **Movimiento con propósito.** Las animaciones refuerzan orientación y jerarquía, no bloquean tareas ni esconden información.
7. **Rendimiento antes que espectáculo.** CSS 3D ligero, una escena focalizada y fallback estático; nada de WebGL ni bibliotecas grandes salvo que una medición demuestre valor neto.

## 2. Referencias de investigación

- Harvard HUIT Learning Experience Platform: referencia de enfoque centrado en aprendizaje, herramientas docentes, colaboración y experiencia consistente.
- Política de accesibilidad digital de Harvard HUIT: referencia institucional para acceso equitativo, no para copiar su identidad.
- W3C WCAG 2.2 y WAI: criterios de accesibilidad para teclado, foco visible, contraste, movimiento y controles.
- La investigación inspira principios de calidad; el contenido, marca, procesos y arquitectura deben seguir siendo propios del INCES y las necesidades del CFS de La Isabelica.

## 3. Identidad visual

### Tokens base propuestos

- Azul institucional existente en el tema: `#003B73`; azul de acción `#0059B3`; rojo institucional `#D32F2F`. Confirmar contra manual/logotipo oficial antes de declarar estos valores definitivos.
- Superficies claras, fondos neutros y bordes discretos; reservar el rojo para error, riesgo y acciones destructivas.
- Tipografía funcional Inter (ya usada en el tema actual), jerarquía clara, cifras tabulares para métricas y longitud de línea cómoda.
- Radios, elevación y espaciado consistentes; no mezclar tarjetas con sombras fuertes, gradientes decorativos y bordes de estilos diferentes.
- Iconos de una sola familia; icono siempre acompañado por texto cuando su significado no sea universal.
- No usar sellos como “Harvard”, escudos similares, claims de acreditación ni métricas institucionales inventadas.

## 4. Arquitectura de la landing

1. **Cabecera:** identidad INCES real, enlaces cortos, acción principal visible y menú móvil accesible.
2. **Hero:** promesa concreta sobre formación y gestión académica; CTA de acceso; visual de producto real o mockup claramente ilustrativo.
3. **Prueba de producto:** captura real revisada, no una imagen que prometa módulos aún no verificados.
4. **Ciclo formativo:** aspirante → inscripción/cupo → formación → clases y evaluaciones → asistencia → constancia/certificación, únicamente donde cada etapa esté respaldada por el producto.
5. **Capacidades por perfil:** aprendiz, docente y administración; describir capacidades implementadas, no futuras.
6. **Confianza y accesibilidad:** privacidad, acceso y soporte sólo con afirmaciones verificadas.
7. **Preguntas frecuentes, contacto institucional y pie:** datos oficiales comprobados; evitar teléfonos/correos inventados.

## 5. Dashboards por rol

### Aprendiz/estudiante
- Próxima clase y horario vigente.
- Cursos/aulas activos y accesos recientes.
- Entregas o evaluaciones pendientes con fecha.
- Estado de inscripción y acciones siguientes cuando exista un bloqueo.
- Una acción primaria, evitando duplicar enlaces del menú.

### Docente
- Próximas clases/secciones.
- Asistencia pendiente de registrar.
- Entregas/evaluaciones que requieren revisión.
- Alertas de agenda o sección sin datos esenciales, si el backend lo detecta.

### Administrador
- Estado del ciclo de inscripción, cupos y secciones.
- Solicitudes y tareas administrativas pendientes.
- Salud de módulos y últimos eventos de auditoría, limitados por permisos.
- Accesos rápidos a tareas frecuentes; evitar un muro de contadores sin acción.

## 6. 3D CSS ligero e interactivo

- Inspeccionar y portar sólo el patrón técnico de la landing del proyecto Python TechLoan; no copiar nombres, paleta comercial, iconografía ni contenido.
- Preferir una composición CSS con perspectiva moderada, capas transformadas y respuesta pequeña al puntero; limitar el movimiento y no seguir el cursor con toda la página.
- Activar interacción de puntero sólo en dispositivos con hover/puntero fino; en táctil, mostrar composición estática.
- Respetar `prefers-reduced-motion: reduce`; con reducción de movimiento, sin parallax ni transiciones espaciales.
- Evitar listeners globales innecesarios; actualizar variables CSS con throttling/RAF sólo si las mediciones lo justifican y limpiar listeners.
- Fallback estático si JS no carga. El contenido esencial y los CTA no pueden depender de la animación.
- No introducir canvas, WebGL, shaders o dependencia 3D pesada para resolver una necesidad que CSS cubre.

## 7. Accesibilidad y calidad

- Navegación completa con teclado; foco visible que no quede tapado por cabeceras o diálogos.
- Contraste de texto y controles conforme a WCAG 2.2 AA; no usar sólo color para estado.
- Objetivos táctiles adecuados, etiquetas accesibles, nombres claros y errores vinculados al campo.
- Modales con foco gestionado y restaurado; escape/cierre coherentes; sin trampas de teclado.
- Reflujo a 320 CSS px y zoom; probar al menos 375, 768, 1024, 1280 y 1440 px.
- Formularios, tablas y gráficas deben conservar sentido semántico; ofrecer alternativa textual a información gráfica.
- Medir LCP, CLS, INP y tamaño comprimido de la landing antes/después. Animación no debe retrasar CTA ni contenido útil.

## 8. Secuencia y puertas de aceptación

1. **Auditar estado real:** componentes, tema, rutas, datos, marca y técnica CSS de TechLoan.
2. **Cerrar bloqueos de funcionalidad y rendimiento** antes del rediseño global; mantener la regla del plan maestro.
3. **Landing:** estructura y contenido verificado → marca → visual de producto → movimiento CSS 3D → responsive y accesibilidad.
4. **Dashboard:** primero jerarquía y tareas por rol; luego componentes y microinteracciones.
5. **Validar:** análisis estático, pruebas focalizadas, navegación teclado, reduced-motion, capturas por viewport y mediciones de rendimiento.
6. **Publicar:** no afirmar que el rediseño está cerrado hasta revisar producción y registrar evidencia.

## 9. Registro de alcance

- [x] Investigación de referencia institucional y WCAG realizada.
- [x] Principios, arquitectura, dirección visual, dashboards por rol y reglas 3D documentados.
- [ ] Auditar en el repositorio los archivos exactos de landing y dashboard antes de modificarlos.
- [ ] Portar y adaptar el patrón CSS 3D de TechLoan con marca INCES propia.
- [ ] Implementar rediseño de landing/dashboard.
- [ ] Ejecutar pruebas de accesibilidad, responsive y rendimiento.
- [ ] Verificar el resultado en producción.

## 10. Fuentes de referencia

- Harvard HUIT Learning Experience Platform: https://www.huit.harvard.edu/lxp
- Harvard HUIT Digital Accessibility Policy: https://accessibility.huit.harvard.edu/digital-accessibility-policy
- W3C WCAG 2.2: https://www.w3.org/TR/WCAG22/
- W3C WAI — WCAG overview: https://www.w3.org/WAI/standards-guidelines/wcag/

Estas fuentes son referencias de investigación, no prueba de conformidad ni aval de Harvard al proyecto.


## 11. Auditoría inicial del código existente — 2026-10-08

- La landing pública actual es `lib/screens/landing_page.dart` (978 líneas), se muestra sin sesión mediante `AuthGate` y carga oferta desde `AspiranteRepository.obtenerProgramasDisponibles()`.
- La portada ya contiene un elemento decorativo llamado `_construirInsigniaIndustrial3D()`, pero es una tarjeta estática con icono de manufactura: no es una escena 3D interactiva. El siguiente rediseño debe sustituirla por un visual más útil del producto, sin simular una certificación oficial.
- La marca actual se dibuja como una letra «I» en un recuadro; no se verificó aún la existencia de un archivo oficial del escudo INCES. Mantener una marca tipográfica honesta hasta localizar un activo oficial autorizado.
- La landing contiene afirmaciones que requieren verificación funcional antes de publicarse como promesas: «sin límite de transferencia», asignación FIFO, «monitoreo en tiempo real», «certificación INCES valedera» y disponibilidad 24/7. El diseño premium no debe amplificar claims no demostrados; confirmar con código, backend y responsable institucional o reformularlos.
- La implementación TechLoan usa DOM + CSS `perspective/transform-style`, interpolación de orientación con `requestAnimationFrame`, arrastre con `pointer capture`, vuelta al reposo y `prefers-reduced-motion`. En INCES el frontend es Flutter Web; por ello se debe traducir el patrón a interacción Flutter (p. ej., `MouseRegion` + `GestureDetector` + `Transform`) en vez de injertar HTML/JS externo sin necesidad.
- El panel de administración ya tiene un tema institucional en `lib/theme/inces_theme.dart` y paneles por módulo. No crear un segundo sistema de estilos: mejorar tokens y componentes compartidos dentro del tema actual.
- La landing y dashboards no deben rediseñarse hasta respetar las puertas de rendimiento y regresión descritas por el plan maestro. Se permite la auditoría de UX y la preparación del diseño mientras se resuelven los bloqueos.
