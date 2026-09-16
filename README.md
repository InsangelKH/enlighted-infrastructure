# Enlighted Infrastructure

Local dev infrastructure for the Allegedly Enlightened storefront backend: the
`docker-compose.yml` that wires Postgres + the service repos together, and the Postgres
bootstrap scripts (roles, extensions). No application code lives here.

Deliberately kept separate from the service repos so that service logic and infra don't mix —
each service repo (`enlighted-api`, `enlighted-products`, `enlighted-users`,
`enlighted-migrations`) owns only its own `Dockerfile`.

## Layout

```
docker-compose.yml    db + migrations + app services
postgres/init/         Postgres docker-entrypoint-initdb.d scripts (roles, extension)
.env.example           role passwords consumed by docker-compose.yml
```

## Prerequisites

Checked out as a sibling of the service repos:

```
enlighted/
├── enlighted-api/
├── enlighted-products/
├── enlighted-users/
├── enlighted-migrations/
└── infrastructure/   (this repo)
```

## Running

```bash
cp .env.example .env
docker compose up --build
```

This starts five services:

- **`db`** — Postgres 16. On first boot against an empty `pgdata` volume, it runs
  [`postgres/init/01-roles.sh`](postgres/init/01-roles.sh), which installs the `uuid-ossp`
  extension and creates the three Postgres roles below.
- **`migrations`** — built from [`../enlighted-migrations`](../enlighted-migrations). Waits
  for `db` to report healthy, connects as `app_admin`, applies SQL migrations then seed data,
  and exits. Safe to re-run.
- **`products`** — built from [`../enlighted-products`](../enlighted-products). Connects as
  `app_readonly`, owns the catalog domain logic, and only starts once `migrations` has exited
  successfully (`service_completed_successfully`). Exposes a gRPC API, internal to the compose
  network only (no host port mapping).
- **`users`** — built from [`../enlighted-users`](../enlighted-users). Connects as
  `app_readwrite`, owns auth (registration/login/JWT) and per-user carts, and calls `products`
  over gRPC to validate/price cart items. Only starts once `migrations` has exited
  successfully. Exposes a gRPC API, internal to the compose network only.
- **`app`** — built from [`../enlighted-api`](../enlighted-api). The public HTTP API gateway —
  no database access of its own, talks to `products` and `users` over gRPC, and verifies JWT
  access tokens locally via the shared `JWT_SECRET`. Only starts once `products` and `users`
  have started.

The API is then available at `http://localhost:8000`.

If you have a `pgdata` volume from before these roles existed, `docker compose down -v` first
so the init script actually runs.

## Database roles

`enlighted-products` and `enlighted-users` touch Postgres directly; access is scoped per
service with least privilege in mind:

| Role            | Used by                | Privileges                                                                   |
| --------------- | ----------------------- | ----------------------------------------------------------------------------- |
| `app_admin`     | `enlighted-migrations`  | `CREATE`/`USAGE` on schema `public`; owns tables it creates (full DDL + DML) |
| `app_readwrite` | `enlighted-users`       | `SELECT, INSERT, UPDATE, DELETE` on all tables, granted automatically       |
| `app_readonly`  | `enlighted-products`    | `SELECT` on all tables, granted automatically                               |

`app_readwrite` and `app_readonly` get their table privileges via
`ALTER DEFAULT PRIVILEGES FOR ROLE app_admin IN SCHEMA public ...`, set once in
`01-roles.sh`. Because migrations always run as `app_admin`, any table a future migration
creates is automatically readable by `app_readonly` and read-writable by `app_readwrite` —
no per-table `GRANT` needed in migration files.

`enlighted-api` (the gateway) never connects to Postgres — it only talks gRPC to `products`
and `users`.

Role passwords come from `APP_ADMIN_PASSWORD` / `APP_READWRITE_PASSWORD` /
`APP_READONLY_PASSWORD` (see `.env.example`). The checked-in defaults are dev-only — override
them for anything beyond local development, and keep them in sync with each service repo's own
`.env` (`enlighted-products`'s `DATABASE_URL` embeds `APP_READONLY_PASSWORD`,
`enlighted-users`'s embeds `APP_READWRITE_PASSWORD`, `enlighted-migrations`'s embeds
`APP_ADMIN_PASSWORD`). `JWT_SECRET` must likewise match between `enlighted-users` (which signs
access tokens) and `enlighted-api` (which verifies them locally).
