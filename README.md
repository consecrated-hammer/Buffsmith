# Buffsmith

**Buffs and consumables, without the scavenger hunt.**

_Sometimes the real raid mechanic is getting the Mage to press Arcane Intellect._

[![Discord](https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/z3xKxRygDc) [![Retail](https://img.shields.io/badge/retail-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/buffsmith) [![WoW Forever](https://img.shields.io/badge/wow%20forever-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/buffsmith) [![Release](https://img.shields.io/github/v/release/consecrated-hammer/Buffsmith?style=flat-square&color=4c9a7a&label=release)](https://github.com/consecrated-hammer/Buffsmith/releases) [![License](https://img.shields.io/badge/license-GPL--3.0-4c9a7a?style=flat-square)](https://github.com/consecrated-hammer/Buffsmith/blob/main/LICENSE.txt)

Questions, bugs or ideas? Come say hi on the [Consecrated Hammer Discord](https://discord.gg/z3xKxRygDc). Bug reports go in `#bug-reports`, or you can open a [GitHub issue](https://github.com/consecrated-hammer/Buffsmith/issues).

---

Buffsmith shows the self-buffs, party buffs and consumables you're missing as a small bar of clickable icons. If something needs attention, it appears. Once it's sorted, it gets out of the way.

## What it does

- **Missing self-buffs**, picked up from your spellbook. Buffs shorter than a minute are listed but start switched off, so things like seals don't nag you.
- **Consumables from your bags**, like food, flasks, scrolls and weapon enhancements. Hover a consumable to see your other choices, and whichever you use becomes the new default.
- **Party buffs.** Buffs you can give to your target, party or pet show up too, and grey out when the game can tell the player is out of range.
- **Party coverage reminders.** When someone's missing a buff another class in the party could give, an icon says so. Clicking it reports it in chat; it never casts anything.
- **Tracking.** Find Herbs, Find Minerals and other tracking spells can sit on the bar until you turn them on. Gathering tracking starts ticked, class and racial tracking start off.
- **One key for the lot.** Bind **Buff trigger** in the game's key bindings and press it to work down the bar one missing buff at a time.
- **Optional thank-you.** Buffsmith can whisper, say, post in party or emote a thanks when someone buffs you. It's off by default.

## Getting started

Install, then type `/buffsmith` (or `/bs`) for settings. **Preview on screen**, at the bottom of the settings list, draws a test bar where yours will sit, so you can place and size it without deliberately removing half your buffs first.

On the bar:

- **Left-click** an icon to cast the buff or use the item.
- **Right-click** to dismiss it until you change zones.
- **Shift-right-click** to ignore it for good. Ignored buffs and consumables are listed on the **Ignored** page, where you can bring them back.

## Commands

| Command | What it does |
| --- | --- |
| `/buffsmith` or `/bs` | Open settings |
| `/buffsmith toggle` | Show or hide the bar |
| `/buffsmith lock` / `unlock` | Hide or show the drag handle |
| `/buffsmith reset position` | Move the bar back to the centre |
| `/buffsmith preview` | Show or hide the on-screen preview |
| `/buffsmith scan` | Rescan your bags for consumables |

Every Consecrated Hammer addon also has `help`, `version`, `about`, `debug`, `startup`, `minimap`, `reset settings` and `quiz`.

## Combat

By default the bar only shows out of combat. Visibility can be set to **Always**, **Never**, or any mix of **In combat**, **Out of combat**, **Solo**, **In a party** and **In a raid group**.

If you do keep it up in combat, it stays as it was when combat started. Buffsmith deals with protected buttons, and WoW gets rather particular about addons rearranging those mid-fight, so nothing is rescanned or rearranged until combat ends.

## Limits

- **Tracking on WoW Forever is one at a time.** The game only allows one tracking type there, so you pick which one Buffsmith offers. Selecting a different one puts it on the bar so a click swaps over.
- **Thank-you needs a known caster.** If the game doesn't say who buffed you, Buffsmith won't guess. On WoW Forever that happens more often, and there's an optional untargeted emote for it.
- **A stronger buff wins.** If the game rejects a buff because you already have a stronger one, Buffsmith hides it until you change zones instead of asking again.

## Licence

GPL v3, see [LICENSE.txt](https://github.com/consecrated-hammer/Buffsmith/blob/main/LICENSE.txt). Buffsmith is its own code; it doesn't copy code or data from other buff addons.

## Development

Two TOCs ship in one addon folder: `Buffsmith.toc` for Retail (`120100`) and
`Buffsmith_Camelot.toc` for WoW Forever (`16001`).

WoW runs Lua 5.1, so that is what the checks use:

```sh
docker run --rm -v "$PWD:/addon:ro" -w /addon nickblah/lua:5.1-alpine sh -lc \
  'find /addon -name "*.lua" -print0 | xargs -0 -n1 luac -p \
   && for t in tests/test_*.lua; do lua $t || exit 1; done'
```

`tools/stage_addon.py` copies a runtime-only folder into a client's `AddOns`
directory for local testing.
