spring:
  application:
    name: api-spring-postgres
  datasource:
    url: ${DB_URL:jdbc:postgresql://localhost:5432/app}
    username: ${DB_USERNAME:postgres}
    password: ${DB_PASSWORD:}
  flyway:
    enabled: true
    locations: classpath:db/migration
  mvc:
    throw-exception-if-no-handler-found: true
  web:
    resources:
      add-mappings: false

mybatis:
  configuration:
    map-underscore-to-camel-case: true

server:
  port: 8080
