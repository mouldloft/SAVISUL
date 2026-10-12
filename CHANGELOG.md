# Changelog

## 2.2

### New

- Live wallpaper: sakura drawn live behind SAVISUL's panel, on the desktop, or both. Three scenes: a bonsai, a cherry tree on a grassy hill under snowy mountains, and a bonsai on a hilltop. Petals fall from the tree on a breeze that never repeats, so there is no loop and no seam. Light under the pointer makes the wallpaper glow where the pointer is, and petals drift away from it. Cards over the wallpaper turn to frosted glass so text stays readable. In Settings.
- The panel moves and resizes: drag it by its header, resize it by its right and bottom edges. It reopens where you left it, and brought back near the menu bar icon it docks there again.

### Better

- Face Unlock asks for everything it needs while you are there: the camera, Accessibility to type your password at the lock screen (clearing an entry an update left stale, which still looked switched on), and opening at login, so it runs after a restart. After a restart macOS asks for the password once; from the next lock your face opens the Mac.

### Download

[SAVISUL-2.2.dmg](https://github.com/mouldloft/SAVISUL/releases/latest/download/SAVISUL-2.2.dmg) for macOS 14.2 or later on Apple silicon.

The build is signed locally and is not notarized. See the installation notes in the README.

## 2.1

### New

- Face Unlock: lock the Mac, look at it, and it opens in about a second. A padlock under the notch turns into a scanning ring, then a green check. Your eyes have to be open on the screen, it can also wait for a blink, it learns your face over time and knows you from across the desk. The faceprints and your password stay in this Mac's keychain. Off until you set it up in Features.

### Better

- Telegram calls: the island mutes every microphone at once, and its camera and hang-up buttons bring Telegram's call window forward, since Telegram lets no other app press its call buttons.
- Every call app comes forward on its call's own window.

### Download

[SAVISUL-2.1.dmg](https://github.com/mouldloft/SAVISUL/releases/download/v2.1/SAVISUL-2.1.dmg) for macOS 14.2 or later on Apple silicon.

The build is signed locally and is not notarized. See the installation notes in the README.

## 2.0

### New

- Context Actions
- Automation engine
- Multi-provider AI in the Mac app, including any OpenAI-compatible server and Ollama
- Live island: music, calls with their controls, volume and headphones, meetings, timers, downloads, agents and system events
- Command bar, clipboard history and Shelf
- Window management, the app switcher and per-app audio
- Browser extension for the notch and page tools

### Fixed in build 7

- Starts on macOS 14.2 and 15. The first 2.0 build could fail to start on anything before macOS 26.
- The timer's "min" label in the island no longer wraps onto two lines.

### Download

[SAVISUL-2.0.dmg](https://github.com/mouldloft/SAVISUL/releases/download/v2.0/SAVISUL-2.0.dmg) for macOS 14.2 or later on Apple silicon.

The build is signed locally and is not notarized. See the installation notes in the README.
