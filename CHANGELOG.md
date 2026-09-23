# Changelog

All notable changes to Buffsmith are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Buffsmith uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
