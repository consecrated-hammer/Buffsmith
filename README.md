# Buffsmith

**Buffs and consumables, without the scavenger hunt.**

_Sometimes the real raid mechanic is getting the Mage to press Arcane Intellect._

[![Discord](https://img.shields.io/badge/discord-join-5865F2?style=flat-square&logo=discord&logoColor=white)](https://discord.gg/z3xKxRygDc) [![Retail](https://img.shields.io/badge/retail-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/buffsmith) [![WoW Forever](https://img.shields.io/badge/wow%20forever-supported-4c9a7a?style=flat-square)](https://www.curseforge.com/wow/addons/buffsmith) [![Release](https://img.shields.io/github/v/release/consecrated-hammer/Buffsmith?style=flat-square&color=4c9a7a&label=release)](https://github.com/consecrated-hammer/Buffsmith/releases) [![License](https://img.shields.io/badge/license-GPL--3.0-4c9a7a?style=flat-square)](https://github.com/consecrated-hammer/Buffsmith/blob/main/LICENSE.txt)

Questions, bugs or ideas? Come say hi on the [Consecrated Hammer Discord](https://discord.gg/z3xKxRygDc). Bug reports go in `#bug-reports`, or you can open a [GitHub issue](https://github.com/consecrated-hammer/Buffsmith/issues).

---

Buffsmith shows the self-buffs, party buffs and consumables you're missing as a small bar of clickable icons. If something needs attention, it appears. Once it's sorted, it gets out of the way.

## What it does

- **Missing self-buffs**, picked up from your spellbook. Buffs shorter than a minute are listed but start switched off, so things like seals don't nag you.
- **Rogue poisons** on Retail, with separate lethal and non-lethal reminders.
  Each spec remembers the last poison you successfully applied in each group,
  including casts from your action bars. Only learned poisons are offered.
  Any active poison in a group satisfies that reminder until it nears expiry.
  On WoW Forever, poison items appear under Weapon enhancements and coat a
  bare main-hand weapon first, then a bare off-hand weapon. Buffsmith remembers
  flyout choices for each hand and leaves existing coatings in place. These
  item actions pause in combat.
- **Consumables from your bags**, like food, flasks, elixirs, scrolls and weapon enhancements. Drinks and other items that give a timed buff, such as the Keg of Thunderbrew, go under **Other buffs**. Hover a consumable to see your other choices, and whichever you use becomes the new default.
  On Forever, Camp Chair appears when Camp Benefits is missing. Camp Tent
  appears when its Boosted Rest lockout is missing. Both use Other buffs and
  respect item cooldowns and your ignored items.
- **Party buffs.** Buffs you can give to your target, party or pet show up too, and grey out when the game can tell the player is out of range.
  Hover an icon to see who it will be cast on. Under **Tooltips**, enable
  **Show spell descriptions** to include Blizzard's explanation of the spell.
  Descriptions start off; **Show bar tooltips** controls the whole tooltip.
- **Party coverage reminders.** When someone's missing a buff another class in the party could give, an icon says so. Clicking it reports it in chat; it never casts anything.
  On Forever, a party member is only listed after Buffsmith sees a buff
  attributed to them during the current group session. Untrained spells aren't
  assumed from class or level. Blood Pact also requires the pet that supplied it.
  If the client omits the caster, that buff cannot establish availability.
- **Read Leyline.** On Forever, characters who know the racial see it when health
  or mana is below 50% and it is off cooldown. Change its threshold on the Buffs
  page. The reminder uses the normal bar and Buff trigger, with the same combat,
  death, flight-path, rested-area and meal rules.
- **Tracking.** Find Herbs, Find Minerals and other tracking spells can sit on the bar until you turn them on. Gathering tracking starts ticked, class and racial tracking start off.
- **One key for the lot.** Bind **Buff trigger** in the game's key bindings and press it to work down the bar one missing buff at a time.
- **Optional thank-you.** Buffsmith can whisper, say, post in party or emote a thanks when someone buffs you. It's off by default.
  **Skip party and raid members** in Thank You settings only skips identified
  group casters. It starts off. Unknown-caster emotes keep following their own
  setting, even when group thanks are skipped. Loading screens and zone
  changes pause thanks while the aura list settles for one second. Existing
  buffs and full aura snapshots become the baseline; new buffs afterward can
  trigger thanks normally. If the client omits the caster's unit token,
  Buffsmith also tries the aura's caster GUID and resolves a matching unit or
  player name. This runs automatically when Thank You is enabled; restricted
  or missing identity data can still prevent a directed reply. Name-based
  emotes depend on the client resolving the player and can become general
  emotes if that player is no longer available.

When you bind the Buff trigger through `/buffsmith` → **Key Bindings**, a
mouse-wheel key that already controls camera zoom reveals **Also zoom in** or
**Also zoom out**. Tick it to keep that camera action as well as using the buff
trigger. The option starts off and appears only for a detected camera binding;
Buffsmith checks the chosen key's camera command instead of assuming wheel direction.
Clearing or replacing the wheel binding restores the captured camera command.
Camera choices are saved separately for account bindings and each character's
character-specific bindings.
Existing Buffsmith wheel bindings whose original action was already replaced
need to be bound to camera zoom first, then selected again in Buffsmith.

Buff trigger keys, the shared wheel and left-clicked icons recheck readiness
before casting. Readable cooldowns and normal casts outside WoW's current
`SpellQueueWindow` suppress the press without advancing the trigger; channels
and eating/drinking also pause casts. One attempted spell is held through the
short native queue window so repeated input doesn't replace it. This doesn't
create an addon cast queue: timers never cast, and a later key press is still
needed. Buffsmith only reads the queue setting. Unknown or restricted readiness
data preserves native input, so this reduces avoidable errors rather than
silencing every possible game error.

Icons show native cooldown sweeps when timing is readable. If the last used
action leaves the reminder list while cooling down, its icon stays as a
non-casting cooldown display until the cooldown ends. This also applies to
Read Leyline; it does not put a cooling ability into the Buff trigger. Cooldowns
use the icon sweep without a separate cooldown text row. A status line shows
casting or channeling. Native queue timing stays internal and has no text row.
Eating/drinking shows a pause
indicator, with a countdown only when every detected meal aura has a readable
expiry. The meal status can remain visible when there are no missing buffs.
Unrelated casts don't reveal an otherwise empty bar. Normal visibility, death,
flight-path and rested-area exclusions apply. Recovery abilities such as Read
Leyline are only actionable when ready; ready consumable alternatives keep their
existing selection rules. `/buffsmith debug` reports the latest input decision
and blocked-press count.

The Consumables page lists supported items you own, including those the client
currently marks unavailable. This can happen during travel or other use
restrictions. These items remain configurable but stay out of cast choices until
a later inventory refresh finds them usable. Diagnostics distinguish discovered
bag contents from currently usable choices. Forever camp benefits and lockouts
are kept separate from consumed-item buffs; an old camp mapping cannot satisfy
a food reminder. New food-effect learning requires a Well Fed signal, so an
unrelated class buff arriving during eating cannot replace the food timer.

The drag handle stays at a fixed top-left corner while icons, cooldowns and
status rows come and go. The grid grows right and down from there. Dragging the
live bar or preview saves the same fixed corner. The changing-size grid no
longer clamps itself back onto the screen, since that would move the handle;
use `reset position` if you need to bring it back into view.

**Skip PvP-flagged players while I'm unflagged** is on by default under
**Buffs → Targets**. It filters explicit target, party and pet recipients while
you're unflagged, checks flags again on input, and skips recipients whose flags
can't be read. Self buffs still work. Turning the option off restores previous
recipient selection; already flagged players can buff normally. Guarded external
buff buttons disarm securely on combat entry and rearm after combat. This doesn't
toggle your PvP setting or control a spell's area effects, other addons or manual
casts outside Buffsmith.

Party-coverage tooltips rotate through twelve playful provider hints, such as
“Skyward and Mira might have a little magic to spare.” Every line keeps all
eligible names and uncertainty about current availability. A clicked report
uses that hint and retains its existing three-second rate limit. Reports still
require a click; very long reports are shortened to fit the chat byte limit.

Reminders and buff-trigger actions pause on flight paths and refresh when you
land. Shared wheel zoom still works while there are no usable buff actions.

Thank You cancels pending replies when combat starts or the feature is turned
off. After combat or an unreadable aura snapshot, it quietly refreshes its
baseline. Unknown-caster emotes on Forever use the configured delay and batch
together, with the first queued reply starting the delay. Discovering the caster
later does not send another thanks. Attribution
expires after five seconds. `/buffsmith debug` includes up to twelve recent
decisions saved locally, without caster names, so they remain available after
logout. An accepted emote API call still needs an in-game delivery check.

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

- Reminders and consumable choices stay hidden while you're dead or a ghost.
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
