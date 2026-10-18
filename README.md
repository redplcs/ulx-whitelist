<img src="workshop/icon.jpg" alt="ULX Whitelist icon" width="128" align="right">

# ULX Whitelist

Server access whitelist for Garry's Mod, managed through ULX/ULib. Allow players by SteamID or by group; everyone else is rejected on connect, before downloading any content.

Available on the [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3822151875).

ULX Whitelist is an unofficial module for ULX. It is not made by or affiliated with Team Ulysses.

## Features

- **Rejects players before they download anything.** The check runs in the `CheckPassword` hook, at the same point where the server password is checked.
- **Managed with ULX.** Let whole groups in with an access string, or add individual players with commands from chat, the console or RCON.
- **Its own tab in the ULX menu**, next to Bans: see who can join, search, add and remove players.
- **Accepts every common SteamID format:** `STEAM_0:X:Y`, `STEAM_1:X:Y`, SteamID64 and `[U:1:N]`. (`ulx adduserid` silently treats a SteamID64 as a UniqueID; these commands convert it.)
- **Works with or without `sv_password`.**
- **Kicks players who lose access** while the whitelist is on (optional).
- **Tells admins about rejected connections**, so they can whitelist a friend right away (optional).
- **Fails closed:** if the check runs into an error, the player is rejected.
- **No data files of its own.** Everything is stored in ULib's users and groups.

## Requirements

- [ULX](https://steamcommunity.com/sharedfiles/filedetails/?id=557962280) and [ULib](https://steamcommunity.com/sharedfiles/filedetails/?id=557962238). Built against ULX 3.81 and ULib 2.72.
- `sv_lan 0`: the whitelist relies on SteamIDs verified by Steam.

## Installation

### Steam Workshop

Add [ULX Whitelist](https://steamcommunity.com/sharedfiles/filedetails/?id=3822151875) to your server's Workshop collection, next to ULX and ULib.

### Manually

Download this repository (**Code → Download ZIP**) and extract it into `garrysmod/addons/`, or clone it there:

```sh
git clone https://github.com/redplcs/ulx-whitelist.git garrysmod/addons/ulx-whitelist
```

Then restart the server fully; a map change is not enough. The console should show:

```
[ULX Whitelist] v1.0.0 loaded. Whitelist is ON.
```

## Quick start

The whitelist is on as soon as the addon is installed. Admins and superadmins can join by default, and the server console always has full ULX access, so you cannot lock yourself out.

1. Let a group in:

   ```
   ulx addgroup resident
   ulx groupallow resident "ulx whitelisted"
   ulx adduserid STEAM_0:1:12345678 resident
   ```

2. Or add people one by one, even before they first join:

   ```
   ulx whitelistid STEAM_0:1:12345678
   ```

   The same player can be given as `76561197984957085` or `[U:1:24691357]`. In chat: `!whitelistid STEAM_0:1:12345678`.

3. Optionally change the message rejected players see:

   ```
   ulx whitelist_message "This server is invite-only. Ask for an invite in our Discord."
   ```

## Commands

| Command | Chat | Default access | What it does |
|---|---|---|---|
| `ulx whitelist <player>` | `!whitelist` | superadmin | Adds a player who is on the server, for example while the whitelist is off. |
| `ulx whitelistid <steamid>` | `!whitelistid` | superadmin | Adds a SteamID, including players who have never joined. |
| `ulx unwhitelist <player>` | `!unwhitelist` | superadmin | Removes the player's personal whitelist entry. If that was their only way in, they are kicked (see `ulx whitelist_kick`). |
| `ulx unwhitelistid <steamid>` | `!unwhitelistid` | superadmin | The same, by SteamID. |
| `ulx whitelistcheck <steamid>` | `!whitelistcheck` | admin | Shows whether a SteamID can join and why. |
| `ulx whitelistshow` | `!whitelistshow` | admin | Opens the Whitelist tab. From the server console or RCON it prints everyone who can join: the groups with access, the players who get in through a group or a personal entry, and explicit denies. |

The chat line of these commands is hidden, so SteamIDs don't end up in chat. Changes are echoed silently: only the caller and players with `ulx hiddenecho` see them, and they are written to the ULX log.

If a player can still join through their group after `unwhitelist`, the command says so and prints the line that blocks them.

## The Whitelist tab

ULX Whitelist adds a **Whitelist** tab to the ULX menu (`!menu`), after Bans. Anyone with `ulx whitelistshow` can open it, and `!whitelistshow` opens the menu straight on this tab. It shows:

- everyone who can join, how they get in (a personal entry or a group), and who is explicitly denied, with a search box;
- the groups that have the access;
- a switch for `ulx whitelist_enabled`.

To add a player, type their SteamID in the box at the bottom and press **Add**. To take a personal entry off the whitelist, select it and press **Remove**. Right-click a player to copy their SteamID, deny them access or lift a deny.

Every button runs the matching ULX command, so it needs the same access and is logged the same way. The list updates by itself when permissions change.

## Who can join

While the whitelist is on, a player can join if ULib grants them the `ulx whitelisted` access. ULX Whitelist applies ULib's usual rules before the player is even on the server:

1. A personal deny beats everything.
2. Then personal allows. `ulx whitelistid` adds one.
3. Then the player's group and every group it inherits from.

SteamIDs that ULib doesn't know are treated as members of `user`. The Whitelist tab, or `ulx whitelistshow` in the server console, shows the result for everyone ULib knows.

By default `admin` has the access, and `superadmin` gets it through inheritance. ULib applies this default only when it first sees the access string; after that, your changes in XGUI or with `ulx groupallow` / `ulx groupdeny` are kept.

To keep out someone who has access through their group:

```
ulx userdenyid STEAM_0:1:12345678 "ulx whitelisted"
```

## Settings

| Setting | Default | Description |
|---|---|---|
| `ulx whitelist_enabled` | `1` | Only players with `ulx whitelisted` can join. |
| `ulx whitelist_message` | `You are not on this server's whitelist.` | Message shown to rejected players. |
| `ulx whitelist_kick` | `1` | Kick connected players who lose access while the whitelist is on: when their entry or their group's access is removed, and when the whitelist is turned on. |
| `ulx whitelist_notify` | `1` | Tell admins who can run `ulx whitelistid` about rejected connections, at most once a minute per SteamID. |

Change them from the console or RCON, for example `ulx whitelist_enabled 0`. ULX saves the new value to `data/ulx/config.txt`. Each setting has its own access string (`ulx whitelist_enabled` and so on), which only superadmins have by default. The underlying cvars are `ulx_whitelist_enabled`, `ulx_whitelist_message`, `ulx_whitelist_kick` and `ulx_whitelist_notify`.

## How it works

- The check runs in `CheckPassword`. ULX Whitelist gives no answer for allowed players, so other hooks (such as ULib's ban check) and `sv_password` still apply. Whitelisted players still need the password if you set one; everyone else is rejected even with the right password.
- Nothing is checked if the addon fails to load, so look for the startup line after installing or updating.
- `CheckPassword` doesn't run for the listen server host or in single player, and bots are never checked.

## Logs

Everything is written to the server console and to the ULX log (`data/ulx_logs/`), prefixed with `[ULX Whitelist]`:

```
[ULX Whitelist] v1.0.0 loaded. Whitelist is ON.
[ULX Whitelist] Rejected Stranger (STEAM_0:1:1099): not whitelisted (group 'user')
[ULX Whitelist] Kicked Guest (STEAM_0:1:6001): no longer whitelisted
```

## Known conflicts

[Wordlist Kicker for ULX](https://github.com/Decicus/Wordlist-Kicker-for-ULX) registers `ulx whitelist`, `ulx unwhitelist`, `ulx whitelistid` and `ulx unwhitelistid` for its nickname filter. Only one addon can own a command name, so don't run both. ULX Whitelist prints a warning at startup if another addon has registered one of its commands.

## For developers

The server side exposes a small API in the `ULXWhitelist` table:

| Function | Returns |
|---|---|
| `ULXWhitelist.NormalizeSteamID( input )` | `"STEAM_0:X:Y"`, or `nil` if `input` is not a SteamID |
| `ULXWhitelist.CheckSteamID( steamid, ip )` | `allowed, reason`; `ip` is optional |
| `ULXWhitelist.Grant( steamid )` | `true` if a personal entry was added |
| `ULXWhitelist.Revoke( steamid )` | `true` if a personal entry was removed |
| `ULXWhitelist.List()` | `{ everyone, groups, allowed, denied }`: who can join, as printed by `ulx whitelistshow` |
| `ULXWhitelist.IsEnabled()` | whether the whitelist is on |
| `ULXWhitelist.Enforce( ply )` | `true` if the player was kicked |

The access string is `ULXWhitelist.ACCESS` (`"ulx whitelisted"`). All commands also work over RCON, so a Discord bot or a control panel can call them.