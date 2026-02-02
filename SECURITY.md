# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.1.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability in SolidObserver, please report it by emailing **bartek.ozdoba@gmail.com**.

**Please do not open a public issue for security vulnerabilities.**

### What to Include

- Description of the vulnerability
- Steps to reproduce the issue
- Potential impact
- Any suggested fixes (optional)

### Response Timeline

- You'll receive an acknowledgment within 48 hours
- We'll provide a detailed response within 5 business days
- We'll work with you to understand and address the issue

### Disclosure Policy

- Please allow us reasonable time to address the issue before public disclosure
- We'll credit you in the fix announcement (unless you prefer to remain anonymous)

## Security Best Practices

When using SolidObserver:

- Keep your Rails and Ruby versions up to date
- Regularly run `bundle audit` to check for vulnerable dependencies
- Use environment variables for sensitive configuration
- Enable HTTP Basic Auth for the web UI in production environments
- Review database retention settings to avoid storing excessive data

Thank you for helping keep SolidObserver and its users safe!
