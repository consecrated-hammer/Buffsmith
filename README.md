# Buffsmith

**Buffs and consumables, without the scavenger hunt.** A small out-of-combat
bar of clickable icons for the self-buffs, party buffs and bag consumables you
are missing.

> **Status: in development.** Buffsmith has not been released or published to
> CurseForge, and its settings and preview have so far been checked by unit
> tests only, not in a live client.

[![License](https://img.shields.io/badge/license-GPL--3.0-4c9a7a?style=flat-square)](LICENSE.txt)
[![Client](https://img.shields.io/badge/client-retail%20%2B%20forever-4c9a7a?style=flat-square)](https://worldofwarcraft.blizzard.com/)

---

## What it does

**It shows what you are missing, and gets out of the way.** A missing
self-buff or consumable appears as an icon. Once it is sorted the icon leaves
and the bar waits until something needs attention again.

**One click to use it.** Left-click an icon to cast the buff or use the item.
Right-click to dismiss it until you change zones.

**Consumables come from your bags.** Food, scrolls, flasks and weapon
enhancements are discovered automatically. Hover a category's icon to open a
flyout of your other choices; using one makes it the new primary.

**Party coverage reminders.** When a party member's class could provide a buff
someone is missing, an informational icon appears. Left-click reports it to
chat; it never casts.

**One key for the next missing buff.** Bind the Buff trigger and press it
repeatedly to work down the bar.

## Combat

Combat starts, Buffsmith clocks off. The bar is hidden by a secure state driver
and none of its actions are available until combat ends. This is deliberate:
its clickable icons are protected, and Lua may not show, hide or reconfigure
them in combat.

## Settings

Use `/buffsmith` to open settings. The window has a preview mode that draws a
test bar at the saved position, so you can place and size the bar even when
nothing is missing.

| Command | Effect |
| --- | --- |
| `/buffsmith` | Open settings |
| `/buffsmith preview` | Show or hide the on-screen preview |
| `/buffsmith toggle` | Hide or show the bar |
| `/buffsmith debug` | Selectable diagnostics report |

## Development

Two TOCs ship in one addon folder: `Buffsmith.toc` for Retail (`120100`) and
`Buffsmith_Camelot.toc` for WoW Forever (`16001`).

WoW runs Lua 5.1, so that is what the checks use:

```sh
docker run --rm -v "$PWD:/addon:ro" -w /addon nickblah/lua:5.1-alpine sh -lc \
  'find /addon -name "*.lua" -print0 | xargs -0 -n1 luac -p \
   && lua tests/test_config.lua && lua tests/test_layout.lua'
```

`tools/stage_addon.py` copies a runtime-only folder into a client's `AddOns`
directory for local testing.

## Licence

GPL v3. See [LICENSE.txt](LICENSE.txt). Buffsmith is independently
implemented; it does not copy code or data from other buff addons.
