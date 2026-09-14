#!/usr/bin/env bash
set -euo pipefail

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_admin') THEN
            CREATE ROLE app_admin LOGIN PASSWORD '${APP_ADMIN_PASSWORD}';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readwrite') THEN
            CREATE ROLE app_readwrite LOGIN PASSWORD '${APP_READWRITE_PASSWORD}';
        END IF;
        IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'app_readonly') THEN
            CREATE ROLE app_readonly LOGIN PASSWORD '${APP_READONLY_PASSWORD}';
        END IF;
    END
    \$\$;

    GRANT CONNECT ON DATABASE "$POSTGRES_DB" TO app_admin, app_readwrite, app_readonly;
    GRANT CREATE ON DATABASE "$POSTGRES_DB" TO app_admin;

    GRANT CREATE, USAGE ON SCHEMA public TO app_admin;
    GRANT USAGE ON SCHEMA public TO app_readwrite, app_readonly;

    ALTER DEFAULT PRIVILEGES FOR ROLE app_admin IN SCHEMA public
        GRANT SELECT ON TABLES TO app_readonly;
    ALTER DEFAULT PRIVILEGES FOR ROLE app_admin IN SCHEMA public
        GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_readwrite;
EOSQL
