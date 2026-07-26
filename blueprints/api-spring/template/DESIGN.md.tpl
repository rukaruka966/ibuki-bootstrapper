# DESIGN.md

Japanese reference: [`docs/ja-JP/DESIGN-ja.md`](docs/ja-JP/DESIGN-ja.md)

## API design

- Keep the starter API intentionally small and product-neutral.
- Use `/internal/**` for application-internal endpoints.
- Use `/api/v1/**` when a future API becomes externally consumed.
- Return RFC 7807 Problem Details for errors.
- Avoid persistence and authentication decisions in the starter.

## Operations

- Keep `/internal/health` fast and independent from optional infrastructure.
- Build one executable Spring Boot JAR.
