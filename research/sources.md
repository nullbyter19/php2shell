# Sources

Order of trust for the talk: **official advisory > changelog > independent technical
analysis > security press**. Never cite press for a technical detail the advisory already
settles.

## Primary

| Source | URL | Use in the talk |
|---|---|---|
| GHSA-6wmf-4rv5-p3rp (CVE-2026-109619) | https://github.com/php/php-src/security/advisories/GHSA-6wmf-4rv5-p3rp | producer/consumer model, mitigations, validity limits |
| GHSA-w8hw-w9fx-j79w (CVE-2026-109618) | https://github.com/php/php-src/security/advisories/GHSA-w8hw-w9fx-j79w | OOM strategies, `longjmp`, susceptible SAPIs |
| PHP 8.5.12 changelog | https://www.php.net/ChangeLog-8.php#8.5.12 | list of fixes |
| The PHP Foundation, 2026-10-21 | https://thephp.foundation/blog/2026/10/21/todays-php-security-release-and-how-were-strengthening-php-security/ | disclosure process context |
| Manual: session.upload-progress | https://www.php.net/manual/en/session.upload-progress.php | documented handler behaviour |
| Manual: session.configuration | https://www.php.net/manual/en/session.configuration.php | default values quoted in the lab |

## Secondary (technical)

| Source | URL | Note |
|---|---|---|
| Tenable | https://www.tenable.com/cve/CVE-2026-109619 | CVSS 2/3/4 vectors side by side |
| VulnCheck | https://www.vulncheck.com/blog/php2shell-vulnerabilities | detail on strategies and exploitation telemetry |
| Unit 42 | https://unit42.paloaltonetworks.com/cve-2026-109618-cve-2026-109619/ | includes a retraction — a good example of why we cite with dates |
| Wiz | https://www.wiz.io/blog/php2shell-php-rce | discovery narrative |
| Cloudflare (WAF) | https://blog.cloudflare.com/php-vulnerabilities-waf-protection/ | perimeter mitigations |
| Check Point | https://blog.checkpoint.com/security/php2shell-what-we-know-about-the-leaked-critical-php-vulnerabilities-cve-2026-109618-cve-2026-109619/ | leak timeline |

## Public PoCs — **reference only, never copied**

Several public repositories (21–26 Oct 2026) carry chains for different SAPIs. The exploit
in this talk is written from scratch. These sources serve to:

- confirm a path is plausible before investing lab time;
- compare results (if our leak fails and theirs works, the problem is ours);
- **not** to support slides that claim "we discovered this".

If any of our technique matches a published one, we say so on stage. Honest attribution is
what separates a research talk from a copy-paste talk.

## Citation rules for slides

1. Every number (CVSS, host counts, success rate) carries a source and a date on the slide.
2. Distinguish "the advisory says" from "we measured in our lab".
3. If a source was retracted or updated, use the current version and mention it.
