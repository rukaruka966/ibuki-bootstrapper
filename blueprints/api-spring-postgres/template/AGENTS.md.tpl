# AGENTS.md

Japanese reference: [`docs/ja-JP/AGENTS-ja.md`](docs/ja-JP/AGENTS-ja.md)

## Project

- ID: `__PROJECT_ID__`
- Display name: `__PROJECT_DISPLAY_NAME__`
- Base package: `__BASE_PACKAGE__`
- Runtime: JDK 17
- Framework: Kotlin and Spring Boot 4.1.0
- Persistence: PostgreSQL, MyBatis Dynamic SQL, and Flyway
- Build tool: Gradle Wrapper

## Commands

Run repository quality tasks through the Gradle Wrapper:

```powershell
Set-Location ./systems/api-server
.\gradlew.bat check
.\gradlew.bat bootJar
.\gradlew.bat e2eTest
```

## API conventions

- Internal endpoints use `/internal/**`.
- Future public endpoints use `/api/v1/**`.
- API errors use RFC 7807 Problem Details.

## Development rules

- Keep the application compatible with JDK 17.
- Keep text UTF-8 without BOM and use LF line endings.
- Add tests for endpoint behavior and important failure paths.
- Keep business models, mappers, services, migrations, and fixtures out of the
  scaffold until an explicit requirement exists.
- Keep Unit Tests independent from Database and Docker. Run `e2eTest` explicitly
  with Docker Desktop in Linux container mode.
- Never write secrets or local absolute paths.

## Definition of Done

- `gradlew.bat check` and `gradlew.bat bootJar` pass.
- `gradlew.bat e2eTest` passes when E2E tests exist and Docker is available.
- Unknown routes return RFC 7807 Problem Details.
- Documentation matches changed commands and contracts.
