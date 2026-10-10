# BJJ Bul — iOS

A nationwide Brazilian jiu-jitsu app for Bulgaria: a gym directory (map, city filter, schedules, prices, contacts), coach profiles, and user accounts with belt rank and home gym. A social feed (Phase 2) and Smoothcomp competitions (Phase 3) will follow.

See [docs/MVP_SPEC.md](docs/MVP_SPEC.md) for the full MVP spec.

## Stack
SwiftUI · iOS 17+ · MVVM · MapKit · Supabase (planned; mocks for now) · XcodeGen

## Setup
```bash
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # fill in Supabase URL + publishable key
brew install xcodegen && xcodegen
open BJJBul.xcodeproj
```
The `.xcodeproj` is generated from `project.yml` and isn't committed.

## Structure
- `BJJBul/App`: app entry point, root TabView, dependency container
- `BJJBul/Core/Models`: Gym, Coach, AppUser, ClassSchedule, City
- `BJJBul/Core/Services`: service protocols and mock implementations with sample data
- `BJJBul/Features`: Explore, Gyms, Coaches, Profile
- `BJJBul/Resources`: bg/en localization
- `BJJBulTests`: unit tests

The sample gyms in `MockData.swift` are placeholders, not real verified data.
