# ============================================================
# DOCKERFILE OPTIMIZADO — Multi-stage Build
# VENTAJAS:
#   1. Etapa builder separada del runtime (no se incluyen herramientas de build)
#   2. Imagen final basada en node:20-alpine (~150 MB vs ~1 GB)
#   3. Solo dependencias de producción en la imagen final
#   4. Menor superficie de ataque: menos paquetes = menos vulnerabilidades
#   5. Usuario no-root para ejecución (principio de mínimo privilegio)
# ============================================================

# ── Etapa 1: Builder ─────────────────────────────────────────
FROM node:20 AS builder

WORKDIR /app

# Copiar solo manifiestos primero → aprovecha el cache de capas Docker.
# Si el código cambia pero las dependencias no, esta capa se reutiliza.
COPY package*.json ./

# Instalar TODAS las dependencias (incluyendo devDependencies para el build)
RUN npm ci --ignore-scripts

# Copiar el código fuente y ejecutar el proceso de build
COPY index.js ./
RUN npm run build

# ── Etapa 2: Producción (Runtime) ────────────────────────────
FROM node:20-alpine AS production

# Metadatos de la imagen (buena práctica: trazabilidad)
LABEL maintainer="DevOps Team" \
      version="1.0.0" \
      description="Slim Image App - Optimized production image"

WORKDIR /app

# Copiar ÚNICAMENTE el artefacto compilado desde la etapa builder.
# El código fuente, devDependencies y herramientas de build NO se incluyen.
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package*.json ./

# Actualizar paquetes del SO para mitigar vulnerabilidades del sistema base (CVEs de zlib, etc.)
# y luego instalar SOLO dependencias de producción de la app
RUN apk update && apk upgrade --no-cache && \
    npm ci --only=production --ignore-scripts && \
    # Limpiar cache de npm y apk para reducir tamaño de imagen
    npm cache clean --force && \
    rm -rf /var/cache/apk/* && \
    # Crear usuario sin privilegios (principio de mínimo privilegio)
    addgroup -g 1001 -S nodejs && \
    adduser -S nodeuser -u 1001 -G nodejs

# Cambiar al usuario sin privilegios antes de ejecutar la app
USER nodeuser

EXPOSE 3000

# Healthcheck integrado: Docker monitorea que la app esté viva
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD wget -qO- http://localhost:3000/health || exit 1

CMD ["node", "dist/index.js"]
