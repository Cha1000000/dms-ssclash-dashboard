# SSClash Dashboard

A [DankMaterialShell (DMS)](https://github.com/AvengeMedia/DankMaterialShell) bar widget plugin for controlling a **Clash / Mihomo (SSClash)** router proxy dashboard directly from the top bar — no browser tab required.

## Features

- **Compact bar pill** with a globe icon and live connection status dot (green = router reachable, yellow = latency test running, red = unreachable). Right-click the pill to refresh immediately.
- **Wide 2-column popout dashboard** styled with your active DMS theme and a customizable neon accent color (default `#19b5ff`).
- **Mode switcher**: quickly toggle between `Rule`, `Global`, and `Direct` routing modes.
- **Fast node switching**: 3-column tile grid per group showing server names, protocol (`vless / xudp`, `hy2 / udp`, `wg / udp`, etc.), and color-coded ping badges.
- **Auto-fallback unlock**: fixed `Fallback` / `URLTest` groups show a lock button (`🔒`) — click it to unfix (`DELETE /proxies/{group}`) and restore automatic selection.
- **Latency testing**: test a single server, an individual group, or all groups at once (`⚡`).
- **Live search & regex filter**: filter proxy groups and servers by name or protocol.
- **Collapsible group cards**: collapsed groups display a compact row of color-coded status dots; collapsed state is persisted in DMS plugin settings.
- **Zero external CLI dependencies**: communicates directly with the Clash/Mihomo REST API via `XMLHttpRequest`.
- **Localization**: Russian and English (follows system locale).

## Requirements

- [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) `>= 1.2.0`
- A running Clash / Mihomo / SSClash instance with External Controller API enabled (e.g. `http://192.168.10.1:9090`)

## Installation

Clone into your DMS plugins directory as `ssclashDashboard`:

```sh
git clone https://github.com/Cha1000000/dms-ssclash-dashboard ~/.config/DankMaterialShell/plugins/ssclashDashboard
```

Then enable **SSClash Dashboard** in DMS Settings (`Mod + ,` → Plugins) and add the widget to your bar.

## Configuration

Available in DMS Settings (`Mod + ,` → Plugins → SSClash Dashboard):

| Setting | Default | Description |
|---|---|---|
| `apiUrl` | `http://192.168.10.1:9090` | Base URL of your router's Clash / Mihomo External Controller |
| `secret` | `""` | Optional Bearer token if controller `secret` is set |
| `accentColor` | `#19b5ff` | Neon highlight color for active servers, mode, and icon |
| `testUrl` | `https://www.google.com/generate_204` | URL used when measuring server latency |
| `testTimeout` | `5000` ms | Timeout per latency test (`1000`–`10000` ms) |
| `pollInterval` | `30` s | Background router status check interval (`10`–`120` s) |
| `showGlobalGroup` | `true` | Show or hide the `GLOBAL` selector group card |

## License

MIT
