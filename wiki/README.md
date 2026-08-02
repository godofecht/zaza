# Zaza Wiki Site

This folder contains the static tutorial site for Zaza.

The writing style should stay simple and direct:

- short steps
- plain language
- tutorial first
- reference second
- no emojis
- no em dashes

## Run locally

```bash
cd wiki
zig run ../build_lib/static_server.zig -- serve . 8000
```

Open `http://localhost:8000`.

## Files

- `index.html`: page shell and layout
- `styles.css`: tutorial site styling
- `app.js`: tutorial content, navigation, and search

Keep API tutorials in sync with `docs/API.md` and `docs/SYNTAX_REFERENCE.md`.
For example, artifact staging belongs in both the reference docs and the
interactive `artifact-copies` tutorial card.
