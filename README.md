# Planty

A gamified plant care app for iPhone: every real plant becomes a living character in your virtual garden.

## Structure

```
Planty/                 iOS app (SwiftUI)
  App/                  entry point, session routing, tab bar
  Core/DesignSystem/    colours, type, buttons, cards, mood badge, plant avatar
  Core/Backend/         Supabase configuration
  Features/             Authentication, Onboarding, Garden, other tabs
  Resources/            Localizable.xcstrings (English, German, Russian)
PlantyTests/            app unit tests
Packages/PlantyKit/     domain rules with no UI: care engine, mood, XP, levels (+ tests)
supabase/migrations/    database schema, Row Level Security, XP and achievement rules
supabase/tests/         database security tests
docs/care-engine.md     the care, mood and XP rules in plain words
project.yml             XcodeGen spec (the .xcodeproj is generated, not committed)
```

## Getting started (Mac)

Requirements: Xcode 16 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```sh
xcodegen generate
open Planty.xcodeproj
```

Pick your team under Signing & Capabilities, then run on a simulator or an iPhone.

## Supabase setup

1. Apply the schema: open the Supabase dashboard → SQL Editor, paste `supabase/migrations/20261107120000_init.sql`, run it. (Or with the Supabase CLI: `supabase link` then `supabase db push`.)
2. Authentication → Sign In / Providers:
   - **Email**: on. Keep "Confirm email" on.
   - **Anonymous sign-ins**: on (guest mode).
   - **Apple**: on, once the Apple Developer account exists (needs the Services ID and key from Apple).
3. The app reads the project URL and publishable key from `Config/Planty.xcconfig`. Never put a secret key in the app.

## Tests

| What | Where it runs | Command |
| --- | --- | --- |
| Care engine, mood, XP | Linux or Mac | `swift test --package-path Packages/PlantyKit` |
| Database security and XP rules | any PostgreSQL 16 | `DATABASE_URL=postgres://… scripts/test-db.sh` |
| App build and unit tests | Mac | `xcodebuild test -scheme Planty -destination 'platform=iOS Simulator,name=iPhone 16'` |

GitHub Actions runs all three on every pull request.
