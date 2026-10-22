# Port Viewer

A small native macOS menu bar app that shows which processes are listening on TCP ports and lets you stop them with one click.

## Features

- Lives in the menu bar (no Dock icon)
- Lists every listening TCP port with app icon, name, PID and command line
- Detects websites: known dev servers (Vite, Next.js, Astro, Nuxt, Angular, …) get a tag, and any port that answers with HTML gets an "Open in browser" button
- 🔒 / 🌐 badge shows whether a port is bound to localhost only or to all interfaces
- Two-step kill button (click ✕, then **Kill**; hold ⌥ to force-kill with SIGKILL)
- Processes owned by root or other users prompt for an administrator password
- Right-click a row: open `http://localhost:<port>`, copy port/PID, reveal in Finder, terminate or force kill
- Filter by port, app name, PID or command
- Auto-refreshes every 5 seconds, ⌘R to refresh manually
- Launch at Login toggle (gear menu)

## Build

Requires macOS 14+ and the Xcode command line tools.

```sh
./build.sh            # builds "build/Port Viewer.app"
./build.sh --install  # also copies it to /Applications and launches it
```

For development, `swift run` launches the app directly from the package.
