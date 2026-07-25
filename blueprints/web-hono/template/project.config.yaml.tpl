schemaVersion: 1
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
  version: 0.1.0
