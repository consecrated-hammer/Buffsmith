# Settings review, 2026-11-13

Reviewed against Buffsmith f4728d4 (1.12.0). The implementation keeps saved
keys, defaults, selection order and eligibility rules. HammerCore is updated to
its existing committed 3c1eeeb implementation; no shared source edits or other
addon deployments are required.

## Hierarchy and control inventory

E = essential setup, S = standard customisation, A = specialised controls.
Every existing control is mapped below; dynamic rows represent every learned
buff, available tracker, supported bag item or ignored entry on the character.

| Previous location / controls | New location | Level |
| --- | --- | --- |
| Appearance: Direction, Icon size | Appearance, Bar | E |
| Appearance: Flyout direction, Flyout choices | Appearance, Bar | S |
| Appearance: Show drag handle, Reset bar position | Appearance, position actions | E |
| Buffs: every detected self-buff toggle | Buffs > Reminders | E |
| Buffs: every buff's reminder percentage, Read Leyline health/mana threshold | Buffs > Reminders, alongside its toggle | A |
| Buffs: Friendly target, Party members, Friendly pets | Buffs > Targets | S |
| Buffs: Skip PvP-flagged players | Buffs > Targets | S |
| Buffs: Party coverage | Buffs > Targets | S |
| Buffs: all tracking choices | Buffs > Tracking | S |
| Consumables: Food, Scrolls, Flasks, Other buffs, Weapon enhancements | Consumables | E |
| Consumables: each category's reminder percentage | Consumables | S |
| Consumables: every owned item toggle and individual reminder percentage | Consumables, under its category | A |
| Visibility: Show food after standing still | Consumables, before categories | S |
| Ignored: each ignored buff/item and Restore | Ignored | A |
| Buffs/Consumables: View ignored links | Same pages | S |
| Key Bindings: Next buff key, active/available bindings, clear/unbind actions | Key Bindings, second in the rail | E |
| Key Bindings: Also zoom in/out | Key Bindings, when a captured wheel binding exists | A |
| Thank You: Thank players for buffs | Thank You | S |
| Thank You: Skip party and raid members, Send thanks as, Delay | Thank You, Delivery (Delay renamed Thank-you delay) | A |
| Thank You: Emote, Emote when caster is unknown | Thank You, only for Emote; unknown caster only on Forever | A |
| Thank You: Message, Preview message | Thank You, only for chat channels | A |
| Tooltips: Show bar tooltips | Tooltips | S |
| Tooltips: Show spell descriptions, Show item effects | Tooltips, when bar tooltips are enabled | A |
| Visibility: Show the bar (Always/Never/composable conditions), Pause reminders in rested areas | Visibility, Bar | E/S |
| Shared: Show minimap button, Minimap right-click | Visibility, Minimap | S |
| Shared: Show startup message, Show what's new after updates, Mark unread What's new, Turn-in sound | Visibility, Updates | S |
| Shared: Settings search, Show support links; header Window scale | Visibility, Settings window; header (unchanged) | S |
| Reference: What's new, Commands, Troubleshooting reports and About/support links | Reference, unchanged | S/A |
| Shared Theme page | Still withheld by HammerCore | A |

Old rail: Visibility, Appearance, Tooltips, Buffs, Consumables, Ignored,
Key Bindings, Thank You. New rail: Appearance, Key Bindings, Buffs,
Consumables, Tooltips, Thank You, Ignored, Visibility. Reference order is unchanged.

## Decisions and coverage

P1: register all custom reminder/threshold and restore rows, index the Buff
trigger, hide ineffective controls and route their searches to the parent.
P2: separate Buffs by player task, reorder the rail, move food timing to
Consumables and add scoped resets. P3: concise labels, consistent layout and
current What's new destinations. These are implemented.

No global Advanced mode, extra top-level Tracking page, welcome wizard or
priority editor. The existing priority/targeting model is unchanged. Tooltips,
Ignored and Appearance are already small, coherent pages; their structure stays.
The three user scenarios follow Appearance/Bindings, then reminder selection;
regular players use Buffs/Consumables; advanced controls remain adjacent to the
feature they customise. The complete lists remain one column for readable names
and aligned thresholds; ordinary controls retain HammerCore's two-column layout.

Threshold sliders hide when their reminder is disabled. Item rows hide when the
category is off, yet remain searchable through that category. Entries no longer
owned/known are removed from search. A disabled Thank You hides all delivery
controls; hidden channel-specific settings focus the channel selector or master.
All controls use the existing search API. Reset Reminders affects currently
learned self-buff exclusions/thresholds; Reset Tracking affects available tracking
preferences. Consumable reset restores category and item thresholds but keeps
preferred and ignored items. Position reset is separate from appearance reset.
No SavedVariables or WTF files are touched.

Tests load both TOCs, reject duplicate registrations, search and focus every
registered control, exercise dynamic bag removal, parent routing, compatibility
and reset isolation. The separate renderer regressions cover the GCD report.
Actual layout at window scales 0.7/1.3 and native secure rendering need client
acceptance. See the wiki handoff for the tested commit and staged versions.
