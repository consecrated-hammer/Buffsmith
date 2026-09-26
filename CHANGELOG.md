# Changelog

All notable changes to Buffsmith are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Buffsmith uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Forever Paladins get Blessing of Might, Kings and Wisdom as self and
  friendly-target actions. They share one slot: any active blessing satisfies
  it, and unticking one on the Buffs page offers the next.
- Self-buffs lasting under a minute, such as Seal of Righteousness, are listed
  on the Buffs page but start unticked. Buffsmith learns each buff's real
  duration the first time it is seen on you; ticking or unticking one keeps
  your choice.
- Shift-right-click a bar icon to ignore that item or buff. The new Ignored
  settings page lists everything ignored, including items no longer in your
  bags, with a Restore button for each. Ignored entries leave the Buffs and
  Consumables lists, which link to that page while anything is ignored.
- `/bs` opens Buffsmith, alongside `/buffsmith` and `/bsmith`.
- Retail adds Evoker Blessing of the Bronze and Shaman Skyfury and Water
  Shield.
- Diagnostics report how many spellbook spells were enumerated and the rank
  each self-buff resolved to.

### Fixed

- Offline and phased party members are no longer offered as buff targets.
- Mutually exclusive self-buffs no longer nag while another is active: a
  Warlock with Fel Armor is not asked for Demon Skin, and a Shaman with Water
  Shield is not asked for Lightning Shield.
- On Forever, a self-buff whose catalogue ID is not recognised is found by its
  spellbook name, and the highest learned rank is used for range checks and
  cast matching.

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
