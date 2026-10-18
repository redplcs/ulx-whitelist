# Security Policy

ULX Whitelist decides who can join a server, so a bug in it can be a security hole. If you find a way around it, please report it privately, so that servers can update before the details become public.

## What to report

For example:

- a player without the `ulx whitelisted` access joins while the whitelist is on;
- a player changes the whitelist or its settings without the access ULX requires for that;
- an error or unusual input makes the check let a player in instead of rejecting them;
- a player without the `ulx whitelistshow` access can see the whitelist.

Not covered by this policy:

- bugs in ULX, ULib, Garry's Mod or Steam themselves; please report those to their developers;
- behaviour described in the README, for example that the listen server host and bots are not checked, that SteamIDs can't be trusted with `sv_lan 1`, or that connected players stay on the server with `ulx whitelist_kick 0`;
- server misconfiguration, such as giving `ulx whitelisted` to the `user` group;
- attacks that need admin access, the RCON password or access to the server's files.

## Supported versions

Only the latest version gets security fixes. The Steam Workshop always serves the latest version; if you installed the addon manually, update it from this repository.

## How to report

Please don't post security issues in public issues, discussions or Workshop comments.

Report them privately through GitHub: [Report a vulnerability](https://github.com/redplcs/ulx-whitelist/security/advisories/new). The same button is on the repository's security page. Only you and the maintainer see the report.

Please include:

- the versions of ULX Whitelist, ULX and ULib;
- the steps to reproduce the problem, and what happened compared with what you expected;
- the relevant settings (`ulx whitelist_*`, `sv_lan`) and log lines.

## What happens next

You'll get a reply within 7 days. Once the problem is confirmed, the fix is published on the Steam Workshop and GitHub, followed by a security advisory that describes the problem. The advisory credits you, unless you'd rather stay anonymous.

Please keep the details private until the fix is released. If 90 days pass without a fix, you're free to disclose the issue.
