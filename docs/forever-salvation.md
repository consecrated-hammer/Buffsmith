# Forever Salvation

Salvation is an independent optional self-maintenance buff on Forever build
70425 or later. It starts unticked on Buffs. It is outside `paladin-blessing`,
does not create target, party, pet or coverage actions, and does not offer
Mass Salvation or Revoke casts. Turning it on means maintaining it on yourself;
removal with Revoke creates a reminder again. Shift-right-click ignores it
persistently, and Ignored can restore it.

## Data and saved preferences

- Individual Salvation: `1038`.
- Mass Salvation: `25895`, accepted as an active self aura for the same effect.
- Preference key: `excludedBuffs["forever-salvation"]`. The old numeric
  blessing keys are retained without migration or reuse.

The [70425 client-data diff](https://needbeforegreed.com/forever/builds/70425)
reports the two renamed IDs compared with 70374. The
[Mass Salvation client record](https://foreverdb.net/spell/25895) identifies
25895 in 70425. Blizzard's
[October 15 notes](https://us.forums.blizzard.com/en/wow/t/2360696) confirm
coexistence with ordinary blessings and Revoke's intentional removal.
Checked 2026-10-16. Spell names and icons come from the player's client.

## Verification boundary

Host tests check coexistence, either Salvation aura satisfying the reminder,
Revoke-like removal, self-only scope, default-off behaviour, separate saved
preferences, Ignore/Restore and old-build/Retail exclusions. They do not prove
the applied aura IDs in Forever.

Before release, check the live cast and aura IDs for Salvation and Mass
Salvation, apply either alongside Might/Kings/Wisdom, remove Salvation alone
with Revoke and confirm the blessing remains satisfied. Verify an ordinary
player `UNIT_AURA` refreshes the bar without `SPELLS_CHANGED`, and that no
reminder returns after ignoring Salvation. Buffsmith's existing combat
deferral applies; raid-member coverage is outside this change.
