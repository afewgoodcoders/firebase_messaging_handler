# Security Policy

## Supported Versions

The latest stable release receives security fixes first. Older versions may receive fixes at our discretion, but users should plan to upgrade to the newest stable package version.

## Reporting a Vulnerability

Do not open a public GitHub issue for suspected security vulnerabilities.

Please report vulnerabilities by emailing `dev@afewgoodcoders.com` with:

- A clear description of the issue
- Affected package version
- Platform and environment details
- Reproduction steps or proof of concept
- Any suggested mitigation

We will acknowledge receipt, assess impact, and coordinate a fix and disclosure timeline.

## Scope Notes

Security-sensitive areas for this package include:

- Notification payload parsing and validation
- Background isolate execution paths
- Deep-link and action payload handling
- Web notification permission and service worker flows

Reports that include a minimal reproducible example are significantly easier to validate.
