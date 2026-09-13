# INCES LMS — CFS Nacional de Soldadura "Rafael Urdaneta"

Sistema de gestión de aprendizaje a la medida del **INCES** (Instituto Nacional de
Capacitación y Educación Socialista), sede La Isabelica. Nace como Trabajo Especial
de Grado de Análisis de Sistemas (IUTEPI, 4.º semestre, período SA26-2) con un
objetivo declarado: **superar a Google Classroom** en lo que el INCES necesita de
verdad — inscripciones, cupos, cuadrante, asistencia y calificaciones bajo las
reglas del instituto, no bajo las de una herramienta genérica.

| | |
| --- | --- |
| **Equipo** | José Tarazón · Lorenzo Roca · Sleither Vásquez · Adrián Cedeño |
| **Tutor** | Prof. Maglis Camacho |
| **Stack** | Flutter · Supabase (PostgreSQL) · Node.js/TypeScript · Cloudflare R2 |

---

## Estado actual

Fases **1, 2 y 3** completas y verificadas. La base de datos está desplegada en la
nube y la API está probada de extremo a extremo contra ella.

> El documento que manda es **[`ESTADO_DEL_SISTEMA.md`](ESTADO_DEL_SISTEMA.md)**.
> Describe el estado **real**: lo construido, lo verificado y lo que falta. Si algo
> contradice a otro archivo, manda ese.

---

## Arquitectura

```
┌──────────────────────────┐        ┌───────────────────────────┐
│  Flutter (Web / móvil)   │  HTTPS │  API Node/TS (stateless)  │
│  Material 3 · responsive │ ─────► │  Fastify 5 · Zod          │
└──────────────────────────┘        └─────────────┬─────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────────┐
                    ▼                             ▼                         ▼
         ┌────────────────────┐      ┌─────────────────────┐     ┌──────────────────┐
         │ Supabase (Postgres)│      │ Supabase Auth       │     │ Cloudflare R2    │
         │ RLS + triggers     │      │ JWT verificados     │     │ URLs prefirmadas │
         └────────────────────┘      └─────────────────────┘     └──────────────────┘
```

**Todo el estado vive en el JWT y en la base de datos.** La API no guarda sesiones,
no escribe en disco y no necesita réplicas pegajosas: se puede escalar horizontalmente
o correr en un servidor local sin cambiar una línea.

### Por qué estas piezas y no otras

- **Supabase en lugar de un Postgres propio:** los cortes eléctricos exigen que el
  sistema siga disponible sin un servidor encendido en el instituto. El *free tier*
  no se duerme.
- **RLS + triggers en lugar de sólo validación en la API:** la API es una puerta, no
  la única. Las invariantes del sistema (no apagar el cPanel, no dejar el sistema sin
  administradores) viven en la base, porque desde el editor SQL o una migración se
  puede esquivar la API.
- **R2 en lugar de subir archivos a la API:** el backend no debe ver pasar los PDFs
  de 20 MB. El servidor construye la clave y firma una URL; el archivo va directo.

---

## Puesta en marcha

### 1. Base de datos

```bash
# Aplica las migraciones al proyecto de Supabase (necesita un token personal)
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/apply-migrations.mjs

# Comprueba el resultado contra el catálogo de PostgreSQL
SUPABASE_ACCESS_TOKEN=sbp_xxx node supabase/verificar-esquema.mjs
```

> Se usa la API de administración por HTTPS y no `supabase db push` porque el host
> directo de la base resuelve **sólo a IPv6** y falla con `ENETUNREACH` en la mayoría
> de las conexiones residenciales. Ver D10 en `ESTADO_DEL_SISTEMA.md`.

### 2. Primer administrador

El auto-registro **nunca** otorga rol, y eso es deliberado: si la aplicación pudiera
promoverse a sí misma, cualquiera con la clave publicable —que viaja en el bundle del
navegador— sería administrador del INCES. El primero se crea fuera de la aplicación:

```bash
node supabase/crear-admin.mjs correo@dominio.com --dry-run   # simulacro
node supabase/crear-admin.mjs correo@dominio.com             # real
```

### 3. API

```bash
cd backend
npm install
npm run dev            # http://localhost:3000
curl http://localhost:3000/salud/profundo
```

Configura `backend/.env` a partir de `backend/.env.example`. La clave **secreta**
(`sb_secret_...`) salta RLS por completo: no debe salir de ese archivo.

### 4. Frontend

```bash
flutter pub get
flutter run -d chrome --web-port=8080 --dart-define-from-file=.env.json
```

Flutter **no lee `.env` en tiempo de ejecución**: `String.fromEnvironment()` se
resuelve al compilar, por eso la configuración viaja con `--dart-define-from-file`.

`--web-port=8080` **no es opcional en desarrollo**. Sin él, `flutter run` toma un
puerto libre cualquiera (10443, 53211…) distinto en cada arranque, y el backend lo
rechaza porque `CORS_ORIGINS` sólo lista orígenes concretos. El síntoma es
confuso: la pantalla carga, pero cada llamada a la API falla con un error de CORS
en la consola del navegador. Fijando el puerto, el origen es siempre el mismo.

> El login del frontend habla **directo con Supabase**, no con la API propia. Si
> Supabase acepta la petición pero la API la rechaza, el problema es CORS.

---

## Verificación

```bash
# Frontend
flutter analyze && flutter test

# SQL sobre PostgreSQL real, sin Docker ni Supabase
cd supabase/tests && npm install && npm test

# Backend
cd backend && npm run typecheck && npm run lint && npm test && npm run build

# Cadena completa contra la nube real (API → Auth → Postgres)
node backend/test-humo.mjs
```

| Red de seguridad | Comprobaciones |
| --- | --- |
| `flutter test` | 88 |
| `supabase/tests` (PGlite) | 49 |
| `npm test` (backend) | 138 |
| `verificar-esquema.mjs` (nube) | 30 |
| `test-humo.mjs` (nube) | 24 |

---

## Contrato de la API

El documento **OpenAPI 3.1 se genera a partir de los esquemas Zod**, que son el único
contrato real: los mismos que validan las peticiones en tiempo de ejecución. Un
`openapi.yaml` escrito a mano es un segundo contrato que se desincroniza en la primera
semana, sin que ninguna prueba lo note.

```bash
cd backend && npm run openapi      # regenera openapi.json
curl -s localhost:3000/openapi.json | jq   # el mismo documento, en vivo
```

---

## Estructura

```
├── lib/                 Flutter: pantallas, repositorios, puertos (interfaces)
├── backend/             API stateless (Fastify + Zod + TypeScript)
│   ├── src/dominio/     Reglas puras y puertos — sin HTTP, sin Supabase
│   ├── src/infra/       Adaptadores: Supabase, R2, cachés
│   ├── src/http/        Rutas, esquemas, plugins, OpenAPI
│   └── test/            Pruebas con la API montada en memoria
├── supabase/
│   ├── migrations/      SQL versionado (esquema, RLS, triggers)
│   ├── tests/           Validador sobre PostgreSQL real (PGlite)
│   └── *.mjs            Aplicar migraciones, verificar esquema, crear admin
└── docs/                Plan maestro y documentos de decisiones
```

**La regla que ordena las carpetas:** el dominio no conoce ni HTTP ni Supabase. Depende
de *puertos* (interfaces) y la infraestructura los implementa. Por eso las reglas se
prueban sin montar nada, y por eso se puede cambiar de proveedor sin tocar la lógica.
