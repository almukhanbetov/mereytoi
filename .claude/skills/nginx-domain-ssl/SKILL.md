---
name: nginx-domain-ssl
description: Настраивает отдельный Nginx virtual host и HTTPS для mereytoi.kz и www.mereytoi.kz, сохраняя остальные сайты VPS.
disable-model-invocation: true
---

# Nginx и HTTPS для Mereytoi

Домен:

```text
mereytoi.kz
www.mereytoi.kz
```

Upstreams:

```text
frontend: http://127.0.0.1:3000
backend:  http://127.0.0.1:8090
```

## Перед изменением

```bash
sudo nginx -T
sudo ls -la /etc/nginx/sites-enabled
sudo grep -R "server_name .*mereytoi.kz" -n /etc/nginx
curl -I http://127.0.0.1:3000
curl -i http://127.0.0.1:8090/health
```

Проверь, используют ли маршруты Go префикс `/api`.

## Конфигурация

Создай отдельный файл:

```text
/etc/nginx/sites-available/mereytoi.kz
```

Требования:

- `server_name mereytoi.kz www.mereytoi.kz`;
- `/` → frontend 3000;
- `/api/` → backend 8090;
- `/uploads/` → backend 8090;
- корректные proxy headers;
- `client_max_body_size` для uploads;
- не изменять default server и конфиги других доменов.

Важно:

- если backend ожидает `/api/...`, используй:
  ```nginx
  proxy_pass http://127.0.0.1:8090;
  ```
- если backend ожидает путь без `/api`, используй:
  ```nginx
  proxy_pass http://127.0.0.1:8090/;
  ```

Не угадывай — проверь routes в Go-коде.

## Безопасное применение

```bash
sudo ln -s /etc/nginx/sites-available/mereytoi.kz /etc/nginx/sites-enabled/mereytoi.kz
sudo nginx -t
```

Только при успешном `nginx -t`:

```bash
sudo systemctl reload nginx
```

## DNS и TLS

Перед Certbot проверь DNS:

```bash
dig +short mereytoi.kz
dig +short www.mereytoi.kz
```

Ожидаемый IP:

```text
89.207.255.212
```

После этого:

```bash
sudo certbot --nginx -d mereytoi.kz -d www.mereytoi.kz
sudo certbot renew --dry-run
```

## Финальная проверка

```bash
curl -I https://mereytoi.kz
curl -I https://www.mereytoi.kz
curl -i https://mereytoi.kz/api/health
sudo nginx -t
docker compose -f /var/www/mereytoi/docker-compose.yml ps
```

Покажи результат, но не показывай секреты.
