/**
 * Tailwind CSS plugin for custom SVG icons.
 *
 * This plugin scans the `assets/icons/` directory for SVG files and generates
 * CSS utility classes like `custom-git-branch` that can be used with the
 * `<.icon name="custom-git-branch" />` component.
 *
 * ## Usage
 *
 * 1. Add SVG files to `assets/icons/` (e.g., `git-branch.svg`)
 * 2. Reference them in templates: `<.icon name="custom-git-branch" class="size-5" />`
 *
 * ## How it works
 *
 * Each SVG is inlined as a CSS mask, allowing the icon to inherit the current
 * text color via `background-color: currentColor`. This works identically to
 * the heroicons implementation.
 */
const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function({matchComponents, theme}) {
  // Directory containing custom SVG icons
  let iconsDir = path.join(__dirname, "../icons")
  let values = {}

  // Scan icons directory and build a map of icon names to file paths
  if (fs.existsSync(iconsDir)) {
    fs.readdirSync(iconsDir).forEach(file => {
      if (file.endsWith(".svg")) {
        let name = path.basename(file, ".svg")
        values[name] = {name, fullPath: path.join(iconsDir, file)}
      }
    })
  }

  // Register the `custom-` prefix for icon classes
  matchComponents({
    "custom": ({name, fullPath}) => {
      // Read SVG and inline it as a data URL
      let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")
      content = encodeURIComponent(content)
      return {
        [`--custom-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
        "-webkit-mask": `var(--custom-${name})`,
        "mask": `var(--custom-${name})`,
        "-webkit-mask-size": "contain",
        "mask-size": "contain",
        "-webkit-mask-repeat": "no-repeat",
        "mask-repeat": "no-repeat",
        "background-color": "currentColor",
        "vertical-align": "middle",
        "display": "inline-block"
      }
    }
  }, {values})
})