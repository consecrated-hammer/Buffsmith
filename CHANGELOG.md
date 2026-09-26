# Changelog

All notable changes to Buffsmith are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Buffsmith uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
