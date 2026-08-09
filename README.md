# OpenBoard

A fast, beautiful native iOS/iPadOS client for US Chess Federation (USCF) ratings.
Built with SwiftUI, Swift 6, SwiftData, and the iOS 26 Liquid Glass material language.

The official US Chess app is an event check-in tool; the ratings website
(ratings.uschess.org, "MUIR") is slow on mobile. OpenBoard is the app chess
parents and players actually want — your player's ratings as glowing chess-clock
digits, one-field search, full rating cards, live tournament crosstables, and a
watchlist that notifies you when a followed player's rating changes.

<p>
  <img src="Screenshots/iphone-mycard.png" width="240">
  <img src="Screenshots/iphone-event.png" width="240">
  <img src="Screenshots/iphone-watchlist.png" width="240">
</p>

---

## Build & run

```bash
brew install xcodegen          # if not already installed
cd OpenBoard
xcodegen generate             # writes OpenBoard.xcodeproj from project.yml
open OpenBoard.xcodeproj       # ⌘R on an iOS 26 simulator
```

- **Xcode 26+, Swift 6.** Deployment target iOS/iPadOS 26.0.
- **Zero third-party dependencies.** No SPM packages, no CocoaPods.
- Universal: iPhone (`TabView`, 4 tabs) and iPad (`NavigationSplitView`, sidebar + detail).

### Live vs mock — one flag

The whole app runs on either live network data or bundled seed data, switched in
**one place** — `AppEnvironment.dataSource` in `Services/RatingsProviding.swift`:

```swift
static var dataSource: DataSource {
    ProcessInfo.processInfo.arguments.contains("-mock") ? .mock : .live
}
```

- **Default = live.** The API probe (below) confirmed the backend is reachable and
  stable, so shipping defaults to `LiveRatingsService`.
- **`-mock` launch argument** forces `MockRatingsService` (used by UI tests, SwiftUI
  previews, and the screenshot pipeline). The app compiles, runs, and demos
  perfectly with **zero network** in this mode.

Everything above the service protocol (`RatingsProviding`) is identical in both
modes — the UI only ever sees the domain models.

---

## API probe findings

The app talks to **MUIR** (*Member Uploads, Information, and Reporting*) — US Chess's
official ratings/reporting platform, built by their partner Leago
([announcement](https://new.uschess.org/news/introducing-muir-member-uploads-information-and-reporting)).
It publicly serves an OpenAPI/Swagger spec but isn't a formally documented,
supported public API, so it's treated as subject to change.

- **Spec:** https://ratings-api.uschess.org/swagger/v1/swagger.json
- **Reference client (unofficial, Go):** https://github.com/mikeb26/uschess-go

> **The task's first step was to probe the backend before writing any UI.** Here's
> what was found on **2026-08-08** using a real US Chess member ID and event ID.
> (All IDs/names below — and everywhere in this repo — are synthetic samples; no
> real member's data is committed.)

### The candidate endpoints from the spec all 404'd…

Every path in the original prompt (`/players/{id}`, `/player/{id}`, `/search`,
`/events/{id}`, `/openapi.json`, `/docs`, …) returned **404**. But `/swagger`
returned a **301** redirect — a lead.

### …but the service publishes a full Swagger/OpenAPI spec

```
https://ratings-api.uschess.org/swagger/index.html      → Swagger UI
https://ratings-api.uschess.org/swagger/v1/swagger.json → OpenAPI v1 (226 KB, ~50 paths)
https://ratings-api.uschess.org/swagger/v2/swagger.json → OpenAPI v2 (members-focused)
```

The real API is **versioned under `/api/v1`** (not the bare paths the spec guessed).
All of these returned **200 with real JSON**:

| Purpose | Endpoint (base `https://ratings-api.uschess.org/api/v1`) |
|---|---|
| Player profile | `GET /members/{memberId}` |
| Player's rated events | `GET /members/{memberId}/events` |
| Player's rating history (pre→post per section) | `GET /members/{memberId}/sections` |
| Name / ID search | `GET /members?search={query}` |
| National + per-state population totals (for percentiles) | `GET /members/max-ranks` |
| Tournament (with section list) | `GET /rated-events/{eventId}` |
| Section metadata | `GET /rated-events/{eventId}/sections/{number}` |
| **Crosstable standings** (with round-by-round) | `GET /rated-events/{eventId}/sections/{number}/standings` |

### Actual JSON shapes

**`/members/{memberId}`** — ratings are an *array* keyed by `ratingSystem`
(`R`/`Q`/`B`/`OR`/`OQ`/`OB`), not the nested object the domain model uses
(values below are synthetic samples):

```json
{
  "id": "90000001", "firstName": "ALEX", "lastName": "RIVERA",
  "stateRep": "NJ", "rank": 58224, "stateRank": 2204, "gender": "Female",
  "ratings": [
    { "ratingSystem": "R", "rating": 383, "gamesPlayed": 5, "isProvisional": true, "floor": 131 },
    { "ratingSystem": "Q", "rating": 379, "gamesPlayed": 5, "isProvisional": true, "floor": 131 },
    { "ratingSystem": "B", "isProvisional": true }
  ]
}
```

**`/members/{memberId}/sections`** — this, not `/events`, carries the pre→post rating
deltas, under `ratingRecords[].preRating/postRating` keyed by `ratingSource`:

```json
{ "items": [ {
  "sectionName": "Section 1 SS G/30 d5",
  "ratingRecords": [
    { "preRating": 322, "postRating": 420, "ratingSource": "R", "postProvisionalGameCount": 12 },
    { "preRating": 319, "postRating": 415, "ratingSource": "Q", "postProvisionalGameCount": 12 }
  ],
  "event": { "id": "900000000001", "name": "SAMPLE SCHOLASTIC OPEN 2026", "startDate": "2026-08-06" }
} ] }
```

**`/rated-events/{id}/sections/{n}/standings`** — paginated (response has `items`,
`hasNextPage`, `offset`, `pageSize`); each standing has `ordinal`, `score`
(a `Double`), a `ratings[]` array (same pre/post shape), and full `roundOutcomes[]`
with opponent member IDs and colors. This is what powers the crosstable, including
the iPad's round-by-round pills.

### Notable quirks handled in the decoding layer

- **Query parameters are PascalCase, and unknown ones are silently ignored.** Fuzzy
  name search is `?Fuzzy=`, and pagination is `?Offset=`/`?Size=` — *not* `search`,
  `offset`, `pageSize`. (A wrong param name doesn't error; it just returns the
  default top-rated list / default page — an easy, silent bug. Confirmed against
  the spec + live API.)
- **Names are ALL CAPS** for many records (`"MAGNUS CARLSEN"`). `USCFMapper` title-cases
  shouty names and leaves mixed-case ones alone.
- **Ratings are arrays**, flattened into the `Ratings` struct by `ratingSystem` code.
- **`ratingSource` vs `ratingSystem`** — the same concept is named differently on
  member-sections vs standings; the DTO exposes a unified `system` accessor.
- **Percentiles aren't returned** — computed from `rank` + `/members/max-ranks`
  population totals (national = `76,379`; NJ = `2,711`).
- **Score is numeric** (`4.0`, `2.5`); formatted to `"3.0"` display strings.
- No auth is required; the app sends `User-Agent: OpenBoard-iOS/1.0`.

### What was mocked

Nothing had to be. Every screen's data maps to a live endpoint. `MockRatingsService`
exists only as the offline/demo/test data source, built entirely from **synthetic
sample players and events** (e.g. member `90000001`, event `900000000001`) — no
real member's data is baked into the app.

> **Caveat:** MUIR publishes a Swagger spec but isn't a formally supported public
> API, so it can change without notice. All endpoint knowledge is isolated to
> `Services/LiveRatingsService.swift` +
> `Services/USCFAPITypes.swift`, so a rename is a one-file fix that never touches
> the domain models or the UI. The fixtures in `OpenBoardTests/Fixtures/` mirror
> the real API's JSON *shape* using synthetic sample values, and back the decoding
> tests.

---

## Architecture

Lightweight **MV** (Model–View) — no view-model ceremony.

```
OpenBoard/
├── App/            OpenBoardApp, AppModel (@Observable), RootView (tab vs split routing)
├── Models/         Domain contract: Player, Ratings, ChessEvent, Standing, ClassTitle …
├── Services/       RatingsProviding protocol + Live / Mock / Cached decorator,
│                   USCFAPITypes (wire DTOs + mapper), CacheStore (SwiftData),
│                   RefreshScheduler (BGAppRefreshTask + notifications)
├── Components/     Theme, ClockDigits, Sparkline, RatingCards, Badges, ShareCard, States
└── Views/          MyCardView, SearchView, PlayerProfileView, CrosstableView,
                    WatchlistView, EventsView
```

- **`RatingsProviding`** is the seam. `LiveRatingsService` (an `actor`) talks HTTP;
  `MockRatingsService` serves seed data; `CachedRatingsService` wraps either one with
  a SwiftData cache.
- **Concurrency:** `async/await` throughout. The networking layer is an `actor` with
  **in-flight request de-duplication** (identical URLs share one call). The cache is a
  SwiftData `@ModelActor`. No Combine.
- **Caching (stale-while-revalidate):** player/event responses are persisted with a
  **5-minute TTL**. Fresh entries serve instantly with no network; stale entries paint
  immediately, then refresh in the background. On failure the last cached copy is
  served, and the UI shows *"showing cached from 3:12 PM"* with Retry.
- **Persistence:** SwiftData models `WatchedPlayer`, `CachedPayload`, `RecentSearch`.
  The app launches with an empty watchlist — the user searches for their own
  player (the first one watched becomes primary / "My Card") and looks up
  tournaments by event ID. Nothing is pre-seeded.
- **Background refresh:** `BGAppRefreshTask` (`com.iliapavlov.openboard.refresh`) polls
  followed players ~2×/day; a changed rating fires a local notification
  (*"Alex's new rating: 420 (+98) 🎉"*) and badges the Watching tab. Manual
  pull-to-refresh triggers the same check.

## Liquid Glass design

- **Chrome uses real system glass:** the tab bar, sidebar, and toolbars are standard
  components, so they get Liquid Glass for free — never custom-drawn.
- **`glassEffect(...)`** on the hero rating "clock face" cards; **`GlassEffectContainer`**
  groups them for correct blending. `.buttonStyle(.glass)` / `.glassProminent` on the
  Watch toggle, section actions, and CTAs.
- Glass stays on the chrome layer only; content stays opaque and high-contrast
  (no glass-on-glass). System materials handle Reduce Transparency / Increase Contrast.
- **Signature element:** ratings rendered as zero-padded chess-clock digits in
  monospaced SF, gold with a soft glow (`ClockDigits` / `HeroClockDigits`); unrated
  shows a ghosted `– – – –`.
- **Palette:** background `#0B0E13`, cards `#141922`, hairlines `#26303F`, gold
  `#E9B44C`, teal `#3DBCCB`, up-green `#41D18B`, down-red `#F0716E` — all adaptive
  for light mode via `Color(dynamicDark:light:)`.
- **Charts:** rating sparkline is Swift Charts `LineMark` + gradient `AreaMark` with a
  dotted last point.
- **Haptics:** `.sensoryFeedback` on the watch toggle and pull-to-refresh completion.

## The dual live-vs-published rating (a core feature)

USCF publishes official ratings on a delay, which confuses everyone. The player
profile shows **LIVE** (post-event, gold clock digits) and **PUBLISHED** (ghosted)
side by side, with a note when they differ — see `DualRatingCard` and the profile
screenshot below.

## Accessibility

- Dynamic Type through XXL — clock digits scale via `@ScaledMetric` and layouts reflow.
- VoiceOver labels read naturally (*"Regular rating three hundred eighty-three, up ninety-eight"*).
- Reduce Motion disables the skeleton shimmer; system materials cover the rest.
- All strings are `String(localized:)` / catalog-ready; US English ships.

---

## Tests

```bash
xcodebuild test -project OpenBoard.xcodeproj -scheme OpenBoard \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=26.5'
```

- **Unit (Swift Testing, 15 tests / 4 suites):** decoding of **synthetic fixtures that
  mirror the real API shape** (member, sections, standings-with-rounds, search,
  max-ranks), USCF class-title mapping (17 parameterized cases), delta math +
  clock-digit formatting, and cache TTL logic (fresh/stale/miss + stale-served-on-failure).
- **UI (XCTest):** search → player profile → crosstable happy path on the mock service.

All green on the iOS 26.5 simulator.

## Definition of done — status

- ✅ Builds clean on iOS 26 simulator (Swift 6, no warnings-as-errors surprises).
- ✅ Runs fully on mock data with **zero network** (`-mock`).
- ✅ Flips to live data by changing one `AppEnvironment` flag — **and the probe
  succeeded, so live is already the default.**
- ✅ Unit + UI tests pass.
- ✅ Dark-mode screenshots of every screen on iPhone 16 Pro and iPad Pro 13".

## Screenshots

### iPhone 16 Pro
| My Card | Crosstable | Watchlist | Search |
|---|---|---|---|
| ![](Screenshots/iphone-mycard.png) | ![](Screenshots/iphone-event.png) | ![](Screenshots/iphone-watchlist.png) | ![](Screenshots/iphone-search.png) |

Player profile (dual live/published): ![](Screenshots/iphone-profile.png)

### iPad Pro 13" (NavigationSplitView)
| My Card | Player profile | Crosstable |
|---|---|---|
| ![](Screenshots/ipad-mycard.png) | ![](Screenshots/ipad-profile.png) | ![](Screenshots/ipad-event.png) |

---

## References & prior art

- **MUIR announcement** — https://new.uschess.org/news/introducing-muir-member-uploads-information-and-reporting
- **Live OpenAPI/Swagger spec** — https://ratings-api.uschess.org/swagger/v1/swagger.json
- **`uschess-go`** (unofficial open-source Go client) — https://github.com/mikeb26/uschess-go
- **glitchess.com** — a similar (closed-source) product, noted as inspiration for future features.

### Possible future features
Not built yet — candidates inspired by similar trackers:
- Head-to-head compare between two watched players.
- Rating projection / "what a result would do to your rating" estimator.
- Per-variant history charts (Quick/Blitz), not just Regular.
- Affiliate/club pages and event discovery (the MUIR API exposes `/affiliates` and
  `/rated-events`), replacing the placeholder that used to live on the Watchlist.

---

*Not affiliated with or endorsed by the US Chess Federation. Data comes from the
MUIR backend, which is not a formally supported public API and may be inaccurate or
unavailable.*
