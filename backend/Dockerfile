# ============================================================================
#  INCES LMS — API stateless
#  Imagen multi-etapa: la imagen final no lleva código fuente ni dependencias
#  de desarrollo, y corre como usuario sin privilegios.
# ============================================================================

# --- Etapa 1: dependencias de producción -------------------------------------
FROM node:22-alpine AS deps
WORKDIR /app

# Sólo el manifiesto: si el código cambia, esta capa sigue cacheada.
COPY package.json package-lock.json ./
RUN npm ci --omit=dev


# --- Etapa 2: compilación ----------------------------------------------------
FROM node:22-alpine AS build
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci

COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build


# --- Etapa 3: ejecución ------------------------------------------------------
FROM node:22-alpine AS runtime

ENV NODE_ENV=production \
    PORT=3000 \
    HOST=0.0.0.0

WORKDIR /app

# Usuario sin privilegios: si el proceso se compromete, no es root.
RUN addgroup -S app && adduser -S app -G app

COPY --from=deps  /app/node_modules ./node_modules
COPY --from=build /app/dist         ./dist
COPY package.json ./

USER app

EXPOSE 3000

# La sonda usa `fetch` nativo de Node 22: no hace falta curl ni wget.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+(process.env.PORT||3000)+'/salud').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "dist/server.js"]
