# BJJ Bul — iOS MVP Spec (Phase 1)

## 1. Goals
- The most complete directory of BJJ gyms and coaches in Bulgaria (every city, not only Sofia).
- Let a user find a gym near them: map, city filter, schedule, prices, contacts.
- A profile for each coach: belt, lineage, achievements, classes taught.
- User accounts with belt rank and home gym (this sets up the Phase 2 social graph).
- Ship in Bulgarian and English.

## 2. Non-goals (Phase 1)
- Social feed, posts, likes, comments, following (Phase 2).
- Gyms editing their own pages through a claim flow (Phase 2; in Phase 1 the admin team edits).
- Competitions / Smoothcomp integration (Phase 3).
- Payments, class booking, check-ins, Android, web app.

## 3. User roles
| Role | Phase 1 abilities |
|---|---|
| Guest | Browse gyms, coaches, map, schedules |
| Registered user | Everything a guest can do, plus a profile (name, belt, stripes, home gym, avatar), favourite gyms, and "suggest an edit" |
| Admin (internal) | Add, edit and verify gyms, coaches and schedules through the Supabase dashboard or a small admin web tool |
| *Gym owner (Phase 2 hook)* | `Gym.ownerUserId` and `claimStatus` fields exist but aren't used yet |

## 4. Screens & navigation
Tab bar: **Explore (Map)** · **Gyms** · **Coaches** · **Profile**

1. **Onboarding / Language** — first launch: pick a language (BG/EN, defaulting to the device locale), allow location (optional), skip or sign in.
2. **Explore Map** — MapKit map with gym pins (clustered), a "near me" button and a city picker chip. Tap a pin to open a bottom sheet card (name, city, distance, belts/levels, next class), then tap the card to go to Gym Detail.
3. **Gym List** — search bar, city filter (all 28 oblasts and their major cities), filters (gi/no-gi, kids classes, women-only classes, open mat, price range). Sort by distance or name. Opens Gym Detail.
4. **Gym Detail** — photos, name, affiliation/team, address with an "Open in Maps" link, phone/email/website/Instagram/Facebook, prices (drop-in, monthly, kids), weekly schedule grid by day, the gym's coaches (opens Coach Detail), a favourite button, a "Suggest an edit" button, and a verified badge with the last-updated date.
5. **Schedule (inside Gym Detail)** — week view; each class shows its time, type (Gi/No-Gi/Kids/Fundamentals/Competition/Open mat), level and coach.
6. **Coach List** — search, filter by belt or city. Opens Coach Detail.
7. **Coach Detail** — photo, name, belt and degree, lineage (promoted by, which can link to another Coach), achievements list, gyms (opens Gym Detail), the classes they teach, socials.
8. **Auth** — Sign in with Apple (required on iOS when offering social login), Google, email magic link.
9. **Profile** — avatar, display name, belt with stripes, home gym (searchable picker), training since, favourite gyms. Edit Profile.
10. **Settings** — language override, account deletion (an App Store requirement), privacy policy, terms, contact/report.
11. **Suggest an edit** — a free-text form with an optional field, saved to a `suggestions` table for admin review.

## 5. Data model
```
City        { id, nameBg, nameEn, oblast, lat, lng, slug }
Gym         { id, name, nameLatin, cityId→City, address, lat, lng, affiliation?, phone?, email?,
              website?, instagram?, facebook?, photos[url], priceDropIn?, priceMonthly?,
              priceKids?, currency("BGN"/"EUR"), amenities[], hasKids, hasWomenOnly,
              verified:bool, lastVerifiedAt, source, createdAt, updatedAt,
              ownerUserId? (P2), claimStatus? (P2: none|pending|approved) }
Coach       { id, fullName, fullNameLatin, photoUrl?, belt(white..black|coral|red), degree(0-10),
              promotedByCoachId?→Coach, lineageText?, achievements[{title, year, event}],
              instagram?, userId?→User (P2 link), createdAt, updatedAt }
GymCoach    { gymId, coachId, role(head|instructor|assistant) }   // many-to-many
ClassSchedule { id, gymId, coachId?, weekday(1-7), startTime, endTime,
              type(gi|nogi|kids|fundamentals|competition|openmat|women), level(all|beginner|advanced),
              notes? }
User        { id(auth uid), displayName, avatarUrl?, belt, stripes(0-4), homeGymId?→Gym,
              trainingSince?, locale, favoriteGymIds[] (or a join table), createdAt,
              isPublic (P2), smoothcompProfileUrl? (P3 hook) }
Suggestion  { id, userId?, entityType, entityId, payload(json), status, createdAt }
```
Hooks for later phases: `Post`, `Follow`, `GymClaim` (P2) and `Competition`, `CompetitionResult` (P3) get their own tables later; the IDs above stay stable.

## 6. Recommended stack
- **iOS:** Swift 5.10+, **SwiftUI**, **iOS 17+** (lets us use the `@Observable` macro, the new MapKit SwiftUI API with `Map { Annotation }`, and SwiftData for caching).
- **Architecture:** MVVM with feature modules (`Explore`, `Gyms`, `Coaches`, `Profile`) and repositories behind protocols (`GymRepository`) so the backend can be swapped and mocked in tests. Swift Package Manager.
- **Maps:** MapKit (free, native, good Bulgarian coverage), with clustering and `MKLocalSearch` for geocoding.
- **Backend: Supabase** (recommended over Firebase):
  - The data is relational (gyms↔coaches↔schedules↔cities, lineage trees, and later follows and results), which fits Postgres much better than Firestore documents.
  - PostGIS gives "gyms near me" distance queries out of the box.
  - Row Level Security for the Phase 2 gym-owner claims; built-in auth (Apple/Google/email); Storage for photos; an official `supabase-swift` SDK.
  - Open source, so there's no lock-in, and it has an EU region (Frankfurt) for GDPR.
  - Firebase is still a fine alternative if real-time chat/feed becomes central, but geo and relational queries are clumsier there.
- **Caching/offline:** SwiftData cache of gyms/coaches; refresh when the app opens.
- **Analytics/crash:** TelemetryDeck (privacy-friendly, EU) + Sentry or Firebase Crashlytics.
- **CI:** Xcode Cloud or GitHub Actions + fastlane → TestFlight.

## 7. Localization
- String Catalogs (`Localizable.xcstrings`) with `bg` and `en`; Bulgarian is the primary market.
- Content fields: city names come in both languages (`nameBg`/`nameEn`); gym and coach names are stored as entered, plus an optional Latin transliteration (used for search and for the English UI).
- Search matches both Cyrillic and Latin (normalize with a transliteration table, e.g. "Пловдив" ↔ "Plovdiv").
- Prices: Bulgaria adopted the euro on 1 Jan 2026, so show **EUR**. A currency field stays on each price.
- Dates and times follow the locale (24h, weeks start on Monday).

## 8. Seeding gym data for all of Bulgaria
1. **Desk research (weeks 1–3):** compile a spreadsheet from Google Maps searches ("BJJ", "бразилско жиу-жицу", "граплинг", "ММА"), Instagram/Facebook pages, affiliation/team websites (e.g. Checkmat, Alliance, Gracie Barra affiliates in BG), the Bulgarian BJJ federation's member lists, and Smoothcomp academy listings for Bulgarian events (read manually).
2. **Cover every oblast center first** (28 cities), then smaller towns.
3. **Verify:** phone or message each gym to confirm the schedule, prices and coaches; set `verified=true` and `lastVerifiedAt`.
4. **Import:** CSV goes into Supabase through a script (geocode addresses with Apple or Nominatim; check coordinates by hand).
5. **Keep it fresh:** in-app "Suggest an edit", a reminder to re-verify every 6 months, and gym self-service in Phase 2.
6. Target for launch: at least 90% of known active BJJ academies, every one with contacts and a schedule.

## 9. Milestones (indicative, 1–2 developers)
| # | Weeks | Deliverable |
|---|---|---|
| M0 | 1 | Repo, Xcode project skeleton, CI, Supabase project + schema, design system |
| M1 | 2–3 | Gym list + Gym Detail + Schedule using seeded test data |
| M2 | 4 | Explore Map (clustering, near me, city filter) |
| M3 | 5 | Coaches list/detail, lineage |
| M4 | 6 | Auth (Apple/Google/email), Profile, home gym, favourites, account deletion |
| M5 | 7 | BG/EN localization, Suggest an edit, offline cache |
| M6 | 3–7 (parallel) | Data seeding & verification for all of Bulgaria |
| M7 | 8 | QA, TestFlight beta with ~5 gyms, App Store submission |

## 10. Phase hooks
- **P2 Social:** `User.isPublic`, `Gym.ownerUserId/claimStatus`, `Coach.userId`; the repository layer is ready for `PostRepository`.
- **P3 Competitions:** `User.smoothcompProfileUrl`; a placeholder "Competitions" tab behind a feature flag.
- **Smoothcomp API finding:** a quick web check found **no public, documented developer API**. Smoothcomp's docs only describe integrations into the platform (Stripe/PayPal keys, YouTube streaming) and **iframe embeds** of event content, and those embeds require the paid federation platform ([iframe embed docs](https://support.smoothcomp.com/article/235-embed-iframe), [federation platform](https://support.smoothcomp.com/article/178-how-to-create-your-federation-company-platform)). Next step: email Smoothcomp support about partner/API access, or partner with the Bulgarian federation (which may run a Smoothcomp federation platform). Fallbacks: entering events by hand, linking out to event pages, or scraping, which carries terms-of-service risk.

## 11. Open questions
1. App name/branding is final ("BJJ Bul")? Is there a logo or brand palette?
2. Include MMA/grappling/submission-wrestling gyms, or BJJ-only?
3. Who verifies gym data, and is there a budget for a data assistant?
4. Prices: show exact numbers or ranges? Will gyms agree to publish them?
5. Is there a relationship with the Bulgarian BJJ federation (data source + Smoothcomp access)?
6. Should coach profiles exist before the coach consents, given GDPR? Proposal: public professional info only, with a removal request option.
7. Monetization later (featured gyms, subscriptions)?
8. Apple Developer account: personal or company?
