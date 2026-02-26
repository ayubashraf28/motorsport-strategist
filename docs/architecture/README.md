# architecture

Use this folder for high-value technical documents:

- component boundaries and responsibilities
- runtime/data flow diagrams
- performance and reliability constraints
- integration points and external dependencies

Current docs:
- `racing-manager-v0.md`: v0 simulation/presentation boundaries and fixed-step runtime flow
- `racing-manager-v1.md`: v1 pace profile architecture, smoothing behavior, and debug visualization flow
- `racing-manager-v1.1.md`: v1.1 geometry asset loading, curvature model, and physics speed profile flow

Key architectural decisions in V3.2:
- **TrackView layer separation**: all track geometry nodes (path, line, overlays, cars) wrapped in a single `TrackView` Node2D; HUD lives on an independent `CanvasLayer`. This allows rotating/scaling the track without affecting UI.
- **Auto-fit algorithm**: tracks auto-rotate (0° vs 90°) and scale to best fill available viewport area, making all circuits display correctly without manual positioning.
- **Game flow via autoload**: `GameState` singleton carries config between scenes (menu → setup → race → results), avoiding global state pollution.
- **F1-style timing tower**: single cycling data column replaces multi-column spreadsheet HUD, scaling to any grid size.
