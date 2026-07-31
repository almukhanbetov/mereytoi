---
name: vps-deploy
description: Подготавливает VPS Ubuntu для безопасного Docker Compose deploy Mereytoi по SSH на порту 22122 без повреждения других сайтов.
disable-model-invocation: true
---

# Подготовка VPS Mereytoi

Целевой сервер:

```text
ssh -p 22122 merey@89.207.255.212
/var/www/mereytoi
```

## Главный принцип

Не ломай другие сайты и контейнеры на VPS.

Перед изменениями выполни только read-only проверки:

```bash
hostname
whoami
pwd
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}'
docker compose version
sudo ss -tulpn
sudo nginx -T 2>/dev/null | sed -n '1,240p'
sudo ls -la /etc/nginx/sites-enabled /etc/nginx/sites-available
```

## Подготовка каталога

```bash
sudo mkdir -p /var/www/mereytoi/backend
sudo chown -R merey:merey /var/www/mereytoi
chmod 750 /var/www/mereytoi
```

Не меняй владельца `/var/www` целиком.

## Production env

Создай вручную на VPS:

```text
/var/www/mereytoi/.env
/var/www/mereytoi/backend/.env
```

Права:

```bash
chmod 600 /var/www/mereytoi/.env
chmod 600 /var/www/mereytoi/backend/.env
```

Не показывай содержимое секретов в отчёте.

Проверь только имена переменных:

```bash
sed -E 's/=.*/=<hidden>/' /var/www/mereytoi/.env
sed -E 's/=.*/=<hidden>/' /var/www/mereytoi/backend/.env
```

## Docker access

Проверь:

```bash
docker ps
```

Если у `merey` нет доступа, предложи:

```bash
sudo usermod -aG docker merey
```

Объясни, что после этого нужен новый SSH-сеанс.

## Первый deploy

```bash
cd /var/www/mereytoi
docker compose config
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
```

Проверка:

```bash
curl -fsS http://127.0.0.1:3000/ >/dev/null
curl -fsS http://127.0.0.1:8090/health || curl -fsS http://127.0.0.1:8090/
```

## Запрещено

- удалять чужие контейнеры;
- выполнять `docker system prune -a`;
- удалять volumes;
- менять UFW без проверки действующего SSH-порта;
- открывать PostgreSQL наружу;
- публиковать 3000/8090 на `0.0.0.0`;
- перезаписывать чужие Nginx-конфиги.
