# DESIGN.md

Japanese reference: [`docs/ja-JP/DESIGN-ja.md`](docs/ja-JP/DESIGN-ja.md)

## API design

- Keep the starter API intentionally small and product-neutral.
- Use `/internal/**` for application-internal endpoints.
- Use `/api/v1/**` when a future API becomes externally consumed.
- Return RFC 7807 Problem Details for errors.
- Use PostgreSQL through MyBatis and manage schema migrations with Flyway.
- Do not add fictional business models, mappers, services, migrations, or
  fixtures.

## Operations

- Keep `/internal/health` fast and independent from optional infrastructure.
- Build one executable Spring Boot JAR.
- Keep Unit Tests independent from Database and Docker.
- Run `e2eTest` explicitly; do not connect it to `check`.
- Use root pnpm commands as the repository interface and keep Gradle Wrapper as
  the Spring build system.
