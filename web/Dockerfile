# Web 前端 Dockerfile (Debian bookworm 基础)
FROM node:20-bookworm-slim AS build
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY package*.json ./
RUN npm ci --no-audit --no-fund
COPY . .
RUN npm run build

FROM nginx:1.27-bookworm
LABEL org.opencontainers.image.description="Player2 AI Web Console (Debian)"
ENV TZ=Asia/Shanghai
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl ca-certificates tzdata \
 && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
 && echo "${TZ}" > /etc/timezone \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK --interval=60s --timeout=5s --retries=3 \
  CMD curl -fsS http://localhost/ || exit 1
CMD ["nginx", "-g", "daemon off;"]
