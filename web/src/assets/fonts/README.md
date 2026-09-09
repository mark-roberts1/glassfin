# Space Grotesk

The interface and wordmark typeface, from the Glassfin style guide:

> Wordmark and interface type — Space Grotesk, 500 for the wordmark and 400 for
> running text. Fallback stack: Segoe UI, system-ui, sans-serif.

Two weights, latin subset only, `.woff2` only. Vendored rather than fetched:
the appliance this runs on may only ever see its own LAN, and a Jellyfin server
on the LAN is not the internet. A font that arrives over the network is a font
that is sometimes missing.

Extracted from `@fontsource/space-grotesk@5.3.0`
(`files/space-grotesk-latin-{400,500}-normal.woff2`). Licensed under the SIL
Open Font License 1.1 — see `LICENSE.txt`.
