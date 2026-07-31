---
name: dockerize-monorepo
description: Создаёт и проверяет production Dockerfile для Go backend и Next.js frontend, а также корневой docker-compose.yml для Mereytoi.
disable-model-invocation: true
---

# Dockerize Mereytoi

Сначала вызови `/project-audit`.

## Архитектура

Репозиторий:

```text
backend/
frontend/
docker-compose.yml
```

Production-сервисы:

- `postgres`: PostgreSQL 17;
- `backend`: Go API;
- `frontend`: Next.js standalone;
- наружу публикуются только loopback-порты:
  - `127.0.0.1:8090:8090`;
  - `127.0.0.1:3000:3000`;
- PostgreSQL наружу не публикуется.

## Backend Dockerfile

Определи реальный Go entrypoint. Не угадывай `./cmd/server`, если структура отличается.

Требования:

- multi-stage build;
- builder на официальном образе Go;
- `CGO_ENABLED=0`;
- минимальный runtime;
- запуск не от root;
- `ca-certificates` и `tzdata`;
- uploads в `/app/uploads`;
- порт 8090;
- не копировать `.env`.

## Frontend Dockerfile

Требования:

- `npm ci`;
- Next.js `output: "standalone"`;
- multi-stage;
- production runner не от root;
- `NEXT_PUBLIC_API_URL` передаётся как build argument;
- `PORT=3000`;
- `HOSTNAME=0.0.0.0`;
- не копировать `.env`.

## Compose

Используй образы:

```text
${DOCKERHUB_USERNAME}/mereytoi-backend:${IMAGE_TAG:-latest}
${DOCKERHUB_USERNAME}/mereytoi-frontend:${IMAGE_TAG:-latest}
```

Требования:

- `restart: unless-stopped`;
- отдельная сеть `mereytoi-network`;
- named volumes для PostgreSQL и uploads;
- healthcheck PostgreSQL;
- backend зависит от healthy PostgreSQL;
- секреты читаются из production `.env` на VPS;
- не добавлять пароли в Git;
- не использовать `network_mode: host`;
- не использовать `latest` как единственный доступный rollback-тег в CI.

## Проверка

Запусти:

```bash
docker compose config
docker build -t mereytoi-backend:test ./backend
docker build --build-arg NEXT_PUBLIC_API_URL=https://mereytoi.kz/api -t mereytoi-frontend:test ./frontend
```

Если безопасно для локальной среды:

```bash
docker compose up -d
docker compose ps
docker compose logs --tail=100 backend
docker compose logs --tail=100 frontend
```

Не удаляй существующие volumes.

## Результат

Покажи:

- созданные/изменённые файлы;
- команды проверки;
- обнаруженные ошибки;
- что пользователь должен добавить в VPS `.env`.
