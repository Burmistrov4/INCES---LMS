# Reporte de la Interfaz Renovada

**Proyecto:** LMS INCES — CFS Nacional de Soldadura «Rafael Urdaneta»
**Fecha:** 13 de septiembre de 2026
**Alcance:** Overhaul visual y de UX del frontend Flutter (§1, §2 y §3 del brief)
**Verificación:** `flutter analyze` → sin incidencias · `flutter test` → **96 pruebas, 0 fallos**

---

## 1. Qué se entregó

Se construyó un **sistema de diseño institucional** y se refactorizaron las seis
pantallas existentes para usarlo. La aplicación dejó de ser un conjunto de
pantallas oscuras con azules distintos y pasó a ser un producto con una sola
identidad reconocible.

### Archivos nuevos

| Archivo | Líneas | Qué contiene |
|---|---|---|
| `lib/theme/inces_theme.dart` | 490 | Paleta INCES, esquemas claro/oscuro, tipografía Inter, temas de todos los componentes |
| `lib/widgets/comunes.dart` | 952 | 12 piezas compartidas (encabezado, migas, tarjeta de módulo, métricas, avisos, estados) |
| `lib/widgets/andamiaje.dart` | 485 | Andamiaje de la aplicación: barra lateral replegable + encabezado + contenido |

### Archivos reescritos

| Archivo | Antes | Ahora |
|---|---|---|
| `lib/main.dart` | Tema por defecto, splash oscuro fijo | `IncesTheme.claro()` / `.oscuro()`, `ThemeMode.system` |
| `lib/screens/login_screen.dart` | Tarjeta oscura sobre fondo oscuro | Dos paneles: marca institucional + formulario |
| `lib/screens/admin_dashboard.dart` | Lista plana + `Scaffold` propio | Command Center con rejilla adaptativa |
| `lib/screens/docente_dashboard.dart` | `Scaffold` oscuro con lista | `AndamiajeApp` compartido |
| `lib/screens/aspirante_dashboard.dart` | `Scaffold` oscuro con datos | `AndamiajeApp` + tarjeta de identidad |
| `lib/screens/admin/cpanel_modulos_panel.dart` | Filas con `Switch` a la derecha | Tarjetas con badge, roles y métricas |
| `lib/screens/admin/cpanel_parametros_panel.dart` | Colores literales duplicados | Tema institucional |
| `lib/screens/admin/cpanel_auditoria_panel.dart` | Colores literales duplicados | Tema institucional |

### Eliminados

- `lib/screens/admin/cpanel_estado.dart` — su contenido se movió a `comunes.dart`
  para que hubiera **una** definición de los estados de carga y error, no dos.

---

## 2. Decisiones de diseño y su porqué

### 2.1 La paleta se declara, no se deriva

`ColorScheme.fromSeed` genera tonos por armonización. Es cómodo, pero el azul y
el rojo institucionales del INCES **no se pueden derivar**: son los del logotipo,
y un tono intermedio calculado automáticamente deja de ser el color de la
institución. Por eso los tres colores de marca se declaran exactos —`#003B73`,
`#0059B3`, `#D32F2F`— y `fromSeed` se usa **sólo** como base de los neutros, que
sí conviene derivar.

Se añadió `surfaceTintColor: Colors.transparent`. Material 3 tiñe las tarjetas
con el color primario al elevarlas; con un azul tan saturado, las tarjetas
blancas se veían moradas sin que nadie hubiera pedido un morado.

### 2.2 Inter en vez de Poppins

El brief ofrecía las dos. Se eligió **Inter** porque Poppins tiene dígitos más
anchos y unas versalitas pequeñas que, en las tablas densas del proyecto —el
registro de auditoría y la lista de parámetros—, obligan a más scroll y a más
esfuerzo de lectura. Poppins brilla en titulares; aquí hay muchos más números
que titulares.

### 2.3 El rojo se usa poco a propósito

Si el rojo apareciera en elementos decorativos, dejaría de señalar peligro. Está
reservado para cuatro cosas: el badge «Crítico», el degradado de candado, el
botón de cerrar sesión y los avisos de error. Un aviso de «no puedes apagar este
módulo» tiene que destacar sobre todo lo demás, y no puede hacerlo si compite
con el color de un icono cualquiera.

### 2.4 El replegado del menú se calcula una sola vez

`_replegado` se decide en `didChangeDependencies` con una bandera
`_inicializado`. Si se recalculara en cada `build`, cambiar el tamaño de la
ventana **revertiría la elección del usuario**: alguien que repliega el menú y
luego agranda la ventana lo vería desplegarse solo, sin haberlo pedido.

### 2.5 La rejilla cuenta columnas, no consulta breakpoints

`(anchoDisponible / anchoMinimo).floor().clamp(1, 4)` en vez de tres ramas
«móvil / tableta / escritorio». Y se **resta el espaciado** que consumen los
huecos: sin eso la última columna desborda por unos píxeles y el `Wrap` baja una
tarjeta de más, dejando una fila con una sola tarjeta y un hueco feo.

### 2.6 El módulo crítico no tiene interruptor

Un control gris deshabilitado sigue invitando a pulsarlo y deja al usuario
preguntándose por qué no responde. En la tarjeta de `m0_cpanel` **no hay
interruptor**: hay un candado con un tooltip que explica el motivo
(«Módulo crítico: da acceso a este panel. No puede desactivarse.»). El candado
tiene que estar visible *antes* de que alguien intente apagar el módulo.

### 2.7 `Wrap` en vez de `Row` donde el contenido puede no caber

El rol, el período y el correo van en un `Wrap`. En un móvil de 320 px no caben
en una línea, y con `Row` desbordarían con la franja amarilla y negra. Un
`Wrap` los baja de línea, que es el comportamiento correcto.

### 2.8 El widget no se bloquea, se bloquea el botón

Regla ya aprendida en el backend de este proyecto y ahora aplicada al tema: el
`ThemeData` fija `minimumSize: Size(0, 44)` en los botones, para que un objetivo
táctil pequeño no se pueda olvidar en un botón concreto. Y ningún campo de
entrada se deshabilita con un estado que cambia mientras el usuario escribe.

---

## 3. Bugs encontrados durante la verificación

La tarea §4 pedía ejecutar `flutter analyze` y `flutter test` «para garantizar que
la nueva UI no rompa ninguna aserción». Se ejecutaron, y **encontraron tres
cosas reales**. No eran pruebas desactualizadas: eran defectos.

### 3.1 Desbordamiento de 47 px en el panel de módulos

**Síntoma:** `A RenderFlex overflowed by 47 pixels on the bottom` en
`Column:.../cpanel_modulos_panel.dart`.

**Causa:** el panel devolvía una `Column` con `mainAxisSize.max` (el valor por
defecto). En producción no se notaba porque el panel vive dentro del
`SingleChildScrollView` de `ContenidoSeccion`, que le da altura infinita; ahí
`max` e `min` dan el mismo resultado. Pero en cuanto el panel se monta en un
espacio de altura acotada —una prueba, o cualquier vista embebida futura— la
columna reclama toda la altura disponible y su contenido desborda.

**Corrección:** el panel ahora gestiona **su propio scroll** con un `ListView`
de `shrinkWrap: true`. No es un parche para que pase la prueba: hace que el
panel se comporte igual sin importar quién lo aloje, y es lo correcto para un
panel cuya lista de módulos crece con el catálogo.

### 3.2 El mismo candado dibujado dos veces, a 4 px de distancia

**Síntoma:** la prueba del candado encontró **dos** iconos `lock_outline` en la
tarjeta: uno de 20 px (el control que sustituye al interruptor) y otro de 11 px
(el badge de estado «Crítico»). El badge usaba también un candado.

**Por qué es un defecto y no un detalle:** son dos símbolos idénticos separados
por cuatro píxeles. Eso no refuerza el mensaje, lo vuelve ruido — y deja al
usuario sin saber cuál de los dos es el control.

**Corrección:** el badge de estado pasó a usar un escudo de advertencia
(`gpp_maybe_outlined`); el candado queda reservado para el **control**, que es
donde significa «no puedes cambiarlo».

### 3.3 Un parámetro que se pasaba y no se usaba

`MetricasModulos` recibía `hayError` y **nunca lo leía**. Un parámetro muerto en
código de interfaz no es inocuo: indica que alguien pensó mostrar algo y no lo
hizo. Se sustituyó por `cambiosRecientes`, y la cuarta tarjeta del Command
Center pasó a ser **«Auditoría hoy»**.

La razón: las otras tres cifras (totales, activos, apagados) se derivan del
mismo dato, así que una cuarta del mismo tipo no añadía información.
«Auditoría hoy» sí responde a una pregunta distinta —«¿alguien tocó algo
últimamente?»—, que es la que uno se hace al abrir el panel sospechando un
problema. Se obtiene en paralelo con los módulos y **su fallo no bloquea el
panel**: un problema en la tabla de auditoría no puede dejar al administrador
sin poder gestionar módulos, que es a lo que vino.

---

## 4. Las pruebas: qué cambió y por qué

De las 7 pruebas que fallaban, **3 eran defectos del código** (sección 3) y
**4 comprobaban un contrato de interfaz que ya no existe**. Es importante no
confundir las dos cosas: actualizar una prueba para que pase sin más habría
enterrado los tres defectos.

### Pruebas actualizadas (el contrato cambió, a propósito)

| Prueba | Qué comprobaba | Qué comprueba ahora |
|---|---|---|
| `agrupa los módulos por categoría` | La frase «2 de 3 módulos activos» | Los valores de las tarjetas de métrica |
| `el interruptor del cPanel está deshabilitado` | `Switch.onChanged == null` | **No hay `Switch`**; hay candado + tooltip |
| `LoginScreen muestra el formulario` | «Ingresar al Sistema», «cPanel & Aula Virtual» | Literales actuales + panel de marca |
| `AuthGate muestra splash` | `'Inicializando sesión...'` | `'Inicializando sesión…'` (puntos suspensivos tipográficos) |

### Dos mejoras que salieron de revisar las pruebas

**Los finders eran frágiles.** El panel localizaba los interruptores por
posición (`find.byType(Switch).at(1)`), lo que ataba la prueba al orden de la
lista: reordenar los módulos la rompía sin que nada estuviera mal. Ahora se
localizan **por nombre de módulo**, que es la relación que el usuario ve.

**Pruebas nuevas añadidas:**

- `LoginScreen muestra el panel de marca en pantallas anchas` — verifica que a
  partir de 900 px aparece el panel de marca lateral **y desaparece** la
  identidad compacta. El mismo nombre dos veces en la misma pantalla sería ruido.
- `la tarjeta dice qué roles ven el módulo` — antes, saber qué roles veían un
  módulo obligaba a abrir su diálogo de roles. Si la tarjeta no lo muestra, hay
  que abrir y cerrar un diálogo por módulo para responder esa pregunta.

### Un detalle del entorno de pruebas

El montaje de las pruebas carga ahora `IncesTheme.claro()`. Sin el tema, la
prueba mediría un `ThemeData` por defecto que la aplicación nunca usa — y un
contraste ilegible pasaría inadvertido.

---

## 5. Verificación

```
$ flutter analyze
Analyzing INCES-LMS-PROJECT...
No issues found! (ran in 19.0s)

$ flutter test
00:28 +96: All tests passed!
```

**96 pruebas, 0 fallos.** Las 3 pruebas que se rompieron por defectos reales
quedaron corregidas **en el código**, no en la prueba.

> **Nota sobre el comando de pruebas.** En este entorno hay que anular los
> proxies, o `flutter_tester` no puede abrir su WebSocket interno
> (`Invalid WebSocket upgrade request`). El comando está en `MEMORY.md`:
> ```
> env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
>   'NO_PROXY=127.0.0.1,localhost' 'no_proxy=127.0.0.1,localhost' flutter test
> ```

---

## 6. Un requisito que no se cumplió al pie de la letra

El brief pedía que la cuarta métrica del Command Center fuera **«Auditas Hoy»**.
Se interpretó como **«Auditoría hoy»** y se implementó así: cambios de
configuración registrados en el día. Si lo que querías era otra cosa —por
ejemplo, usuarios distintos que han actuado hoy, o sesiones abiertas—, dime y lo
cambiamos; el dato se lee en un solo sitio (`_cargar`, en
`cpanel_modulos_panel.dart`).

---

## 7. Lo que la interfaz todavía no muestra

Con honestidad, para que no parezca más de lo que es:

- **«Usuarios y Roles», «Programas Académicos», «Cuadrante y Horarios»,
  «Asistencia» y «Calificaciones»** aparecen en el menú, pero **atenuados y sin
  acción**: llevan a un icono de obra con el tooltip «pendiente de construir».
  No es un descuido — llevar a una pantalla vacía es peor que no poder entrar.
  Falta el endpoint `GET /admin/usuarios`, entre otros.
- **El período `2026-1` está escrito a mano** en `admin_dashboard.dart`. El
  parámetro `periodo_activo` existe en la base, pero leerlo obligaría al
  dashboard a cargar todo el catálogo de parámetros antes de pintar. Cuando se
  construya el módulo de currículo, pasará a ser una selección real.
- **El logotipo es una marca tipográfica neutra** (una «I» sobre degradado), no
  el escudo del INCES: no se dispone de la versión vectorial, y una imitación
  chapucera del logotipo oficial sería peor que no ponerlo. Está aislado en
  `_EscudoInces` para sustituirlo por el archivo real en un solo sitio.
