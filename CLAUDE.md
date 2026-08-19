# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Flutter app "Blue Dot" (package name `dmm_delivery`) — a Dunedin/Auckland delivery app prototype with two roles, Customer and Rider, switchable at runtime from the app bar. Targets Android, iOS, and web.

## Commands

- Install deps: `flutter pub get`
- Run app: `flutter run`
- Analyze/lint: `flutter analyze`
- Run all tests: `flutter test`
- Run a single test file: `flutter test test/widget_test.dart`
- Format: `dart format .`

Lints come from `package:flutter_lints/flutter.yaml` via `analysis_options.yaml`; the analyzer excludes `build/**`, `android/**`, `ios/**`, `web/**`, `windows/**`, `macos/**`, `linux/**`.

## Architecture

**Prototype-driven UI.** `prototypeAssets/` contains the original static HTML/CSS mockups (`customer-home.html`, `customer-tracking.html`, `customer-receipt.html`, `rider-orders.html`, `rider-active.html`, `rider-earnings.html`, `styles.css`). Each Flutter screen under `lib/screens/` is a port of the corresponding HTML file, and design tokens in `lib/theme/app_colors.dart` are explicitly "lifted from prototypeAssets/styles.css". When changing visual design or adding a screen, check the matching HTML file first for the intended layout/spacing/copy before improvising.

**Single mutable state object, no external state package.** `lib/state/app_state.dart` defines `AppState extends ChangeNotifier`, holding all mock data (jobs, orders, trips, receipts, saved addresses) and cross-screen navigation state (`role`, `customerTabIndex`, `riderTabIndex`) as plain mutable fields. There's one `AppState` instance, created in `RootShell` (`lib/screens/root_shell.dart`) and passed down to every screen via constructor (`appState: appState`) — not via `Provider`/`InheritedWidget`/Riverpod. Screens rebuild via `ListenableBuilder(listenable: appState, ...)` in `RootShell`. Mutations go through methods on `AppState` (e.g. `switchRole`, `confirmDropoff`, `acceptJob`, `completeActiveJob`) that mutate fields directly and call `notifyListeners()`.

**Role-based tab navigation.** `RootShell` is the single `Scaffold` host: it swaps between two independent 3-tab `NavigationBar` sets (Customer: Home/Tracking/Receipt; Rider: Orders/Active/Earnings) based on `AppState.role`, using an `IndexedStack` so screen state survives tab switches. The role toggle lives in the `AppBar` actions.

**Data is all mock/static.** Models in `lib/models/` (`CustomerOrder`, `Receipt`, `RecentTrip`, `RiderJob`, `SavedAddress`) are plain immutable data classes with no serialization — there is no backend, network layer, or persistence. Sample data is hardcoded directly in `AppState` field initializers.

**Shared UI primitives** live in `lib/widgets/` (`PrimaryButton`/`SecondaryButton`, `PillBadge`, `SectionLabel`, `StatTile`, `SurfaceCard`, `WeeklyBarChart`) and pull styling from `lib/theme/app_colors.dart` / `lib/theme/app_theme.dart` rather than hardcoding colors inline — follow this pattern for new UI.

The `Inter` variable font is registered once in `pubspec.yaml` under multiple weights (400–800) pointing at the same variable font file (`assets/fonts/Inter-Variable.ttf`); reference weights via `TextStyle(fontWeight: ...)`, not separate font family names.
