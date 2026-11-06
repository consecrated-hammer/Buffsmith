# Changelog

All notable changes to Buffsmith are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Buffsmith uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.5.2] - 2026-11-06

### Fixed

- Unknown-caster Thank You emotes explicitly have no target, so they cannot
  thank a selected mob or player. Your selected target stays unchanged.

## [1.5.1] - 2026-11-06

### Fixed

- Thank You can recover a buff giver from the aura's caster GUID when the
  client supplies no usable unit token, including during delayed attribution
  retries. Use a matching unit or a readable player name without changing target.
- Keep group filtering tied to the recovered GUID, even when the caster's name
  is unavailable. Self and NPC casters never trigger the unknown-caster emote.
- Recovered directed emotes can use the captured player name if their unit
  disappears before sending. Missing or restricted identity data still follows
  the existing optional unknown-caster fallback and never invents a recipient.

## [1.5.0] - 2026-11-06

### Added

- Optional skip for Thank You replies to identified party or raid casters,
  checked when queuing and sending. Unknown-caster emotes keep their existing
  behaviour. The new option starts off.

### Changed

- Add spacing above and below optional spell descriptions in bar tooltips.

### Fixed

- Changing zones or entering a loading screen no longer treats returning buffs
  as newly received buffs for Thank You. Rebuild the aura baseline while the
  zone settles, cancel old queued replies and attribution retries, and treat
  full aura updates as a baseline.

## [1.4.0] - 2026-11-05

### Added

- Buff tooltips name the intended recipient. The new Tooltips page can turn
  bar tooltips off or add Blizzard's spell descriptions, using the offered
  spell rank where known. Spell descriptions start off, matching Salve.

## [1.3.4] - 2026-11-05

### Fixed

- Hide the bar, missing-buff reminders and consumable choices while dead or
  a ghost, and refresh them after resurrection.

## [1.3.3] - 2026-11-05

### Fixed

- Forever Camp Chair reminders now hide while Camp Benefits is active and
  return when it is missing. Camp Tent reminders separately respect the
  Boosted Rest debuff. Camp placement no longer learns unrelated buff timers.

## [1.3.2] - 2026-11-05

### Fixed

- Forever party reminders no longer assume every member of a class knows its
  buffs. Providers must first be observed supplying the buff during the current
  group session. Blood Pact also requires the pet that supplied it. If the
  client omits caster attribution, Buffsmith holds back the reminder.

## [1.3.1] - 2026-11-04

### Removed

- Obsolete Forever Salvation reminders following Blizzard's removal of
  Salvation, Mass Salvation and Revoke. Existing saved preferences are retained
  but no longer create reminders or settings entries.

## [1.3.0] - 2026-10-28

### Added

- Optional Salvation reminders for yourself on WoW Forever build 70425 or
  later. They start off, stay independent of Might/Kings/Wisdom, and recognise
  Salvation or Mass Salvation on you. Turning them on will remind again after
  Revoke; ignore Salvation to stop maintaining it. Old blessing exclusions
  are retained separately. Mass Salvation casts and raid coverage are deferred.
  Not yet checked in the Forever client.

## [1.2.0] - 2026-10-21

### Added

- Rogue poison reminders on Retail, with separate lethal and non-lethal
  groups. Each spec remembers your last successfully applied poison in each
  group, including casts from your action bars.
- Poison items in Weapon enhancements for WoW Forever. The action coats a
  bare main-hand weapon first, then a bare off-hand weapon, and remembers
  the poison item chosen for each hand. Existing coatings are preserved.
  Poison-item actions pause in combat.

## [1.1.0] - 2026-10-14

### Added

- **Other buffs**, a new consumable category for elixirs, and for drinks or
  other items whose "Use:" line gives a timed buff that isn't Well Fed, such
  as the Keg of Thunderbrew. Each item is tracked by its own effect, so an
  agility elixir still shows while a stamina drink is active. Potions are
  left out because they're for combat.

### Changed

- Support Retail 12.1.5 (interface `120105`).
- While you're eating or drinking, Buffsmith's icons and Buff trigger no
  longer cast anything, so a stray click or key press can't stand you up
  mid-meal. The bar stays visible, and pressing the trigger or clicking an
  icon shows "Buffsmith waits until you finish eating or drinking." on
  screen.

## [1.0.0] - 2026-09-27

### Added

- Tracking. Buffsmith reads your minimap tracking list and offers each
  tracking spell (Find Herbs, Find Minerals, class and racial senses) on the
  Buffs page. On WoW Forever, choose one tracker explicitly; selecting a
  different tracker puts it on the bar so it can replace the active one.
- Thank You gains an opt-in, untargeted emote fallback when WoW Forever cannot
  identify who applied a recognised buff. The settings page explains why
  attribution is sometimes unavailable; recipient-specific messages still
  require a known caster.

### Fixed

- Consumables on cooldown are hidden until they are usable again.
- An active Well Fed aura suppresses food reminders, including food whose
  generic icon differs between clients.
- Consumables restricted to another class no longer appear for this character.
- Ignored buffs are scoped to the current character, while ignored tracking
  entries remain visible and restorable.

## [0.2.0] - 2026-09-26

### Added

- A lore quiz: the quest "!" on the About page, or `/buffsmith quiz`, asks five
  questions suited to your client, class and race. **Share result** posts
  the verdict to yourself, Say or Party in one click; it is unavailable in
  combat and during keys, PvP matches and encounters.
- Forever Paladins get Blessing of Might, Kings and Wisdom as self and
  friendly-target actions. They share one slot: any active blessing satisfies
  it, and unticking one on the Buffs page offers the next.
- Self-buffs lasting under a minute, such as Seal of Righteousness, are listed
  on the Buffs page but start unticked. Buffsmith learns each buff's real
  duration the first time it sees it; your own choice always wins.
- Shift-right-click a bar icon to ignore it. The Ignored page lists everything
  ignored, including items no longer in your bags, with Restore buttons.
- `/bs` opens Buffsmith, alongside `/buffsmith` and `/bsmith`.
- Retail adds Evoker Blessing of the Bronze and Shaman Skyfury and Water Shield.
- New commands: `version`, `about`, `startup`, `minimap`, `reset position`,
  `reset settings`, `lock`, `unlock` and `scan`.

### Changed

- Buffsmith now uses HammerCore, the settings, command and chat foundation shared
  by every Consecrated Hammer addon. The login message reads
  `Buffsmith v0.2.0 loaded - type /buffsmith for settings, /buffsmith help for commands`, chat uses
  a gold name prefix, and `/buffsmith help` lists every command.
- Settings: Buffsmith's pages, then Commands, Troubleshooting and About.
  **Preview on screen** stays at the foot of the rail. "Show startup message"
  and "Show minimap button" are on Visibility; existing choices carry over.
- Right-click the minimap button to show or hide the drag handle.
- The Overview page is gone; its tips live in the bar and minimap tooltips.

### Removed

- `/buffsmith copy` and `/buffsmith report`; use `/buffsmith debug`.

### Fixed

- Offline and phased party members are no longer offered as buff targets.
- Mutually exclusive self-buffs no longer nag while another is active (Fel
  Armor and Demon Skin; Water and Lightning Shield).
- On Forever, a self-buff whose catalogue ID is not recognised is found by its
  spellbook name, using the highest learned rank.
- Clicking the tick in a dropdown menu now chooses it.

## [0.1.4] - 2026-09-26

### Added

- Thank You can perform a built-in emote instead of sending a chat message.
  Its searchable picker starts with Random, Thank, Bow, Cheer, Applaud and
  Salute, followed by the client's available emotes.

### Fixed

- Forever Thank You recognises ranked versions of tracked buffs by their aura
  name when the spell ID differs, and diagnostics now show aura-match and
  missing-caster counts.
- Existing self-buffs and unidentified auras no longer overwrite the latest
  Thank You delivery status on every unrelated aura update.
- Forever emotes use the confirmed caster unit token through the legacy emote
  API; the modern emote call could broadcast an untargeted emote while
  reporting failure. A matching `UNIT_AURA` added entry can supply direct
  caster attribution, and diagnostics probe the legacy aura API when no caster
  is exposed.
- Secret values are no longer returned by Buffsmith's plain-value helper.
- Forever retries direct caster attribution for the same newly received aura
  at 0.2 and 0.7 seconds. It stays quiet when the client never exposes the
  caster or merely reveals one for an aura present before login.
- A different identified player refreshing an existing buff remains eligible
  for thanks even when the client keeps the same aura instance.

## [0.1.3] - 2026-09-25

### Added

- A configurable one-to-five-second Thank You delay, so replies can feel more
  natural.
- One combined Thank You for multiple recognised buffs applied by the same
  player during the delay.

### Fixed

- Thank You replies now use the complete cross-realm recipient name and stay
  quiet when the buff provider cannot be identified.
- Pending Thank You replies cancel when combat begins or the feature is turned
  off.

## [0.1.2] - 2026-09-24

### Fixed

- The rested-area setting now also hides food, scroll, flask and weapon
  reminders, and the bar updates as soon as you enter or leave a rested area.
  The setting is renamed "Pause reminders in rested areas".

## [0.1.1] - 2026-09-21

### Added

- Buffsmith artwork: a clean anvil minimap/settings icon and a hammermark addon
  icon for the AddOns list.
- Configurable flyout direction: Left/Right for vertical bars and Above/Below
  for horizontal bars, with an Automatic choice that follows available space.
- Range-aware target, party and pet buff icons, including live target range
  updates and lightweight party/pet range refreshes.
- Visibility choices matching Salve: Always, Never, and combinable combat and
  group conditions.

### Changed

- A rejected weaker buff or consumable is dismissed for the current zone rather
  than repeatedly offered when a stronger compatible effect is already active.
- Existing scoped out-of-combat visibility settings retain their original
  behaviour until changed by the player.

## [0.1.0] - 2026-09-20

### Added

- Out-of-combat bar of clickable self-buffs, party buffs and bag consumables
  for Retail 12.1 and WoW Forever.
- Hover flyout for each consumable category, showing your other choices beside
  the primary without moving any other icon.
- On-screen preview of the bar, available from the settings rail on every page
  and from `/buffsmith preview`.
- Settings for visibility, appearance, per-buff and per-item reminder times and
  exclusions, a key binding for the next missing buff, optional thank-you
  messages, and a copyable diagnostics report.
