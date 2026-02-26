# ui-ux

UI/UX working standards for the project.

Include:
- information architecture and user flows
- component behavior rules and accessibility constraints
- visual system decisions (spacing, typography, color roles)
- interaction states (default, hover, focus, disabled, loading, error)

## Current UI Architecture (V3.2)

### Game Flow
Main Menu → Race Setup (track/team selection) → Race → Results

### Race HUD Design — F1-Style Timing Tower

Inspired by F1 Manager games. Key design principles:
- **One data column at a time**: instead of cramming all data into a spreadsheet, a single right-aligned data column cycles through modes (INTERVAL, LAST LAP, TYRE, FUEL) via arrow buttons.
- **Left-side timing tower**: compact vertical panel with semi-transparent dark background (`rgba(0.08, 0.09, 0.12, 0.88)`, 6px rounded corners).
- **Bottom status bar**: full-width strip showing race state, time controls, and post-race navigation.
- **Visual hierarchy**: position numbers and gaps use subdued colors; driver names use team colors for instant identification.
- **Auto-sizing**: tower height adjusts to the actual car count rather than a fixed size.

### Row Layout
`Position | Color Bar | Driver Code | Data Value | [Pit Button]`

### Data Modes (Cycled via `<` / `>`)
| Mode | Content | Color Rule |
|------|---------|------------|
| INTERVAL | Gap to car ahead in seconds | Subdued gray |
| LAST LAP | Last completed lap time | Subdued gray |
| TYRE | Compound letter + life % | Compound color (S=red, M=yellow, H=white) |
| FUEL | Remaining fuel in kg | Red when <15% capacity |

### Track Presentation
- Track geometry rendered on a `TrackView` Node2D, separate from the HUD `CanvasLayer`.
- Auto-fit algorithm rotates (0° or 90°) and scales tracks to fill the viewport area to the right of the timing tower.
- All 5 circuits display correctly without manual positioning.
