schemaVersion: 2
project:
  id: __PROJECT_ID__
  displayName: "__PROJECT_DISPLAY_NAME_YAML__"
branchStrategy:
  default: main
  integration: develop
systems:
  - id: web-frontend
    type: react-vite
    port: 5173
  - id: api-bff
    type: hono
    port: 3000
bootstrapper:
  source: rukaruka966/ibuki-bootstrapper
  blueprint: web-hono
  version: __BOOTSTRAPPER_VERSION__
  commit: __BOOTSTRAPPER_COMMIT__
