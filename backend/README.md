# MEREYTOI Backend

Go + Gin + GORM + PostgreSQL API for the MEREYTOI event-agency site.

## Stack

- Gin (HTTP router)
- GORM + `gorm.io/driver/postgres` (ORM, auto-migrations)
- `golang-jwt/jwt/v5` + bcrypt (auth)
- PostgreSQL 17 (via Docker Compose, database `mereytoi_db`)

## Database schema

- **users** — `id, name, email, phone, password_hash, role, created_at, updated_at`
- **categories** — `id, slug, name_ru, name_kz, position` — seeded with the 5 fixed categories:
  1. `venues` — Рестораны и локации
  2. `hosts` — Ведущие
  3. `shows` — Шоу-программы
  4. `artists` — Артисты и исполнители
  5. `stars` — Звёзды эстрады
- **listings** — the entries inside each category (restaurant names, host names, etc.): `id, category_id, name_ru, name_kz, description_ru, description_kz, city, phone, price, rating, emoji, color_from, color_to, is_active`

Categories and a handful of example listings are seeded automatically on first run (`internal/seed/seed.go`), skipped if the categories table isn't empty.

## Run locally

```bash
# 1. start Postgres (from the repo root, one level up)
docker compose up -d db

# 2. configure env
cp .env.example .env

# 3. run the API
go run ./cmd/server
```

API listens on `http://localhost:8090` by default (`PORT` in `.env`).

## Endpoints

| Method | Path | Auth | Description |
|---|---|---|---|
| GET | `/api/health` | – | health check |
| POST | `/api/auth/register` | – | create a user, returns JWT |
| POST | `/api/auth/login` | – | returns JWT |
| GET | `/api/auth/me` | Bearer | current user |
| GET | `/api/categories` | – | list the 5 categories |
| GET | `/api/categories/:slug` | – | single category |
| GET | `/api/listings?category=slug&search=term` | – | list/filter listings |
| GET | `/api/listings/:id` | – | single listing |
| POST | `/api/listings` | Bearer, role=admin | create listing |
| PUT | `/api/listings/:id` | Bearer, role=admin | update listing |
| DELETE | `/api/listings/:id` | Bearer, role=admin | delete listing |

New users get `role=user`; promote to `admin` directly in the database to manage listings:

```sql
UPDATE users SET role = 'admin' WHERE email = 'you@example.com';
```
