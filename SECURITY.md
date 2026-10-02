# Security

## Report a vulnerability

Report vulnerabilities privately through [GitHub's private vulnerability reporting](https://github.com/YZXBiz/copytrading/security/advisories/new). Do not post vulnerability details in a public issue or discussion.

Keep reports minimal and do not include credentials, private source messages, provider requests or responses, broker records, databases, or full logs. For ordinary bugs, use the repository [bug report form](https://github.com/YZXBiz/copytrading/issues/new?template=bug_report.yml) and include only sanitized details.

## Preview scope

The developer preview is unsigned and requires Apple Silicon with macOS 26 or later. Restore and update paths have local implementation and test evidence, but clean-device installation, signed and notarized distribution, and trusted signed-update handoff remain unqualified. This preview is not qualified for production or live trading. See [validation](docs/validation.md) and [release instructions](docs/releases.md) for current evidence and gates.

The app stores operational data and credentials locally. Treat captured source text and model output as untrusted input. Keep credentials in owner-controlled storage and private operational data out of issues, pull requests, and test fixtures.
