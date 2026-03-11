# Security Policy

## Reporting a Vulnerability

Do not open a public issue for a security vulnerability.

Report vulnerabilities privately to:

- `security@vex.build`

Please include:

- affected version or commit
- platform and toolchain details
- reproduction steps
- impact assessment if known

You should receive an acknowledgement within 5 business days.

## Scope

Security reports are most useful for issues such as:

- arbitrary command execution beyond intended build steps
- dependency or fetch-path trust issues
- unsafe handling of generated files or staged artifacts
- local server or browser demo issues with security impact
- credential or secret exposure in build flows

## Supported Versions

The project is currently maintained on the default branch only.

| Version | Supported |
| --- | --- |
| `main` | yes |
| older commits | no |
