# NEXUS — Flutter Conversion Reference
### Complete Design Specification for AI-Assisted Development

---

## TABLE OF CONTENTS

1. [App Overview](#1-app-overview)
2. [Design Tokens — Colors](#2-design-tokens--colors)
3. [Design Tokens — Typography](#3-design-tokens--typography)
4. [Design Tokens — Shadows & Elevation](#4-design-tokens--shadows--elevation)
5. [Design Tokens — Border Radii](#5-design-tokens--border-radii)
6. [Design Tokens — Spacing](#6-design-tokens--spacing)
7. [App Architecture & Navigation](#7-app-architecture--navigation)
8. [Global Background & Body](#8-global-background--body)
9. [Component: Topbar](#9-component-topbar)
10. [Component: Globe Hero (Canvas)](#10-component-globe-hero-canvas)
11. [Component: Hero Label](#11-component-hero-label)
12. [Component: Pill Toggle (Tab Bar)](#12-component-pill-toggle-tab-bar)
13. [Screen: Setup](#13-screen-setup)
14. [Screen: Scan](#14-screen-scan)
15. [Screen: Results](#15-screen-results)
16. [Component: Detail Sheet (Slide-in)](#16-component-detail-sheet-slide-in)
17. [Component: Filter Panel (Bottom Sheet)](#17-component-filter-panel-bottom-sheet)
18. [Component: Bottom Dock (Navigation Bar)](#18-component-bottom-dock-navigation-bar)
19. [Animations & Motion](#19-animations--motion)
20. [Data Models](#20-data-models)
21. [State Management](#21-state-management)
22. [Platform Notes](#22-platform-notes)

---

## 1. APP OVERVIEW

**App Name:** NEXUS  
**Purpose:** Web3 job scanner — user uploads a company list, the app scrapes career pages and surfaces job openings.  
**Target:** Mobile-first, max width 390px, iOS & Android.  
**Aesthetic:** Clay morphism / soft 3D. Warm orange-dominant palette. Soft shadows with depth cues. Bouncy spring animations.

**Three Main Screens (tab-based):**
1. **Setup** — Upload file, set include/exclude keyword filters, initiate scan
2. **Scan** — Live progress arc, metrics, scrolling log feed
3. **Results** — Horizontal snap carousel of job cards + detail sheet

---

## 2. DESIGN TOKENS — COLORS

### Primary Palette (define as `const` in a `AppColors` class)

```dart
class AppColors {
  // Backgrounds
  static const bg       = Color(0xFFFFF8F4);   // warm off-white — page background
  static const bgSoft   = Color(0xFFFFEEE4);   // slightly deeper warm — secondary bg
  static const white    = Color(0xFFFFFFFF);   // pure white — card surfaces

  // Text
  static const ink      = Color(0xFF1A0F08);   // near-black warm — primary text
  static const inkSoft  = Color(0xFF3D2215);   // dark brown — secondary text
  static const muted    = Color(0xFFA07060);   // warm gray-brown — placeholder, labels

  // Brand Oranges
  static const orange     = Color(0xFFFF5500); // primary orange
  static const orangeLight= Color(0xFFFF8C42); // lighter orange — gradients, accents
  static const orangeDark = Color(0xFFFF3D00); // deeper red-orange — button bottom
  static const amber      = Color(0xFFFFB347); // warm amber — tertiary accent
  static const orangeMid  = Color(0xFFFF6B1A); // between orange and orangeLight

  // Semantic (scan log)
  static const logOk   = Color(0xFF16A34A);   // green — success log lines
  static const logErr  = Color(0xFFDC2626);   // red — error log lines
  static const logWarn = Color(0xFFD97706);   // amber — warning log lines

  // Status indicators
  static const pipRed    = Color(0xFFFF5F57); // macOS-style red dot
  static const pipYellow = Color(0xFFFEBC2E); // macOS-style yellow dot
  static const pipGreen  = Color(0xFF28C840); // macOS-style green dot

  // Tag backgrounds
  static const tagNewFrom  = Color(0xFFFF5500); // gradient start
  static const tagNewTo    = Color(0xFFFF8C42); // gradient end
  static const tagSeenBg   = Color(0xFFFFF8F4); // same as bg
  static const tagSeenText = Color(0xFFA07060); // muted

  // File uploaded tile
  static const fileGreenLight = Color(0xFFDCFCE7);
  static const fileGreenMid   = Color(0xFFBBF7D0);
  static const fileIconFrom   = Color(0xFF6EE7B7);
  static const fileIconTo     = Color(0xFF34D399);
  static const fileCheckFrom  = Color(0xFF22C55E);
  static const fileCheckTo    = Color(0xFF16A34A);
  static const fileText       = Color(0xFF14532D);
  static const fileTextMuted  = Color(0x9914532D); // 60% alpha

  // Metric orb backgrounds
  static const orbWarm1From  = Color(0xFFFFE4CC);
  static const orbWarm1To    = Color(0xFFFFD0A8);
  static const orbWarm2From  = Color(0xFFFFF0E0);
  static const orbWarm2To    = Color(0xFFFFE0C0);

  // Exclude chips
  static const excChipFrom = Color(0xFFFECACA);
  static const excChipTo   = Color(0xFFFCA5A5);
  static const excChipText = Color(0xFF7F1D1D);
}
```

### Gradient Definitions

```dart
// Primary orange button gradient (top-left to bottom-right)
const LinearGradient gradientPrimaryBtn = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF6620), Color(0xFFFF3D00)],
);

// Pill track / active tab
const LinearGradient gradientPillTrack = LinearGradient(
  begin: Alignment(-1, -1),
  end: Alignment(1, 1),
  colors: [Color(0xFFFF5500), Color(0xFFFF8C42)],
);

// Dock active item
const LinearGradient gradientDockActive = LinearGradient(
  begin: Alignment(-1, -1),
  end: Alignment(1, 1),
  colors: [Color(0xFFFF5500), Color(0xFFFF8C42)],
);

// Arc progress stroke (use as ShaderMask or custom painter)
const LinearGradient gradientArc = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFF3D00), Color(0xFFFF6B1A), Color(0xFFFF8C42)],
  stops: [0.0, 0.5, 1.0],
);

// Brand orb (conic-like — approximate with sweep gradient)
const SweepGradient gradientBrandOrb = SweepGradient(
  startAngle: 3.49, // ~200 degrees in radians
  endAngle: 3.49 + (2 * 3.14159),
  center: Alignment(-0.4, -0.4),
  colors: [Color(0xFFFF5500), Color(0xFFFF8C42), Color(0xFFFF3D00), Color(0xFFFF5500)],
  stops: [0.0, 0.33, 0.67, 1.0],
);

// Upload tile top border stripe
const LinearGradient gradientStripe = LinearGradient(
  colors: [Color(0xFFFF3D00), Color(0xFFFF8C42), Color(0xFFFFB347)],
);
```

---

## 3. DESIGN TOKENS — TYPOGRAPHY

**Font Family:** `Nunito` (primary) and `Nunito Sans` (secondary/body)  
Add to `pubspec.yaml`:
```yaml
fonts:
  - family: Nunito
    fonts:
      - asset: fonts/Nunito-Regular.ttf
      - asset: fonts/Nunito-SemiBold.ttf  weight: 600
      - asset: fonts/Nunito-Bold.ttf      weight: 700
      - asset: fonts/Nunito-ExtraBold.ttf weight: 800
      - asset: fonts/Nunito-Black.ttf     weight: 900
  - family: NunitoSans
    fonts:
      - asset: fonts/NunitoSans-Light.ttf weight: 300
      - asset: fonts/NunitoSans-Regular.ttf
      - asset: fonts/NunitoSans-SemiBold.ttf weight: 600
```

### Text Style Reference

```dart
class AppText {
  // Brand name in topbar
  static const brandName = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800,
    fontSize: 18, letterSpacing: -0.36, color: AppColors.ink,
  );

  // Brand letter inside orb
  static const brandLetter = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 17, color: Colors.white,
    shadows: [Shadow(offset: Offset(0,1), blurRadius: 3, color: Color(0x4D000000))],
  );

  // Hero big number
  static const heroNumber = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 44, letterSpacing: -1.76, color: AppColors.ink, height: 1.0,
  );

  // Hero subtitle
  static const heroSub = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w300,
    fontSize: 13, color: AppColors.muted, letterSpacing: 0.26,
  );

  // Pill tab label
  static const pillTab = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800,
    fontSize: 12, letterSpacing: 0.48,
  );

  // Section header (uppercase label)
  static const sectionHead = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800,
    fontSize: 11, letterSpacing: 1.1, color: AppColors.muted,
  );

  // Clay input text
  static const inputText = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.ink,
  );
  static const inputPlaceholder = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w400, fontSize: 15, color: AppColors.muted,
  );
  static const inputLabel = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 11,
    letterSpacing: 0.88, color: AppColors.muted,
  );

  // Chip label
  static const chipLabel = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.ink,
  );

  // Upload tile
  static const uploadTitle = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 18, color: AppColors.ink,
  );
  static const uploadHint = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w300, fontSize: 13, color: AppColors.muted,
  );

  // Arc percentage
  static const arcPct = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 44, letterSpacing: -2.2, color: AppColors.ink, height: 1.0,
  );
  static const arcSub = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700,
    fontSize: 10, letterSpacing: 1.0, color: AppColors.muted,
  );

  // Metric orb number
  static const orbNum = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 30, letterSpacing: -1.2, color: AppColors.ink, height: 1.0,
  );
  static const orbLabel = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700,
    fontSize: 10, letterSpacing: 0.8, color: Color(0x66000000),
  );

  // Log feed (monospace)
  static const logTime = TextStyle(
    fontFamily: 'Courier New', fontSize: 10.5, color: AppColors.muted, height: 2.0,
  );
  static const logOk = TextStyle(
    fontFamily: 'Courier New', fontSize: 10.5, fontWeight: FontWeight.bold,
    color: AppColors.logOk, height: 2.0,
  );
  static const logErr = TextStyle(
    fontFamily: 'Courier New', fontSize: 10.5, color: AppColors.logErr, height: 2.0,
  );
  static const logWarn = TextStyle(
    fontFamily: 'Courier New', fontSize: 10.5, color: AppColors.logWarn, height: 2.0,
  );
  static const logInfo = TextStyle(
    fontFamily: 'Courier New', fontSize: 10.5, color: AppColors.muted, height: 2.0,
  );

  // Job card
  static const jcardTitle = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 14,
    color: AppColors.ink, height: 1.35,
  );
  static const jcardCompany = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 11.5, color: AppColors.inkSoft,
  );
  static const jcardLocation = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w400, fontSize: 11, color: AppColors.muted,
  );
  static const jcardTime = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w400, fontSize: 10, color: AppColors.muted,
  );
  static const tagAts = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 9.5, color: AppColors.muted,
  );
  static const tagNew = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 9,
    color: Colors.white, letterSpacing: 0.54,
  );
  static const tagSeen = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 9,
    color: AppColors.muted, letterSpacing: 0.54,
  );

  // Detail sheet
  static const detailTitle = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 26, color: AppColors.ink, height: 1.1,
  );
  static const detailCompany = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.orange,
  );
  static const detailLocation = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w400, fontSize: 13, color: AppColors.muted,
  );
  static const detailBody = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w400,
    fontSize: 15, color: AppColors.inkSoft, height: 1.6,
  );
  static const reqChip = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 11, color: AppColors.inkSoft,
  );

  // Dock label
  static const dockLabel = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 9, letterSpacing: 0.36,
  );

  // Carousel counter
  static const carouselCounter = TextStyle(
    fontFamily: 'Courier New', fontWeight: FontWeight.w700,
    fontSize: 10, color: AppColors.muted, letterSpacing: 1.0,
  );

  // Filter panel
  static const filterTitle = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w900,
    fontSize: 20, letterSpacing: -0.6, color: AppColors.ink,
  );
  static const filterSectionLabel = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 10,
    letterSpacing: 1.0, color: AppColors.muted,
  );
  static const filterChip = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 12, color: AppColors.inkSoft,
  );

  // File tile
  static const fileName = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.fileText,
  );
  static const fileMeta = TextStyle(
    fontFamily: 'NunitoSans', fontWeight: FontWeight.w400,
    fontSize: 11, color: AppColors.fileTextMuted,
  );

  // Filter bar pill
  static const filterBarPill = TextStyle(
    fontFamily: 'Nunito', fontWeight: FontWeight.w700, fontSize: 11, color: AppColors.muted,
  );
}
```

---

## 4. DESIGN TOKENS — SHADOWS & ELEVATION

Flutter doesn't support CSS `box-shadow` exactly, so use `BoxDecoration.boxShadow`.

```dart
class AppShadows {
  // Clay "up" — resting surface, main card shadow
  static const clayUp = [
    BoxShadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1),  blurRadius: 1,  spreadRadius: 0), // inset-like top sheen
    BoxShadow(color: Color(0x1AB43C00), offset: Offset(0, 2),  blurRadius: 4),
    BoxShadow(color: Color(0x12B43C00), offset: Offset(0, 6),  blurRadius: 16),
    BoxShadow(color: Color(0x0F000000), offset: Offset(0, 1),  blurRadius: 0),
  ];

  // Clay "down" — pressed state
  // NOTE: Flutter doesn't support inset shadows natively.
  // Simulate with a slightly darker background and no top elevation.
  // Use a custom painter or a translucent overlay for true inset feel.
  static const clayDown = [
    BoxShadow(color: Color(0xCCFFFFFF), offset: Offset(0, 1), blurRadius: 2),
  ];

  // Clay "float" — elevated cards (upload tile, job cards)
  static const clayFloat = [
    BoxShadow(color: Color(0xF3FFFFFF), offset: Offset(0, 1),  blurRadius: 1),
    BoxShadow(color: Color(0x17B43C00), offset: Offset(0, 4),  blurRadius: 8),
    BoxShadow(color: Color(0x12B43C00), offset: Offset(0, 12), blurRadius: 32),
    BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1),  blurRadius: 0),
  ];

  // Globe canvas shadow
  static const globe = [
    BoxShadow(color: Color(0xCCFFFFFF), offset: Offset(0, 1),   blurRadius: 1, spreadRadius: 0),
    BoxShadow(color: Color(0x12000000), offset: Offset(0, 6),   blurRadius: 0),
    BoxShadow(color: Color(0x24000000), offset: Offset(0, 12),  blurRadius: 32),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 24),  blurRadius: 56),
  ];

  // Dock / bottom nav
  static const dock = [
    BoxShadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1),  blurRadius: 1),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 4),  blurRadius: 0),
    BoxShadow(color: Color(0x1F000000), offset: Offset(0, 8),  blurRadius: 32),
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 2),  blurRadius: 8),
  ];

  // Dock active item
  static const dockActive = [
    BoxShadow(color: Color(0x33FFFFFF), offset: Offset(0, 1),  blurRadius: 1),
    BoxShadow(color: Color(0x4DB42800), offset: Offset(0, 3),  blurRadius: 0),
    BoxShadow(color: Color(0x33FF5500), offset: Offset(0, 6),  blurRadius: 16),
  ];

  // Clay button primary bottom edge (3D lift)
  static const btnPrimaryEdge = [
    BoxShadow(color: Color(0x66C82800), offset: Offset(0, 4), blurRadius: 0),
  ];

  // New tag
  static const tagNew = [
    BoxShadow(color: Color(0x4DFF5500), offset: Offset(0, 2), blurRadius: 6),
  ];

  // Pill track (orange active tab)
  static const pillTrack = [
    BoxShadow(color: Color(0x59FF5500), offset: Offset(0, 2), blurRadius: 8),
  ];

  // City tooltip (globe popup)
  static const tooltip = [
    BoxShadow(color: Color(0x38000000), offset: Offset(0, 4), blurRadius: 16),
    BoxShadow(color: Color(0x26000000), offset: Offset(0, 2), blurRadius: 0),
  ];
}
```

> **Inset Shadows:** CSS `inset` shadows (used for the pressed state) don't exist natively in Flutter. To replicate:
> - Use a `Stack` with a semi-transparent dark overlay at the top when pressed
> - OR use a `CustomPaint` with a shadow effect drawn inside the clip
> - OR use `NeumorphicContainer` from the `flutter_neumorphic` package

---

## 5. DESIGN TOKENS — BORDER RADII

```dart
class AppRadius {
  static const pill  = 100.0;  // fully rounded pills and chips
  static const btn   = 18.0;   // clay buttons
  static const card  = 28.0;   // upload tile, large cards
  static const input = 18.0;   // text inputs
  static const chip  = 100.0;  // keyword chips (same as pill)
  static const dock  = 32.0;   // dock container
  static const dockItem = 24.0; // individual dock tabs
  static const orb   = 12.0;   // brand orb, icon buttons
  static const metric= 24.0;   // metric orb cards
  static const jcard = 22.0;   // job cards
  static const log   = 20.0;   // log tile
  static const filterSheet = 28.0; // bottom sheet top corners
  static const detail = 32.0;  // detail header bottom corners
  static const fileIcon = 14.0; // file icon 3D orb
  static const filterChip = 100.0;
}
```

---

## 6. DESIGN TOKENS — SPACING

```dart
class AppSpacing {
  static const pageHPad = 24.0;   // horizontal padding for all screens
  static const sectionGap = 8.0;  // between section header and content
  static const chipGap = 7.0;     // gap inside chip rows
  static const chipRowBottom = 12.0; // margin below chip row
  static const orbGap = 12.0;     // gap between metric orbs
  static const inputBottom = 12.0; // below input fields
  static const topbarV = 20.0;    // topbar top padding
  static const topbarB = 12.0;    // topbar bottom padding
  static const dockBottom = 24.0; // dock from bottom of screen
  static const heroBottom = 20.0; // below hero label
  static const pillH = 24.0;      // pill toggle side margin
  static const pillB = 28.0;      // pill toggle bottom margin
  static const pillPad = 4.0;     // pill toggle inner padding
  static const tabV = 10.0;       // pill tab vertical padding
}
```

---

## 7. APP ARCHITECTURE & NAVIGATION

```
lib/
├── main.dart
├── app.dart                  # MaterialApp setup, theme
├── models/
│   └── job.dart              # Job data model
├── data/
│   └── mock_jobs.dart        # 200 mock job entries
├── state/
│   └── app_state.dart        # ChangeNotifier or Riverpod provider
├── screens/
│   ├── shell_screen.dart     # Main shell with tabs, dock, globe, hero
│   ├── setup_screen.dart     # Screen 0
│   ├── scan_screen.dart      # Screen 1
│   └── results_screen.dart   # Screen 2
├── widgets/
│   ├── brand_orb.dart
│   ├── globe_canvas.dart     # CustomPaint globe
│   ├── pill_toggle.dart
│   ├── clay_button.dart
│   ├── clay_input.dart
│   ├── keyword_chip.dart
│   ├── upload_tile.dart
│   ├── metric_orb.dart
│   ├── arc_progress.dart     # CustomPaint arc
│   ├── log_tile.dart
│   ├── job_card.dart
│   ├── carousel_widget.dart  # Snap scroll carousel
│   ├── dock_bar.dart
│   ├── detail_sheet.dart     # Slide-in overlay
│   └── filter_panel.dart     # Bottom sheet
└── theme/
    ├── colors.dart
    ├── text_styles.dart
    ├── shadows.dart
    └── radii.dart
```

**Navigation pattern:**
- No `Navigator.push`. Everything lives in `ShellScreen`.
- Tab state managed via `IndexedStack` or manual `Visibility` — keep all screens alive.
- `activeTab` is a single int in state.
- Detail sheet and filter panel are fixed-position overlays using `Stack` + `AnimatedPositioned`.

---

## 8. GLOBAL BACKGROUND & BODY

```dart
// In app.dart / scaffold
Scaffold(
  backgroundColor: AppColors.bg,
  body: Container(
    decoration: BoxDecoration(
      color: AppColors.bg,
      // Simulate the radial gradient overlays:
      gradient: RadialGradient(
        center: Alignment(0, -1.2),
        radius: 1.5,
        colors: [Color(0xCCFFFFFF), AppColors.bg],
      ),
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 390),
        child: ShellScreen(),
      ),
    ),
  ),
)
```

> The HTML uses 3 layered radial gradients. In Flutter, layer them with a `Stack` of `Container`s with gradient decorations and `IgnorePointer`.

---

## 9. COMPONENT: TOPBAR

**Layout:** `Row` with `brand-lockup` on left, two icon buttons on right.  
**Height:** ~78px total (20px top pad + 38px content + 12px bottom pad)

### Brand Orb (38×38)
```dart
Container(
  width: 38, height: 38,
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(AppRadius.orb),
    boxShadow: AppShadows.clayUp,
    gradient: gradientBrandOrb, // sweep gradient
  ),
  child: Stack(
    children: [
      // Top sheen (simulated ::after pseudo-element)
      Positioned(
        top: 3, left: 5, right: 10,
        child: Container(
          height: 38 * 0.4,
          decoration: BoxDecoration(
            color: Color(0x59FFFFFF),
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      Center(
        child: Text('N', style: AppText.brandLetter),
      ),
    ],
  ),
)
```

### Icon Buttons (38×38 each, gap: 8px)
```dart
// Decoration (same for both)
Container(
  width: 38, height: 38,
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(AppRadius.orb),
    boxShadow: AppShadows.clayUp,
  ),
  child: IconButton(
    padding: EdgeInsets.zero,
    icon: Icon(/* bell or search SVG */, size: 16, color: AppColors.muted),
    onPressed: () {},
  ),
)
```
**Active/pressed state:** Scale to `0.96`, switch shadow to `clayDown` — use `GestureDetector` with `onTapDown`/`onTapUp` + `AnimatedScale`.

---

## 10. COMPONENT: GLOBE HERO (CANVAS)

This is the most complex widget. Use `CustomPaint` with a `CustomPainter`.

### Container
```dart
Center(
  child: AnimatedBuilder(
    animation: _floatAnimation, // looping tween
    builder: (ctx, child) => Transform.translate(
      offset: Offset(0, _floatAnimation.value),
      child: child,
    ),
    child: SizedBox(
      width: 200, height: 200,
      child: GestureDetector(
        onTap: () => _handleTap(),
        child: ClipOval(
          child: CustomPaint(
            painter: GlobePainter(state: _globeState),
          ),
        ),
      ),
    ),
  ),
)
```

### Float Animation
```dart
// In initState:
_floatController = AnimationController(
  vsync: this, duration: Duration(milliseconds: 4200),
)..repeat(reverse: true);

_floatAnimation = Tween<double>(begin: 0, end: -9).animate(
  CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
);
```

### Globe Painter Parameters
The `GlobePainter` needs:
```dart
class GlobeState {
  double cLon;         // current view longitude center
  double cLat;         // current view latitude center
  double radius;       // current radius (88 base, 165 zoomed)
  double dotAlpha;     // 0..1 city dot opacity
  double scanLon;      // current scan sweep longitude
  String mode;         // 'setup' | 'scan' | 'results'
  City? selectedCity;  // currently selected city (or null)
  int frame;           // frame counter for animations
  List<List<List<double>>> lands; // loaded GeoJSON polygons
}
```

### Orthographic Projection (port to Dart)
```dart
// Returns null if the point is on the back hemisphere
Offset? project(double lon, double lat, double R, double cLon, double cLat) {
  final DEG = pi / 180;
  final lambda = lon * DEG, phi = lat * DEG;
  final lambda0 = cLon * DEG, phi0 = cLat * DEG;
  final cosC = sin(phi) * sin(phi0) +
               cos(phi) * cos(phi0) * cos(lambda - lambda0);
  if (cosC < 0) return null;
  final cx = 100.0, cy = 100.0; // center of 200x200 canvas
  return Offset(
    cx + R * cos(phi) * sin(lambda - lambda0),
    cy - R * (cos(phi0) * sin(phi) - sin(phi0) * cos(phi) * cos(lambda - lambda0)),
  );
}
```

### What to draw in order (GlobePainter.paint):
1. **Clip** to circular path matching radius
2. **Ocean fill** — radial gradient (warm off-white center, darker edges)
3. **Lat/lon grid** — 0.45px lines, `rgba(110,90,65,0.13)`, every 30°
4. **Equator** — slightly bolder, `rgba(110,90,65,0.20)`
5. **Land masses** — from GeoJSON polygons, `rgba(196,180,152,0.62)` fill, `rgba(140,120,90,0.38)` stroke 0.7px
6. **Scan sweep** (only in scan mode) — 3 vertical lines at `scanLon`, `scanLon+4`, `scanLon+10` with decreasing alpha and increasing width
7. **City nodes** (only in results mode, fade with `dotAlpha`) — sonar rings, diamond shape, crosshairs, selected lock rings
8. **Edge shading** — radial gradient overlay, transparent center to `rgba(0,0,0,0.16)` at edge
9. **Specular highlight** — radial gradient at top-left, `rgba(255,255,255,0.60)` → transparent

### GeoJSON Loading
Use `http` package to fetch `https://cdn.jsdelivr.net/npm/world-atlas@2/land-110m.json` at startup. Decode the TopoJSON (delta-encoded arcs) to lat/lon polygon arrays. Cache in memory. Fall back to a hardcoded simplified polygon list if fetch fails.

### Tap Handling
- **Single tap** → spin globe (add 55-80° to `tLon`), or zoom into nearest city if in results mode
- **Double tap** → zoom out if zoomed
- Use a 210ms debounce timer to distinguish single from double

### City Nodes Drawing
```dart
// For each city, after project():
// 1. Two sonar rings (expanding, pulsing with sin(t*1.6 + i*1.4))
// 2. Static thin circle (r=5, stroke only)
// 3. Diamond shape (rotated square, half-size 2.6)
// 4. Centre pinhole (r=0.9, white fill)
// 5. Crosshair tick lines (8px long, starting 5.5px from center)
// 6. If selected: dashed rotating lock ring (r=13)
```

### Tooltip & Zoom Hint
```dart
// Position these as Stack children above the globe canvas:
Positioned(
  bottom: -36, left: 0, right: 0,
  child: AnimatedOpacity(
    opacity: _tooltipVisible ? 1.0 : 0.0,
    duration: Duration(milliseconds: 300),
    child: AnimatedScale(
      scale: _tooltipVisible ? 1.0 : 0.92,
      duration: Duration(milliseconds: 350),
      curve: Curves.elasticOut,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.circular(100),
          boxShadow: AppShadows.tooltip,
        ),
        child: Text(_tooltipText, style: /* 11px, w800, white, ls:0.02em */),
      ),
    ),
  ),
)
```

---

## 11. COMPONENT: HERO LABEL

```dart
Column(
  children: [
    Text(_heroNum, style: AppText.heroNumber),
    SizedBox(height: 4),
    Text(_heroSub, style: AppText.heroSub),
  ],
)
```

**State changes by active tab:**
| Tab | heroNum | heroSub |
|-----|---------|---------|
| 0 (Setup) | `"255"` | `"companies ready to scan"` |
| 1 (Scan) | current `"XX%"` | `"scan in progress"` |
| 2 (Results) | `"200"` | `"positions discovered"` |

---

## 12. COMPONENT: PILL TOGGLE (TAB BAR)

```dart
// Container
Container(
  margin: EdgeInsets.symmetric(horizontal: 24),
  padding: EdgeInsets.all(4),
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(AppRadius.pill),
    boxShadow: AppShadows.clayUp,
  ),
  child: Stack(
    children: [
      // Animated track (orange pill)
      AnimatedPositioned(
        duration: Duration(milliseconds: 350),
        curve: Cubic(0.34, 1.56, 0.64, 1), // spring
        left: activeTab * (trackWidth / 3) + activeTab * 1.0,
        top: 0, bottom: 0,
        width: trackWidth / 3 - 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: gradientPillTrack,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: AppShadows.pillTrack,
          ),
        ),
      ),
      // Tabs
      Row(
        children: ['Setup', 'Scan', 'Results'].asMap().entries.map((e) =>
          Expanded(
            child: GestureDetector(
              onTap: () => switchTab(e.key),
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  e.value,
                  textAlign: TextAlign.center,
                  style: AppText.pillTab.copyWith(
                    color: activeTab == e.key ? Colors.white : AppColors.muted,
                  ),
                ),
              ),
            ),
          ),
        ).toList(),
      ),
    ],
  ),
)
```

> **Spring curve** `Cubic(0.34, 1.56, 0.64, 1)` approximates CSS `cubic-bezier(0.34, 1.56, 0.64, 1)`. For a true spring, use `SpringSimulation` with a custom `AnimationController`.

---

## 13. SCREEN: SETUP

### Upload Tile
```dart
// Outer container
GestureDetector(
  onTap: _handleUpload,
  child: AnimatedScale(
    scale: _uploadPressed ? 0.97 : 1.0,
    duration: Duration(milliseconds: 200),
    curve: Cubic(0.34, 1.56, 0.64, 1),
    child: Container(
      margin: EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.clayFloat,
      ),
      child: Stack(
        children: [
          // Top stripe (2px height)
          Positioned(
            top: 0, left: 0, right: 0,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: gradientStripe,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(AppRadius.card),
                  topRight: Radius.circular(AppRadius.card),
                ),
              ),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.fromLTRB(20, 32, 20, 32),
            child: Column(
              children: [
                _UploadOrb(), // 72x72 circular orb with icon
                SizedBox(height: 16),
                Text('Drop company list', style: AppText.uploadTitle),
                SizedBox(height: 4),
                Text('.xlsx · .csv · .json', style: AppText.uploadHint),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
)
```

#### Upload Orb (72×72)
```dart
Container(
  width: 72, height: 72,
  decoration: BoxDecoration(
    shape: BoxShape.circle,
    gradient: LinearGradient(
      begin: Alignment(-1, -1),
      end: Alignment(1, 1),
      colors: [Color(0xFFF0EDE8), Color(0xFFE2DDD6)],
    ),
    boxShadow: [
      BoxShadow(color: Color(0x1A000000), offset: Offset(0, -3), blurRadius: 8),
      BoxShadow(color: Color(0xCCFFFFFF), offset: Offset(0, 2), blurRadius: 4),
      BoxShadow(color: Color(0x1A000000), offset: Offset(0, 8), blurRadius: 20),
    ],
  ),
  child: Icon(/* upload cloud icon */, size: 28, color: AppColors.orange),
)
```

### File Loaded Tile
Shown after upload (replaces upload tile):
```dart
Container(
  padding: EdgeInsets.all(16),
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment(-1, -1), end: Alignment(1, 1),
      colors: [AppColors.fileGreenLight, AppColors.fileGreenMid],
    ),
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      ...AppShadows.clayUp,
      BoxShadow(color: Color(0x40007830), offset: Offset(0, 3)),
    ],
  ),
  child: Row(
    children: [
      // File icon (46x46)
      Container(
        width: 46, height: 46, borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(colors: [AppColors.fileIconFrom, AppColors.fileIconTo]),
        boxShadow: [/* green shadow */],
        child: Icon(Icons.description, size: 22, color: Colors.white),
      ),
      SizedBox(width: 14),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('web3_companies.xlsx', style: AppText.fileName),
        Text('255 companies · 48 KB', style: AppText.fileMeta),
      ]),
      Spacer(),
      // Check mark (32x32 circle)
      Container(
        width: 32, height: 32, borderRadius: BorderRadius.circular(100),
        gradient: LinearGradient(colors: [AppColors.fileCheckFrom, AppColors.fileCheckTo]),
        child: Icon(Icons.check, size: 16, color: Colors.white),
      ),
    ],
  ),
)
```

### Clay Input
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(AppRadius.input),
    boxShadow: [
      BoxShadow(color: Color(0x12000000), offset: Offset(0, 2), blurRadius: 6, spreadRadius: 0),
      BoxShadow(color: Color(0x0D000000), offset: Offset(0, 1), blurRadius: 2),
      BoxShadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1), blurRadius: 2),
    ],
  ),
  child: TextField(
    style: AppText.inputText,
    decoration: InputDecoration(
      hintText: '+ add keyword',
      hintStyle: AppText.inputPlaceholder,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      border: InputBorder.none,
    ),
    onSubmitted: (val) => _addChip(val),
  ),
)
```

**Focus state:** Add a 3px ring — wrap with `AnimatedContainer` and add `BoxShadow(color: Color(0x2EFF5500), spreadRadius: 3)`.

### Keyword Chips
```dart
// Include chip (white)
Container(
  padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(100),
    boxShadow: AppShadows.clayUp,
  ),
  child: Row(children: [
    Text(keyword, style: AppText.chipLabel),
    SizedBox(width: 3),
    GestureDetector(
      onTap: () => _removeChip(keyword),
      child: Text('×', style: TextStyle(fontSize: 11, color: AppColors.muted.withOpacity(0.45))),
    ),
  ]),
)

// Exclude chip (red gradient)
Container(
  padding: EdgeInsets.symmetric(horizontal: 13, vertical: 7),
  decoration: BoxDecoration(
    gradient: LinearGradient(colors: [AppColors.excChipFrom, AppColors.excChipTo]),
    borderRadius: BorderRadius.circular(100),
    boxShadow: AppShadows.clayUp,
  ),
  child: Row(children: [
    Text(keyword, style: AppText.chipLabel.copyWith(color: AppColors.excChipText)),
    // × icon same as above but in excChipText color
  ]),
)
```

### Clay Button (Primary Orange)
```dart
GestureDetector(
  onTapDown: (_) => setState(() => _pressed = true),
  onTapUp: (_) => setState(() => _pressed = false),
  onTapCancel: () => setState(() => _pressed = false),
  onTap: widget.onPressed,
  child: AnimatedContainer(
    duration: Duration(milliseconds: 150),
    transform: Matrix4.translationValues(0, _pressed ? 3 : 0, 0),
    width: double.infinity,
    padding: EdgeInsets.symmetric(vertical: 20, horizontal: 24),
    decoration: BoxDecoration(
      gradient: gradientPrimaryBtn,
      borderRadius: BorderRadius.circular(AppRadius.btn),
      boxShadow: _pressed ? AppShadows.clayDown : [
        ...AppShadows.clayUp,
        BoxShadow(color: Color(0x66C82800), offset: Offset(0, 4)),
      ],
    ),
    child: Stack(
      children: [
        // Top sheen (::before pseudo)
        Positioned(
          top: 0, left: 0, right: 0,
          height: 50%, // half of button height
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0x40FFFFFF), Color(0x00FFFFFF)],
              ),
              borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.btn)),
            ),
          ),
        ),
        // Bottom shadow stripe (::after pseudo)
        Positioned(
          bottom: 0, left: 4, right: 4,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: Color(0x26000000),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(AppRadius.btn)),
            ),
          ),
        ),
        Center(child: Text(widget.label, style: AppText.inputText.copyWith(fontSize: 17, color: Colors.white))),
      ],
    ),
  ),
)
```

---

## 14. SCREEN: SCAN

### Arc Progress (CustomPaint)
```dart
class ArcPainter extends CustomPainter {
  final double progress; // 0.0 to 1.0

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = 80.0;
    final strokeWidth = 10.0;

    // Background arc
    canvas.drawCircle(center, radius, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..color = Color(0x0F000000));

    // Gradient foreground arc (start from top, go clockwise)
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweepAngle = 2 * pi * progress;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: -pi / 2 + 2 * pi,
        colors: [Color(0xFFFF3D00), Color(0xFFFF6B1A), Color(0xFFFF8C42)],
        stops: [0.0, 0.5, 1.0],
      ).createShader(rect)
      ..maskFilter = MaskFilter.blur(BlurStyle.outer, 8); // drop-shadow equivalent

    canvas.drawArc(rect, -pi / 2, sweepAngle, false, paint);
  }
}
```

### Metric Orbs (3 in a Row)
```dart
Row(
  children: [
    _MetricOrb(num: found, label: 'FOUND',   gradient: LinearGradient(colors: [Color(0xFFFFE4CC), Color(0xFFFFD0A8)])),
    SizedBox(width: 12),
    _MetricOrb(num: scanned, label: 'SCANNED', gradient: LinearGradient(colors: [Color(0xFFFFF0E0), Color(0xFFFFE0C0)])),
    SizedBox(width: 12),
    _MetricOrb(num: errors, label: 'ERRORS',  color: AppColors.white),
  ],
)

// Each orb:
Container(
  padding: EdgeInsets.symmetric(vertical: 18, horizontal: 12),
  decoration: BoxDecoration(
    gradient: orbGradient, // or color: white
    borderRadius: BorderRadius.circular(24),
    boxShadow: AppShadows.clayFloat,
  ),
  child: Column(
    children: [
      // Top sheen line (::before)
      Container(
        height: 1.5,
        margin: EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.transparent, Color(0xCCFFFFFF), Colors.transparent]),
        ),
      ),
      Text(num.toString(), style: AppText.orbNum),
      SizedBox(height: 4),
      Text(label, style: AppText.orbLabel),
    ],
  ),
)
```

### Log Tile
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(20),
    boxShadow: [
      BoxShadow(color: Color(0x12000000), offset: Offset(0, 2), blurRadius: 6, spreadRadius: -1),
      BoxShadow(color: Color(0xE6FFFFFF), offset: Offset(0, 1), blurRadius: 2),
    ],
  ),
  child: Column(
    children: [
      // Titlebar with 3 dots
      Container(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [Color(0x08000000), Colors.transparent]),
          border: Border(bottom: BorderSide(color: Color(0x0D000000))),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Row(children: [
          _Dot(color: AppColors.pipRed),
          SizedBox(width: 6),
          _Dot(color: AppColors.pipYellow),
          SizedBox(width: 6),
          _Dot(color: AppColors.pipGreen),
          SizedBox(width: 10),
          Text('live feed', style: AppText.logInfo),
        ]),
      ),
      // Scrolling log body
      SizedBox(
        height: 140,
        child: ListView.builder(
          controller: _logScrollController,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: _logLines.length,
          itemBuilder: (ctx, i) => Row(
            children: [
              Text(_logLines[i].time, style: AppText.logTime),
              SizedBox(width: 10),
              Text(_logLines[i].message, style: _logLines[i].style),
            ],
          ),
        ),
      ),
    ],
  ),
)
```

---

## 15. SCREEN: RESULTS

### Filter Bar (horizontal scroll)
```dart
SingleChildScrollView(
  scrollDirection: Axis.horizontal,
  child: Row(
    children: [
      ...['All', 'New', 'Seen', 'Remote'].map((label) =>
        Padding(
          padding: EdgeInsets.only(right: 8),
          child: _FilterPill(label: label, active: _activeFilter == label),
        ),
      ),
      Padding(
        padding: EdgeInsets.only(left: 8),
        child: _FilterPill(label: '⚙ Filter', onTap: _openFilterPanel),
      ),
    ],
  ),
)
```

#### Filter Pill
```dart
Container(
  padding: EdgeInsets.symmetric(horizontal: 14, vertical: 7),
  decoration: BoxDecoration(
    gradient: active ? gradientPillTrack : null,
    color: active ? null : AppColors.white,
    borderRadius: BorderRadius.circular(100),
    boxShadow: active
      ? [...AppShadows.clayUp, BoxShadow(color: Color(0x4DB42800), offset: Offset(0, 3))]
      : AppShadows.clayUp,
  ),
  child: Text(label, style: AppText.filterBarPill.copyWith(color: active ? Colors.white : AppColors.muted)),
)
```

### Job Card
```dart
Container(
  decoration: BoxDecoration(
    color: AppColors.white,
    borderRadius: BorderRadius.circular(AppRadius.jcard),
    boxShadow: AppShadows.clayFloat,
  ),
  child: Stack(children: [
    // Top stripe (3px)
    Positioned(top: 0, left: 0, right: 0,
      child: Container(height: 3,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [job.stripeFrom, job.stripeTo]),
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.jcard)),
        ),
      ),
    ),
    // Pip indicator (top right, 10x10)
    Positioned(top: 14, right: 16,
      child: Container(
        width: 10, height: 10, borderRadius: BorderRadius.circular(5),
        color: job.pipColor,
        // Ring: wrap with a Container with border
      ),
    ),
    Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(job.title, style: AppText.jcardTitle),
        SizedBox(height: 9),
        Wrap(spacing: 6, runSpacing: 4, children: [
          Text(job.company, style: AppText.jcardCompany),
          Text('·', style: TextStyle(fontSize: 9, color: AppColors.muted)),
          Text(job.location, style: AppText.jcardLocation),
          _AtsTag(job.ats),
          job.isNew ? _NewTag() : _SeenTag(),
        ]),
        SizedBox(height: 8),
        Text(job.time, style: AppText.jcardTime),
      ]),
    ),
  ]),
)
```

### Snap Carousel
```dart
// Use PageView with viewport fraction for the "peek at adjacent cards" effect
PageView.builder(
  controller: PageController(viewportFraction: 0.72), // shows ~1.4 cards
  scrollDirection: Axis.horizontal,
  onPageChanged: (idx) => setState(() => _activeCard = idx),
  itemCount: jobs.length,
  itemBuilder: (ctx, i) {
    // Animate scale and opacity based on distance from center
    return AnimatedBuilder(
      animation: _pageController,
      builder: (ctx, child) {
        double page = _pageController.hasClients ? (_pageController.page ?? 0) : 0;
        double dist = (page - i).abs();
        double scale = (1 - dist * 0.15).clamp(0.85, 1.0);
        double opacity = (1 - dist * 0.6).clamp(0.4, 1.0);
        return Transform.scale(
          scale: scale,
          child: Opacity(opacity: opacity, child: child),
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 5),
        child: GestureDetector(
          onTap: () => _openDetail(jobs[i]),
          child: JobCard(job: jobs[i]),
        ),
      ),
    );
  },
)
```

#### Carousel Dots
```dart
Row(
  mainAxisAlignment: MainAxisAlignment.center,
  children: List.generate(dotCount, (i) {
    bool isActive = _dotWindow + i == _activeCard;
    return AnimatedContainer(
      duration: Duration(milliseconds: 350),
      width: isActive ? 16 : 4,
      height: 4,
      margin: EdgeInsets.symmetric(horizontal: 2.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(2),
        gradient: isActive ? gradientPillTrack : null,
        color: isActive ? null : AppColors.muted.withOpacity(0.25),
      ),
    );
  }),
)
```

---

## 16. COMPONENT: DETAIL SHEET (SLIDE-IN)

This is a full-screen overlay that slides in from the right.

```dart
// In ShellScreen Stack:
AnimatedPositioned(
  duration: Duration(milliseconds: 400),
  curve: Curves.fastOutSlowIn,
  left: _detailOpen ? 0 : MediaQuery.of(context).size.width,
  right: _detailOpen ? 0 : -MediaQuery.of(context).size.width,
  top: 0, bottom: 0,
  child: DetailSheet(job: _selectedJob, onClose: _closeDetail),
)
```

### Detail Sheet Structure
```dart
Scaffold(
  backgroundColor: AppColors.bg,
  body: SingleChildScrollView(
    child: Column(children: [
      // HEADER (white card with rounded bottom)
      Container(
        padding: EdgeInsets.fromLTRB(24, 80, 24, 24),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          boxShadow: AppShadows.clayFloat,
        ),
        child: Stack(children: [
          // Top stripe (6px)
          Positioned(top: 0, left: 0, right: 0,
            child: Container(height: 6,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [job.stripeFrom, job.stripeTo]),
              ),
            ),
          ),
          // Back button (absolute top-left, 44x44 circle)
          Positioned(top: 24, left: 24,
            child: GestureDetector(
              onTap: onClose,
              child: Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: AppColors.white, shape: BoxShape.circle,
                  boxShadow: AppShadows.clayUp,
                ),
                child: Icon(Icons.chevron_left, size: 20, color: AppColors.ink),
              ),
            ),
          ),
          // Content
          Padding(
            padding: EdgeInsets.only(top: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (job.isNew) ...[
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    gradient: gradientDockActive,
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: AppShadows.tagNew,
                  ),
                  child: Text('NEW MATCH', style: AppText.tagNew),
                ),
                SizedBox(height: 8),
              ],
              Text(job.title, style: AppText.detailTitle),
              SizedBox(height: 8),
              Row(children: [
                Text(job.company, style: AppText.detailCompany),
                Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('•', style: TextStyle(color: AppColors.muted))),
                Text(job.location, style: AppText.detailLocation),
              ]),
            ]),
          ),
        ]),
      ),
      // BODY
      Padding(
        padding: EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('DETAILS', style: AppText.filterSectionLabel),
          SizedBox(height: 12),
          Wrap(children: [
            _ReqChip(job.ats),
            _ReqChip('Full-Time'),
            _ReqChip(job.time),
          ]),
          SizedBox(height: 16),
          Text('We are looking for an exceptional team member...', style: AppText.detailBody),
          SizedBox(height: 32),
          ClayButton(label: 'Apply Now →', onPressed: () {}),
        ]),
      ),
    ]),
  ),
)
```

---

## 17. COMPONENT: FILTER PANEL (BOTTOM SHEET)

```dart
showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (ctx) => Container(
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.filterSheet)),
      boxShadow: [
        BoxShadow(color: Color(0x1FFF5500), offset: Offset(0, -8), blurRadius: 40),
        BoxShadow(color: Color(0x14000000), offset: Offset(0, -2), blurRadius: 12),
      ],
    ),
    padding: EdgeInsets.fromLTRB(24, 0, 24, 48),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Handle
      Center(child: Container(
        width: 36, height: 4, margin: EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.muted.withOpacity(0.25),
          borderRadius: BorderRadius.circular(2),
        ),
      )),
      Text('Filter Results', style: AppText.filterTitle),
      SizedBox(height: 20),
      // Sections...
      _FilterSection(label: 'STATUS', options: ['All','New','Seen']),
      _FilterSection(label: 'LOCATION', options: ['Anywhere','Remote','United States','Europe']),
      _FilterSection(label: 'ATS PLATFORM', options: ['All','Workday','Greenhouse','Lever']),
      SizedBox(height: 8),
      // Apply button
      GestureDetector(
        onTap: _applyFilters,
        child: Container(
          width: double.infinity, padding: EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: gradientPrimaryBtn,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [...AppShadows.clayUp, BoxShadow(color: Color(0x66B42800), offset: Offset(0, 4))],
          ),
          child: Center(child: Text('Apply Filters', style: AppText.inputText.copyWith(fontSize: 16, color: Colors.white))),
        ),
      ),
    ]),
  ),
)
```

---

## 18. COMPONENT: BOTTOM DOCK (NAVIGATION BAR)

```dart
// Position at bottom with padding
Positioned(
  bottom: 0, left: 0, right: 0,
  child: Padding(
    padding: EdgeInsets.only(bottom: 24),
    child: Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.dock),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: Color(0xE0FAFAF8),
              borderRadius: BorderRadius.circular(AppRadius.dock),
              boxShadow: AppShadows.dock,
            ),
            padding: EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _DockItem(icon: Icons.wb_sunny_outlined, label: 'Setup',   index: 0),
                _DockItem(icon: Icons.show_chart,        label: 'Scan',    index: 1),
                _DockItem(icon: Icons.star_outline,      label: 'Results', index: 2),
                _DockItem(icon: Icons.bookmark_outline,  label: 'Saved',   index: 3),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
)

// Dock Item
Widget _DockItem(IconData icon, String label, int index) {
  final isActive = activeTab == index;
  return GestureDetector(
    onTap: () => switchTab(index),
    child: AnimatedContainer(
      duration: Duration(milliseconds: 200),
      curve: Cubic(0.34, 1.56, 0.64, 1),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: isActive ? gradientDockActive : null,
        borderRadius: BorderRadius.circular(AppRadius.dockItem),
        boxShadow: isActive ? AppShadows.dockActive : null,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 20, color: isActive ? Colors.white : AppColors.muted),
        SizedBox(height: 3),
        Text(label, style: AppText.dockLabel.copyWith(color: isActive ? Colors.white : AppColors.muted)),
      ]),
    ),
  );
}
```

---

## 19. ANIMATIONS & MOTION

### Summary of All Animations

| Element | Type | Duration | Curve | Notes |
|---------|------|----------|-------|-------|
| Globe float | Loop translate Y (0 → -9px) | 4200ms | `easeInOut` | Infinite, reverse |
| Screen popIn | Scale 0.94→1 + Y 12→0 | 500ms | `Cubic(0.34,1.56,0.64,1)` | Staggered: +40ms, +100ms, +160ms, +220ms |
| Pill track slide | Horizontal position | 350ms | `Cubic(0.34,1.56,0.64,1)` | Spring bounce |
| Tab switch | Fade/visibility | Instant | — | `IndexedStack`, no transition |
| City tooltip | Scale 0.92→1 + opacity | 350ms | `Cubic(0.34,1.56,0.64,1)` | |
| Globe zoom radius | Lerp each frame | Per frame | 0.068 factor | `curR += (tgtR - curR) * 0.068` |
| Globe spin | Increment `tLon` | Per frame | — | 0.13°/frame setup, 0.24° scan, 0.10° results |
| Globe camera lerp | Lerp lon/lat | Per frame | 0.055 factor | Smooth pan |
| City dot alpha | Lerp | Per frame | 0.038 factor | Fade in/out |
| Scan arc | Stroke dashoffset | 55ms per tick | Linear | 100 ticks total |
| Carousel scale/opacity | Per scroll frame | RAF | Linear | Distance from center |
| Dot pip width | AnimatedContainer | 350ms | Linear | 4px inactive → 16px active |
| Upload tile press | Scale 0.97 + shadow | 200ms | `Cubic(0.34,1.56,0.64,1)` | |
| Button press | Y+3px + shadow | 150ms | Linear | |
| Filter panel open | TranslateY 100%→0 | 400ms | `Cubic(0.34,1.2,0.64,1)` | |
| Detail sheet open | TranslateX 100%→0 | 400ms | `Curves.fastOutSlowIn` | |
| City sonar rings | Scale+opacity sine wave | 60fps | sin(t*1.6 + offset) | Infinite |
| Lock ring rotation | Dash offset increment | 60fps | Linear | -t*12 |
| Chip enter | popIn | 500ms | `Cubic(0.34,1.56,0.64,1)` | |
| Globe double-tap hint | Opacity | 350ms | Linear | |

### Spring Curve
The app heavily uses `cubic-bezier(0.34, 1.56, 0.64, 1)` — an overshoot spring. In Flutter:
```dart
const springCurve = Cubic(0.34, 1.56, 0.64, 1);
// Or for a true physics spring:
SpringSimulation(SpringDescription(mass: 1, stiffness: 200, damping: 20), 0, 1, 0)
```

### Globe Lerp Logic (port to Dart, called every 16ms via AnimationController)
```dart
void _tick() {
  // Handle 360° wrap for longitude
  var dL = tLon - cLon;
  while (dL > 180) dL -= 360;
  while (dL < -180) dL += 360;
  cLon += dL * 0.055;
  cLat += (tLat - cLat) * 0.055;
  if (autoSpin) tLon += spinSpeed;
  curR += (targetR - curR) * 0.068;
  dotAlpha += (targetDotAlpha - dotAlpha) * 0.038;
  setState(() {}); // triggers repaint
}
```

---

## 20. DATA MODELS

```dart
class Job {
  final String title;
  final String company;
  final String ats;       // 'Workday' | 'Greenhouse' | 'Lever'
  final String location;
  final bool isNew;
  final String time;      // "just now", "2 min ago", etc.
  final Color stripeFrom;
  final Color stripeTo;
  final Color pipColor;   // same as stripeFrom
}

class City {
  final String name;
  final double lon;
  final double lat;
  final Color color;
  final int count; // number of job positions
}

class LogLine {
  final String time;        // "MM:SS"
  final String icon;        // "✓", "✗", "→", "!"
  final String message;
  final LogType type;       // ok | err | warn | info
}

class FilterState {
  String status; // 'all' | 'new' | 'seen'
  String loc;    // 'all' | 'remote' | 'us' | 'eu'
  String ats;    // 'all' | 'workday' | 'greenhouse' | 'lever'
}

class ScanState {
  int progress;   // 0-100
  int found;
  int scanned;
  int errors;
  List<LogLine> log;
}
```

---

## 21. STATE MANAGEMENT

Recommend using **Riverpod** or **Provider**. Minimum providers needed:

```dart
// Active tab
final activeTabProvider = StateProvider<int>((ref) => 0);

// Globe state
final globeStateProvider = ChangeNotifierProvider<GlobeNotifier>((ref) => GlobeNotifier());

// Scan state
final scanStateProvider = ChangeNotifierProvider<ScanNotifier>((ref) => ScanNotifier());

// Jobs / results
final jobsProvider = StateProvider<List<Job>>((ref) => generateMockJobs());
final filteredJobsProvider = Provider<List<Job>>((ref) {
  final jobs = ref.watch(jobsProvider);
  final filter = ref.watch(filterStateProvider);
  return jobs.where((j) => filter.matches(j)).toList();
});

// Filter
final filterStateProvider = StateProvider<FilterState>((ref) => FilterState());

// Detail
final selectedJobProvider = StateProvider<Job?>((ref) => null);

// Upload
final fileLoadedProvider = StateProvider<bool>((ref) => false);
```

---

## 22. PLATFORM NOTES

### iOS Specific
- `ClipRRect` + `BackdropFilter` for the dock blur (requires `ImageFilter.blur`)
- Use `SafeArea` for the bottom dock — add extra bottom padding for home bar
- Tap gesture debounce for globe (250ms): use `Timer` from `dart:async`

### Android Specific
- `BackdropFilter` works on Android but may need `RenderObject` workarounds on older devices
- Use `android:windowTranslucentNavigation` or `SystemUiOverlayStyle` for edge-to-edge layout
- Canvas-based globe uses `repaintBoundary` — wrap `CustomPaint` with `RepaintBoundary` for performance

### Performance Tips
- **Globe**: Run the ticker in a `Ticker` (not `setState` every frame). Use `RepaintBoundary`.
- **Carousel**: Use `AutomaticKeepAliveClientMixin` on job cards to prevent rebuilds.
- **Log scroll**: Reverse the list and scroll to top (which is bottom) — avoids needing to always scroll to end.
- **GeoJSON**: Load and decode on a separate `Isolate` to avoid UI jank.
- The globe painter should cache land polygon projected coordinates when `cLon`/`cLat`/`curR` haven't changed significantly.

### Packages Recommended
```yaml
dependencies:
  flutter:
    sdk: flutter
  riverpod: ^2.x          # State management
  http: ^1.x              # GeoJSON fetch
  google_fonts: ^6.x      # OR embed fonts manually
  flutter_animate: ^4.x   # Declarative animations
  path_provider: ^2.x     # File handling
  file_picker: ^6.x       # Company list upload
```

---

*End of NEXUS Flutter Conversion Reference*
*Generated: April 2026*