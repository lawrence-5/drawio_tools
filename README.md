# draw.io Color Mapping Editor

A single-file tool that runs entirely in your local browser. It edits light/dark text-color pairs and reports icons with explicit non-transparent backgrounds.

## How to use

1. Open `index.html` in a current version of Chrome, Edge, or Safari.
2. Drop a `.drawio` or `.xml` file onto the page.
3. Review the current light and dark values for each text color.
4. Select **Change mapping** for the mappings you want to edit. Nothing is selected automatically.
5. Edit the light and dark colors together. If needed, expand **Set per-page overrides** for page-specific pairs.
6. Review **Non-transparent icon backgrounds** to find icon cells with a visible `fillColor` or `imageBackground`.
7. Select **Generate new file**, then review the result in draw.io.

The tool does not upload files and never overwrites the original. Generated filenames use the `-color-mappings` suffix.

## Supported features

- Multi-page draw.io files
- Compressed and uncompressed draw.io XML
- Existing explicit `light-dark()` mappings
- Regular `fontColor` values
- CSS `color` and legacy `<font color="...">` in rich text
- Light/dark pairs for global mappings and per-page overrides
- Light- and dark-background previews with contrast warnings
- No automatic selections: unselected colors remain untouched
- Style-based reporting for image/stencil icons with explicit visible backgrounds

Compressed pages use the browser's native `CompressionStream` and `DecompressionStream` APIs.

The icon report checks draw.io cell styles. It does not inspect pixels inside embedded raster or SVG image data.
