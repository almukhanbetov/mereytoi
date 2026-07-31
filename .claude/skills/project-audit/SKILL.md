---
name: project-audit
description: Аудитирует monorepo Mereytoi с frontend Next.js, backend Go и Docker. Использовать перед изменением Dockerfile, docker-compose, CI/CD, Nginx или production-конфигурации.
---

# Аудит проекта Mereytoi

Работай из корня репозитория.

## Цель

Перед изменениями определить реальную структуру проекта и не делать предположений о путях, портах, командах сборки и переменных окружения.

## Обязательный порядок

1. Покажи текущую директорию и структуру:
   ```bash
   pwd
   find . -maxdepth 3 -type f | sort
   ```

2. Проверь Git:
   ```bash
   git status --short
   git branch --show-current
   git remote -v
   find . -maxdepth 3 -type d -name .git
   ```

3. Проверь backend:
   ```bash
   find backend -maxdepth 4 -type f | sort
   cat backend/go.mod
   find backend/cmd -maxdepth 3 -type f -name '*.go' -print
   grep -R "PORT\|DATABASE_URL\|Run(" -n backend --exclude-dir=.git
   ```

4. Проверь frontend:
   ```bash
   cat frontend/package.json
   cat frontend/next.config.mjs 2>/dev/null || true
   grep -R "NEXT_PUBLIC_\|localhost:8090\|localhost:8080" -n frontend/src frontend/app 2>/dev/null || true
   ```

5. Проверь контейнеризацию:
   ```bash
   find . -maxdepth 3 \( -name 'Dockerfile' -o -name 'docker-compose*.yml' -o -name '.dockerignore' \) -print
   docker compose config 2>/dev/null || true
   ```

6. Проверь существующий CI/CD:
   ```bash
   find .github -maxdepth 3 -type f -print 2>/dev/null || true
   ```

## Правила

- Не удаляй рабочие настройки без необходимости.
- Не выводи значения `.env`, приватных ключей, токенов и паролей.
- Не меняй код до завершения аудита.
- После аудита дай краткий отчёт:
  - фактический entrypoint backend;
  - порт backend;
  - команда сборки frontend;
  - используемые env-переменные;
  - найденные Docker/CI файлы;
  - риски и точный план изменений.
