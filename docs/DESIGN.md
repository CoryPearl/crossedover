# Interface

CrossedOver uses a monochrome shell with original game artwork. Keep the library quiet: one supported demo, one primary game action, and ample room around the content.

## Layout

The 196-point sidebar owns navigation and the Windows Steam launcher. The main pane uses 40-point side gutters and a shared content width of up to 940 points. Page headings, rules, cards, and form sections align to that grid. Native window controls retain their own space above the sidebar wordmark.

The TrackMania card separates artwork and game details from its action footer. At narrower widths it stacks vertically. Play is the filled primary button; Manage is an outlined menu. Steam stays in the sidebar. Installation, setup, and running states use the same card geometry.

Settings uses bordered groups with consistent rows and trailing controls. Recovery and runtime tools stay in Advanced. Activity uses separated rows. Notices and progress appear at the bottom of the main pane, outside the scrolling content.

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

Preview states include `setup`, `install`, `running`, `busy`, and `notice`; these change only the preview model. Set `CROSSEDOVER_DATA_ROOT` to an empty temporary directory to check first launch or empty Activity. The standard sizes are 1100 × 760 and 840 × 620. Tall previews expose expanded content that normally scrolls.

ImageRenderer substitutes static menu labels and a progress symbol for native controls that cannot render offscreen. These images verify composition, spacing, and state presentation; they do not verify menu interaction, keyboard focus, title-bar placement, or live scrolling.
