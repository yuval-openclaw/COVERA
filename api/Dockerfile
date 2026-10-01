# Clausa API — production image.
#
# Build:   docker build -t covera-api api/
# Migrate: docker run --env-file prod.env covera-api node dist/db/migrate.js
# Run:     docker run --env-file prod.env -p 3000:3000 covera-api
#
# Needs Postgres with the pgvector extension, and S3-compatible storage
# (STORAGE_DRIVER=s3): a container's own disk is lost on every deploy.

FROM node:22-slim AS build
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY tsconfig.json tsconfig.build.json ./
COPY src ./src
RUN npm run build

FROM node:22-slim
ENV NODE_ENV=production \
    HOST=0.0.0.0 \
    PORT=3000
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY --from=build /app/dist ./dist
# Health documents pass through this process; it has no reason to run as root.
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"
CMD ["node", "dist/server.js"]
