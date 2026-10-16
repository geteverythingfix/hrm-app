# HRM SaaS

This project is intended to be a multi-vendor SaaS application. Each customer has a unique subdomain, such as `acme.example.com`, that identifies its tenant.

The proposed technical design is in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). The `docs/` directory holds architecture and decision records.

The draft feature scope and acceptance criteria are in [SPEC.md](SPEC.md).

The PostgreSQL tables, relationships, ingestion flow, and monthly attendance model are in [docs/DATABASE.md](docs/DATABASE.md). The Prisma schema and first migration are in [`prisma/`](prisma/).

## Tenancy requirements

- Resolve the customer from the request hostname before serving customer data.
- Keep each customer's users and HRM records isolated from other customers.
- Reject unknown or inactive customer subdomains.
- Reserve the base domain and operational subdomains so they cannot be assigned to customers.
- Make tenant resolution and data isolation part of the automated tests when the application framework is introduced.

The selected stack is Nuxt, Nuxt UI, Prisma, and PostgreSQL. The draft first release covers permission-based access, ZKTeco ADMS attendance ingestion, daily and monthly attendance views, and supervisor adjustments. Device-discovered people become provisional users without login access until verified. The base domain and device-specific protocol details remain open.

## Local database

A project-local PostgreSQL 17 cluster was initialized in ignored `.local/postgres`, and the `hrm_dev` database was created. The first migration was applied using PostgreSQL single-user mode because this task's restricted shell cannot open TCP or Unix sockets. An ignored `.env` contains separate database-owner (`DIRECT_URL`) and restricted application (`DATABASE_URL`) credentials. Keep that file private. The `hrm_app` role has tenant-table grants, with raw logs updateable only for `user_id` attribution; adjustment and audit tables are append-only to this role.

To run the existing cluster in a normal WSL shell with socket access:

```bash
/usr/lib/postgresql/17/bin/pg_ctl -D .local/postgres -l .local/postgres.log start
/usr/lib/postgresql/17/bin/pg_ctl -D .local/postgres stop
```

It listens on `127.0.0.1:5433` and puts its Unix socket in `.local/run`. Keep the project directory available while it runs. `pg_isready -h 127.0.0.1 -p 5433` checks readiness.

When npm registry access is available, finish the Prisma setup from the project root:

```bash
npm install
npx prisma validate
npx prisma migrate resolve --applied 20261016130000_initial
npm run db:status
npm run db:generate
```

`migrate resolve` records the already-applied first migration in Prisma's migration history. Run it **once** on this existing `hrm_dev` database. For a fresh empty database elsewhere, use `npm run db:deploy` instead. Future schema changes use `npm run db:migrate` in development and `npm run db:deploy` for deployment. Prisma 7 requires explicit client generation after migration. The runtime adapter and `withTenant` transaction helper are in [`src/server/db/client.ts`](src/server/db/client.ts); resolve the tenant from the host before calling it.

This repository has not yet been scaffolded as a Nuxt app, so there is no app `dev`, `build`, or test command. npm package installation and Prisma CLI validation were blocked here by DNS failure for `registry.npmjs.org`; the SQL migration was applied and smoke-tested directly with PostgreSQL. Row-level security policy behavior must be retested under a normal PostgreSQL server session, since single-user mode bypasses it.
