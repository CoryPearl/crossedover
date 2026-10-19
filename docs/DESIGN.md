# Interface

crossedover uses a monochrome shell with original game artwork. Keep the library quiet: installed games, one primary action per game, and ample room around the content. TrackMania remains the first tested demo; other games are labeled with untested compatibility.

## Layout

The 196-point sidebar owns navigation and the Windows Steam launcher. The main pane uses 32-point side gutters; the library, page heading, and rules expand with the window. Settings forms retain a 940-point reading width. Native window controls retain their own space above the sidebar wordmark.

Game cards separate 112-point artwork and compact game details from their action footers. All installed games, including a single title, use the same adaptive grid with columns between 250 and 320 points and 16-point gaps. More columns fit as the window expands; cards do not become oversized. List mode uses compact artwork, a title, session/storage details, and trailing controls in 88-point rows. Play is the filled primary button; the outlined ellipsis menu retains properties, file access, verification, and uninstall. Steam stays in the sidebar. Only the active game displays its session status.

Settings uses bordered groups with consistent rows and trailing controls. Recovery and runtime tools stay in Advanced. Activity uses separated rows. Notices and progress appear at the bottom of the main pane, outside the scrolling content.

The library toolbar provides live title search and a grid/list selector. Search ignores case, accents, and surrounding whitespace. The clear button and Escape clear the query; Command-F focuses search from any page. Clicking elsewhere in the app window dismisses search focus without clearing its text or consuming the click. A no-results state preserves the toolbar and offers Clear search. The view preference persists across launches; filtering does not change game discovery or session tracking.

## Visual rules

- Neutral surfaces at 6.5%, 8.5%, and 10.5% white; restrained 21% white borders.
- One-point panel outlines, eight-point panel corners, six-point control corners.
- Buttons and menu labels share a 34-point height.
- Page titles are 25 points; normal labels are 12 points. Secondary copy uses muted gray.
- Game logos retain their original colors, with a light artwork mat for legibility.
- Keep native alerts, confirmation dialogs, keyboard shortcuts, scrolling, and window controls.

## Visual checks

The app can render its own SwiftUI content without starting Steam or changing interrupted-operation records:

```sh
.build/release/CrossedOver --render-preview /tmp/library.png
.build/release/CrossedOver --render-preview /tmp/compact.png --compact-preview
.build/release/CrossedOver --render-preview /tmp/settings.png --preview-page settings
.build/release/CrossedOver --render-preview /tmp/advanced.png --preview-page settings --preview-advanced --tall-preview
.build/release/CrossedOver --render-preview /tmp/running.png --compact-preview --preview-state running
```

Preview states include `setup`, `install`, `running`, `unknown`, `busy`, and `notice`; these change only the preview model. `--preview-games /path/to/fixture.json` supplies a JSON array of `GameInstallation` values to inspect larger libraries without installing games or editing real Steam manifests. Set `CROSSEDOVER_DATA_ROOT` to an empty temporary directory to check first launch or empty Activity. The standard sizes are 1100 × 760 and 840 × 620. `--preview-width` and `--preview-height` allow wide-window checks; `--preview-layout grid|list` and `--preview-search "title"` exercise presentation and filtering without changing the saved view preference. Tall previews expose expanded content that normally scrolls.

ImageRenderer substitutes static menu labels and a progress symbol for native controls that cannot render offscreen. These images verify composition, spacing, and state presentation; they do not verify menu interaction, keyboard focus, title-bar placement, or live scrolling.


## Application icon

Build 13 uses an original vector branch mark with two outward diagonal arrowheads and a rounded shared stem. It follows the direction and visual weight of the sidebar’s branch symbol. The warm-white silhouette sits on a charcoal rounded square with a restrained edge and generous insets. The generator produces every standard macOS icon size from one 1024-pixel drawing; small-size legibility is visually checked. No SF Symbol artwork is embedded in the app icon.


## Wordmark

Use **crossedover**, all lowercase, as one word in product-facing text, the app display name, and distribution filenames. The wordmark uses the existing compact semibold typography and branch icon. Internal executable, bundle, and data identifiers keep their established names.
