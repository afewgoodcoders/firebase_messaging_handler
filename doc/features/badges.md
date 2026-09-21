---
layout: page
title: Badges
---

# Badges

Direct app-icon badge mutation is implemented by the package's iOS native
bridge. Android launcher badges are not exposed as a reliable direct mutation
capability because behavior varies by launcher and notification state. Web,
macOS, Windows, and Linux report the capability as unsupported.

Query `getCapabilities()` or `runDiagnostics()` before exposing badge controls.
The legacy Android-named helpers remain source-compatible but return no badge
value unless the runtime reports support.

Validate iOS behavior on a physical device.
