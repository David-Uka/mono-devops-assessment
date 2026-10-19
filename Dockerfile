# ---------------------------------------------------------------------------
# Stage 1: build  - compile TypeScript with the full dependency set
# ---------------------------------------------------------------------------
FROM node:24-alpine AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2: deps   - production-only node_modules, no compilers or type defs
# ---------------------------------------------------------------------------
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund \
    && npm cache clean --force

# ---------------------------------------------------------------------------
# Stage 3: runtime - minimal, non-root, read-only friendly
# ---------------------------------------------------------------------------
FROM node:24-alpine AS runtime
ENV NODE_ENV=production \
    PORT=3000
WORKDIR /app

# npm is a build-time tool. Dropping it from the runtime image removes its
# bundled dependencies (undici, brace-expansion, ...) from the attack surface.
RUN rm -rf /usr/local/lib/node_modules/npm /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack

# Drop to the unprivileged `node` user that ships with the official image
COPY --chown=node:node --from=deps  /app/node_modules ./node_modules
COPY --chown=node:node --from=build /app/dist         ./dist
COPY --chown=node:node package.json ./

USER node
EXPOSE 3000

# Kubernetes probes hit /health; this keeps `docker run` users honest too
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:${PORT}/health || exit 1

CMD ["node", "dist/server.js"]
