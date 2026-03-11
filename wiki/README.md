# Vex Wiki Site

This folder contains the static tutorial site for Vex.

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
