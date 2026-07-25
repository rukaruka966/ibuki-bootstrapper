:root {
  color-scheme: light dark;
  font-family:
    Inter, "Noto Sans JP", system-ui, -apple-system, BlinkMacSystemFont,
    "Segoe UI", sans-serif;
  font-synthesis: none;
  text-rendering: optimizeLegibility;
}

* {
  box-sizing: border-box;
}

body {
  min-width: 320px;
  margin: 0;
}

main {
  width: min(100% - 2rem, 72rem);
  margin-inline: auto;
  padding-block: 4rem;
}

h1 {
  margin: 0;
  font-size: clamp(2rem, 6vw, 4rem);
  line-height: 1.1;
}

:focus-visible {
  outline: 0.2rem solid Highlight;
  outline-offset: 0.2rem;
}

@media (prefers-reduced-motion: reduce) {
  *,
  *::before,
  *::after {
    scroll-behavior: auto !important;
    transition-duration: 0.01ms !important;
    animation-duration: 0.01ms !important;
    animation-iteration-count: 1 !important;
  }
}
