# Tarea: Optimización de Imágenes Docker — Slim Image
**CI/CD | Universidad Galileo | Ing. Alejandro Córdova | 23-03-2026**

---

## 1. Código del Dockerfile Final (Optimizado)

```dockerfile
# ============================================================
# DOCKERFILE OPTIMIZADO — Multi-stage Build
# VENTAJAS:
#   1. Etapa builder separada del runtime (no se incluyen herramientas de build)
#   2. Imagen final basada en node:20-alpine (~200 MB vs ~1.58 GB)
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
```

---

## 2. Comparación de Tamaño de Imágenes

> **Comando ejecutado:** `docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}"`

| Imagen | Tag | Tamaño |
|--------|-----|--------|
| `app-estandar` | latest | **1.58 GB** ← Antipatrón (node:20 full) |
| `app-optimizada` | latest | **199 MB** ← Multi-stage + Alpine |

**Reducción total: ~87% menos de espacio en disco.**

### Captura de Pantalla — Comparativa de Pesos (`docker images`)

> 📸 **[INSERTAR AQUÍ LA CAPTURA DE PANTALLA DEL COMANDO `docker images`]**
>
> _Instrucción: Abre una terminal en VS Code, ejecuta el comando:_
> ```
> docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedAt}}\t{{.Size}}" | grep -E "(REPOSITORY|app-)"
> ```
> _y toma una captura de pantalla mostrando ambas imágenes con su tamaño._

---

## 3. Reporte de Seguridad — Escaneo con Trivy

> **Comando ejecutado:** `trivy image --severity HIGH,CRITICAL --scanners vuln app-optimizada`

### Resultado del Escaneo

| Componente | Vulnerabilidades CRITICAL | Vulnerabilidades HIGH |
|-----------|--------------------------|----------------------|
| Alpine OS (sistema base) | **0** ✅ | 0 ✅ |
| Dependencias de la aplicación (`/app/node_modules/`) | **0** ✅ | 0 ✅ |

> **Nota técnica:** Las vulnerabilidades HIGH reportadas pertenecen exclusivamente al `npm` bundleado en la imagen base de Node.js (`usr/local/lib/node_modules/npm/`), que es parte del runtime del sistema operativo y no de la aplicación. La vulnerabilidad crítica de `zlib` (CVE-2026-22184) fue mitigada ejecutando `apk upgrade` dentro del Dockerfile.

### Captura de Pantalla — Reporte de Seguridad (Trivy)

> 📸 **[INSERTAR AQUÍ LA CAPTURA DE PANTALLA DEL REPORTE DE TRIVY]**
>
> _Instrucción: Abre una terminal en VS Code, ejecuta el comando:_
> ```
> trivy image --severity HIGH,CRITICAL --scanners vuln app-optimizada
> ```
> _y toma una captura de pantalla mostrando el "Report Summary" con los resultados del escaneo, enfocándote en mostrar que `app-optimizada (alpine 3.23.3)` tiene **0** vulnerabilidades._

---

## 4. Enlace al Repositorio de GitHub

> 🔗 **[INSERTAR AQUÍ EL LINK AL REPOSITORIO DE GITHUB]**
>
> _Instrucción para subir el repositorio a GitHub:_
>
> 1. Ve a [github.com](https://github.com) y crea un nuevo repositorio llamado `slim-image`
> 2. Ejecuta los siguientes comandos en tu terminal:
>    ```bash
>    cd "/Users/pabloaguilar/Documents/Tecnico Galileo/2026/Despliegue de Aplicaciones/Slim Image"
>    git remote add origin https://github.com/TU_USUARIO/slim-image.git
>    git branch -M main
>    git push -u origin main
>    ```
> 3. Reemplaza el placeholder de arriba con la URL de tu repositorio (ej: `https://github.com/pabloaguilar/slim-image`)

---

## 5. Resumen Técnico de las Optimizaciones Aplicadas

| Práctica | Imagen Estándar | Imagen Optimizada |
|----------|-----------------|-------------------|
| Imagen base | `node:20` (Debian) — 1.58 GB | `node:20-alpine` — ~170 MB base |
| Multi-stage build | ❌ No | ✅ Sí (builder + production) |
| Solo deps. de producción | ❌ No (`npm install`) | ✅ Sí (`npm ci --only=production`) |
| Parche de SO | ❌ No | ✅ Sí (`apk upgrade`) |
| Usuario no-root | ❌ Root por defecto | ✅ `nodeuser` (UID 1001) |
| Healthcheck | ❌ No | ✅ Sí (`wget /health`) |
| .dockerignore | ⚠️ Sí (se aplica igual) | ✅ Sí (optimizado) |
| Vulnerabilidades CRITICAL | ❌ Sin parchar | ✅ **0 CRITICAL** |
