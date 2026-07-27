schemaVersion: 1
project:
  id: __PROJECT_ID__
  displayName: "__PROJECT_DISPLAY_NAME_YAML__"
  basePackage: __BASE_PACKAGE__
branchStrategy:
  default: main
  integration: develop
systems:
  - id: api-server
    type: spring-boot-postgresql
    port: 8080
bootstrapper:
  version: __BOOTSTRAPPER_VERSION__
