---
name: Lumina Prime
colors:
  surface: '#f9faf7'
  surface-dim: '#d9dad7'
  surface-bright: '#f9faf7'
  surface-container-lowest: '#ffffff'
  surface-container-low: '#f3f4f1'
  surface-container: '#edeeeb'
  surface-container-high: '#e7e8e6'
  surface-container-highest: '#e2e3e0'
  on-surface: '#191c1b'
  on-surface-variant: '#444932'
  inverse-surface: '#2e312f'
  inverse-on-surface: '#f0f1ee'
  outline: '#757a60'
  outline-variant: '#c5c9ac'
  surface-tint: '#536600'
  primary: '#536600'
  on-primary: '#ffffff'
  primary-container: '#d4ff00'
  on-primary-container: '#5f7400'
  inverse-primary: '#b0d500'
  secondary: '#5f5e5e'
  on-secondary: '#ffffff'
  secondary-container: '#e5e2e1'
  on-secondary-container: '#656464'
  tertiary: '#732ee4'
  on-tertiary: '#ffffff'
  tertiary-container: '#f4eaff'
  on-tertiary-container: '#8140f2'
  error: '#ba1a1a'
  on-error: '#ffffff'
  error-container: '#ffdad6'
  on-error-container: '#93000a'
  primary-fixed: '#caf300'
  primary-fixed-dim: '#b0d500'
  on-primary-fixed: '#171e00'
  on-primary-fixed-variant: '#3e4c00'
  secondary-fixed: '#e5e2e1'
  secondary-fixed-dim: '#c8c6c5'
  on-secondary-fixed: '#1c1b1b'
  on-secondary-fixed-variant: '#474646'
  tertiary-fixed: '#eaddff'
  tertiary-fixed-dim: '#d2bbff'
  on-tertiary-fixed: '#25005a'
  on-tertiary-fixed-variant: '#5a00c6'
  background: '#f9faf7'
  on-background: '#191c1b'
  surface-variant: '#e2e3e0'
typography:
  headline-xl:
    fontFamily: Syne
    fontSize: 40px
    fontWeight: '800'
    lineHeight: 48px
    letterSpacing: -0.02em
  headline-lg:
    fontFamily: Syne
    fontSize: 32px
    fontWeight: '700'
    lineHeight: 40px
    letterSpacing: -0.01em
  headline-lg-mobile:
    fontFamily: Syne
    fontSize: 28px
    fontWeight: '700'
    lineHeight: 34px
  title-md:
    fontFamily: Hanken Grotesk
    fontSize: 20px
    fontWeight: '600'
    lineHeight: 28px
  body-lg:
    fontFamily: Hanken Grotesk
    fontSize: 18px
    fontWeight: '400'
    lineHeight: 26px
  body-md:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '400'
    lineHeight: 24px
  label-caps:
    fontFamily: JetBrains Mono
    fontSize: 12px
    fontWeight: '500'
    lineHeight: 16px
    letterSpacing: 0.05em
  button-text:
    fontFamily: Hanken Grotesk
    fontSize: 16px
    fontWeight: '700'
    lineHeight: 20px
rounded:
  sm: 0.25rem
  DEFAULT: 0.5rem
  md: 0.75rem
  lg: 1rem
  xl: 1.5rem
  full: 9999px
spacing:
  base: 8px
  xs: 4px
  sm: 12px
  md: 24px
  lg: 40px
  xl: 64px
  gutter: 16px
  margin-mobile: 20px
  margin-desktop: 120px
---

## Brand & Style

The design system is engineered for the high-stakes world of property collaboration. It balances the high-energy "Vibrant Lime" of the real estate market with a "Deep Charcoal" anchor that communicates authority and institutional trust.

The aesthetic follows a **High-Contrast Modern** direction. It utilizes heavy ink-traps and bold weights from the typography to command attention, while maintaining a clean, systematic layout that ensures efficiency for power users. The visual mood is unapologetically professional—avoiding soft pastels in favor of a striking, monochromatic base punctuated by neon accents. This creates a "premium-official" atmosphere that feels both cutting-edge and dependable.

Key stylistic pillars:
- **Impactful Minimalism:** Using whitespace not just for breathing room, but as a structural tool to frame property assets.
- **Precision Engineering:** Sharp execution of components that mirror the reliability required in legal and financial property transactions.
- **Vibrant Functionalism:** Color is used sparingly but with high intent—specifically for action prompts and critical status indicators.

## Colors

The palette is built on extreme contrast ratios to ensure maximum legibility and brand recall.

- **Primary (Vibrant Lime):** Used exclusively for primary actions, success states, and key brand moments. It should never be used for long-form text.
- **Secondary (Deep Charcoal):** The foundation for surfaces, primary text, and high-emphasis containers. It provides the "official" weight to the system.
- **Tertiary (Electric Violet):** A secondary accent used for rare, high-priority callouts (e.g., "Featured" or "Hot Lead") to provide visual variety without diluting the primary brand color.
- **Neutral (Off-White/Bone):** The primary background color. It is warmer than pure white, reducing eye strain during long periods of appraisal and data entry.

**Color Roles:**
- **Surface-High:** `#121212` (Cards on light backgrounds)
- **Surface-Base:** `#F4F5F2` (Main App Background)
- **On-Primary:** `#000000` (Text/Icons on Lime buttons)
- **On-Secondary:** `#FFFFFF` (Text/Icons on Charcoal surfaces)

## Typography

This design system uses a triple-typeface strategy to distinguish between brand, content, and data.

1.  **Syne (Headlines):** Chosen for its aggressive, wide geometry. It provides the "Clash Display" look—bold, modern, and structural. Use this for page titles and major section headers.
2.  **Hanken Grotesk (Body):** A highly readable, professional sans-serif that handles long-form property descriptions and agent bios with clarity.
3.  **JetBrains Mono (Data Labels):** Used for "Metadata" (e.g., SQFT, Price/SQFT, Dates). The monospaced nature emphasizes the technical, "official" aspect of property data.

**Formatting Rules:**
- All `label-caps` should be transformed to Uppercase.
- `headline-xl` should use tight letter spacing to maintain a compact, "heavy" visual weight.
- Avoid using weights below 400 to maintain the high-contrast aesthetic.

## Layout & Spacing

The layout utilizes a **Strict 8pt Grid System**. All dimensions, padding, and margins must be multiples of 8px to ensure a rigid, professional structure.

**Mobile (Android Focus):**
- Use a 4-column fluid grid.
- Standard side margins are 20px.
- Card gutters are 16px.

**Desktop:**
- Use a 12-column fixed-center grid (max-width 1440px).
- Large 120px margins to create a "gallery" feel for property listings.

**Reflow Rules:**
- On mobile, lists of properties are single-column stacks.
- On tablet/desktop, property cards reflow into 2 or 3-column grids respectively.
- Navigation moves from a Bottom Nav Bar (Mobile) to a Left-hand Rail (Desktop) to maximize vertical space for property images.

## Elevation & Depth

Elevation in this design system is conveyed through **High-Contrast Layering** rather than traditional soft shadows.

- **Level 0 (Base):** Off-White background.
- **Level 1 (Cards):** Pure white surfaces with a very tight, dark shadow (0px 4px 12px rgba(0,0,0,0.05)). This keeps the UI feeling flat and modern.
- **Level 2 (Active/Floating):** Deep Charcoal surfaces. These appear to sit "above" the UI, used for snackbars, tooltips, or primary action cards.
- **Level 3 (Modals):** Full-screen overlays with a 40% opacity black backdrop.

**Shadow Character:**
Avoid diffused "glow" shadows. Shadows should be crisp and barely perceptible, serving only to separate white elements from the off-white background. For Charcoal elements, use a 1px interior border (rgba(255,255,255,0.1)) instead of a shadow to define depth.

## Shapes

The shape language is **Structured-Rounded**. While the system is professional, we use generous corner radii to keep the app feeling modern and accessible.

- **Standard Elements (Buttons, Inputs):** 8px (`0.5rem`).
- **Containers (Cards, Modals):** 16px (`1rem`).
- **Feature Elements:** 24px (`1.5rem`)—used for large image carousels or prominent property highlights.

Icons should follow a 2px stroke weight with slightly rounded terminals to match the `roundedness: 2` setting. Avoid sharp 90-degree corners on any interactive element.

## Components

### Buttons
- **Primary:** Vibrant Lime background, Black text. High-emphasis. Pill-shaped or Rounded (8px).
- **Secondary:** Deep Charcoal background, White text. Used for secondary actions or "Withdraw" style functions.
- **Outline:** 2px Charcoal border with transparent background. Used for tertiary actions.

### Cards
- Property cards must use a 16px corner radius. 
- The image should occupy the top 60% of the card.
- Metadata (Price, Location) should use `title-md` for the price and `label-caps` for the location.

### Input Fields
- **Default:** Off-white background with a 1px border (`#E0E0E0`).
- **Focus:** 2px Charcoal border. No "glow" effect.
- **Error:** 2px border using a high-visibility Red, but retaining the `label-caps` for error messages.

### Chips / Status Tags
- Status chips (e.g., "Available", "Sold") use the `label-caps` typography.
- "Available" uses a small Lime circle dot next to the text.

### Navigation (Android)
- Use a persistent Bottom Navigation bar with active states highlighted in Vibrant Lime. 
- Floating Action Buttons (FAB) should always be Vibrant Lime with a Black icon.