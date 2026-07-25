{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "lib": [
      "ES2023"
    ],
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "outDir": "dist",
    "rootDir": "src",
    "types": [
      "node",
      "vitest/globals"
    ]
  },
  "include": [
    "src"
  ],
  "exclude": [
    "src/**/*.test.ts"
  ]
}
