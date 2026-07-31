---
name: github-actions-dockerhub
description: Создаёт безопасный GitHub Actions workflow для сборки frontend/backend, публикации в Docker Hub и деплоя Mereytoi на VPS.
disable-model-invocation: true
---

# GitHub Actions: Docker Hub + VPS

Параметры проекта:

```text
VPS_HOST=89.207.255.212
VPS_PORT=22122
VPS_USER=merey
VPS_PATH=/var/www/mereytoi
DOMAIN=mereytoi.kz
```

Не записывай реальные секреты в workflow.

## Ожидаемые GitHub Secrets

```text
DOCKERHUB_USERNAME
DOCKERHUB_TOKEN
VPS_HOST
VPS_PORT
VPS_USER
VPS_PATH
VPS_SSH_KEY
```

## Workflow

Создай `.github/workflows/deploy.yml`.

Требования:

1. Trigger:
   - push в `main`;
   - `workflow_dispatch`.

2. Permissions:
   - минимальные, `contents: read`.

3. Build:
   - checkout;
   - Docker Buildx;
   - login в Docker Hub;
   - build/push backend;
   - build/push frontend;
   - два тега:
     - `${{ github.sha }}`;
     - `latest`;
   - frontend build arg:
     `NEXT_PUBLIC_API_URL=https://mereytoi.kz/api`;
   - GitHub Actions cache отдельно для frontend/backend.

4. Deploy:
   - выполняется только после успешного build;
   - SSH на `${VPS_HOST}:${VPS_PORT}`;
   - ключ писать через `printf`, права `600`;
   - `ssh-keyscan` для known_hosts;
   - копировать только production compose и необходимые deployment-файлы;
   - на VPS:
     ```bash
     cd /var/www/mereytoi
     docker compose pull
     docker compose up -d --remove-orphans
     docker compose ps
     ```
   - выполнять health checks;
   - при ошибке workflow должен завершаться с ошибкой;
   - не применять `docker system prune -a`;
   - не удалять volumes;
   - не печатать секреты.

5. Rollback:
   - сохранять SHA-теги;
   - compose должен поддерживать `IMAGE_TAG`;
   - документировать команду отката:
     ```bash
     IMAGE_TAG=<previous_sha> docker compose up -d
     ```

## Проверка до commit

```bash
git diff --check
docker compose config
```

Проверь YAML и пути. Не запускай push без прямой просьбы пользователя.

## Финальный отчёт

Покажи:

- список Secrets без значений;
- какие Docker Hub repositories нужны;
- файлы, созданные workflow;
- точную команду commit/push;
- как открыть GitHub Actions и проверить job.
