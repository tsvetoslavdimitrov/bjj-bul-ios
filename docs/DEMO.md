# Demo mode (DEBUG builds only)

For screenshots without signing in. Xcode → Product → Scheme → Edit Scheme → Run → Arguments → add:

- `-demo` — mock services with SAMPLE data, signed in as "Demo Coach" (owner of the mock gym, active subscription, terms accepted).
- `-demoScreen <name>` (with `-demo`) — opens one screen full-screen.

Screen names: `feed`, `explore`, `gymDetail`, `events`, `openMats`, `training`, `profile`, `bjjPass`, `myGym`,
`reports`, `kiosk`, `kioskGuest`, `askBJJ`, `notifications`, `composer`, `record`.

Without `-demoScreen` the normal tab bar opens with demo data. All demo data is fictional sample data
(gradient/SF Symbol images, no real people). Code: `BJJBul/Demo/` (all under `#if DEBUG`).
Simulator CLI: `xcrun simctl launch booted <bundle id> -demo -demoScreen reports`.
