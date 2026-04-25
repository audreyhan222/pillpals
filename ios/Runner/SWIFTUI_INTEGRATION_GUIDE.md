# PillPal SwiftUI Integration Guide

This guide explains how to use the native SwiftUI screens that have been created for the PillPal iOS app.

## Files Created

### Views
- **`Views/LandingView.swift`** - The main landing screen with animation
  - Logo fades in and smoothly glides upward
  - Buttons fade in with a delay
  - Animated glow effect on the logo
  - Two action buttons: "I Take Medicine" and "I'm a Caregiver"

### Extensions
- **`Extensions/ColorExtensions.swift`** - Design system colors
  - Brand colors (Blue, Yellow)
  - Background gradients
  - Icon gradients
  - Text colors
  - Shadow colors

### Navigation
- **`Navigation/AppNavigation.swift`** - App-wide navigation structure
  - NavigationStack implementation
  - AppScreen enum for type-safe routing
  - Navigation preview

### App Entry
- **`App.swift`** - Main SwiftUI app entry point

## Animation Breakdown

### Timeline
1. **0ms** - App launches, logo appears with opacity: 0
2. **0-800ms** - Logo fades in (opacity: 0 → 1)
3. **1000ms** - Logo begins gliding upward
4. **1000-1800ms** - Logo slides up from y: 150 → 0
5. **1300-2100ms** - Buttons fade in (opacity: 0 → 1)
6. **Continuous** - Glow effect pulses with scale and opacity animation

### State Variables
```swift
@State private var showButtons = false          // Controls when buttons appear
@State private var logoOffset: CGFloat = 150   // Y position of logo (150 → 0)
@State private var logoOpacity: Double = 0     // Opacity of logo (0 → 1)
@State private var buttonOpacity: Double = 0   // Opacity of buttons (0 → 1)
@State private var animatingGlow = false       // Glow pulsing effect
```

## Color Reference

### Brand Colors
- **pillPalBlue**: `Color(red: 0.4, green: 0.7, blue: 1.0)`
- **pillPalYellow**: `Color(red: 1.0, green: 0.9, blue: 0.2)`

### Background Gradient
- **From**: Light blue `#B5E0FF` (0.71, 0.88, 1.0)
- **Via**: Soft yellow `#FFF5CC` (1.0, 0.96, 0.80)
- **To**: Light pink `#FFF3E0` (1.0, 0.95, 0.88)

### Logo Gradient
- **Start**: Blue `#C5E1FF` (0.77, 0.88, 1.0)
- **End**: Yellow `#FFEDCC` (1.0, 0.93, 0.80)

## How to Use

### Option 1: Replace Flutter with SwiftUI (Complete Rewrite)
1. Remove Flutter dependencies from iOS build
2. Use `App.swift` as the new app entry point
3. Add `@main` attribute to `PillPalApp` struct
4. Remove Flutter AppDelegate override

### Option 2: Hybrid Approach (Keep Flutter)
1. Create a Swift wrapper that bridges to Flutter
2. Use SwiftUI screens alongside Flutter screens
3. Implement navigation between both frameworks

### Option 3: Use as Reference
1. Keep your Flutter implementation
2. Use these SwiftUI files as design reference
3. Replicate the animation logic in Flutter/Dart

## Device Support

The views are optimized for:
- **iPhone 15 Pro Max** (design target)
- All iPhone models with notch/Dynamic Island support
- Landscape and portrait orientations (with minor adjustments)

Safe area is properly handled with `.ignoresSafeArea()` only on background.

## Animation Customization

To adjust animation timings, edit the `startAnimations()` function in `LandingView.swift`:

```swift
private func startAnimations() {
    // Logo fade in duration (default: 0.8s)
    withAnimation(.easeOut(duration: 0.8)) {
        logoOpacity = 1.0
    }
    
    // Delay before logo glides up (default: 1.0s)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        withAnimation(.easeOut(duration: 0.8)) {
            logoOffset = 0
            showButtons = true
        }
    }
    
    // Delay before buttons fade in (default: 1.3s)
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
        withAnimation(.easeOut(duration: 0.8)) {
            buttonOpacity = 1.0
        }
    }
}
```

## Button Functionality

Currently, the buttons don't have actions. To add navigation:

```swift
// I Take Medicine Button
Button(action: {
    navigationPath.append(.medicineTracker)
}) {
    // ... button content ...
}

// I'm a Caregiver Button
Button(action: {
    navigationPath.append(.caregiverDashboard)
}) {
    // ... button content ...
}
```

Update `AppNavigation.swift` to create the corresponding views.

## Preview Support

All views have `#Preview` blocks for Xcode canvas preview:
- Real-time preview updates
- Interactive testing without running the app
- Canvas can be opened with ⌘⌥↩ in Xcode

## Next Steps

1. Create additional screens (MedicineTrackerView, CaregiverDashboardView)
2. Implement button navigation
3. Add state management (ObservableObject, EnvironmentObject)
4. Connect to backend services
5. Test on iPhone 15 Pro Max simulator

## Notes

- No external dependencies required (uses only SwiftUI and Foundation)
- Fully compatible with iOS 16+
- All animations use standard SwiftUI animation primitives
- Accessibility considerations should be added for production
