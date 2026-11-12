# GCD icon flash: current evidence and next capture

The live Mark of the Wild → Thorns flash remains unconfirmed at source level.
No production rendering or eligibility code was changed for this report.

The current code hides unused frames, replaces textures when frames are reused,
clears the secondary resource texture for ordinary buffs, replaces the tracked
identity on a successful second cast, and rejects later unrelated shared GCDs.
New deterministic tests exercise those render transitions on both client TOCs,
including failed/queued casts and manual action-bar casts. Existing tests cover
long remaining aura duration, real spell/item cooldowns, delayed success and
cooldown metadata, rank identity and expiry. Passing the harness cannot establish
native frame rendering or reproduce the live client's event timing.

## Capture while the flash is visible

After reloading the staged build, check `/buffsmith version`. Record a short
video of Mark → Thorns and say whether Thorns was cast using a bar icon, the
Buff trigger or an ordinary action-bar key. Capture `/buffsmith debug` too.

Prepare this macro before reproducing; press it while the wrong icon is visible:

```text
/run for k,f in pairs(Buffsmith.Palette.buttons) do if f:IsShown() then local e=f.buffsmithEntry; print(k,e and e.name,e and e.cooldownOnly,f.icon:GetTexture(),f.secretIcon:IsShown()) end end
```

A second Mark entry means the logical reminder/retained-entry path is involved.
A Thorns entry with Mark artwork means texture/native rendering state is involved.
The final boolean reports whether the secondary recovery texture is shown.
The macro only reads existing frame state, without changing secure attributes.

If possible, capture cooldown identity during the same flash with a second macro:

```text
/run local r=Buffsmith.Readiness; local e=r.lastEntry; local c=r:LastCooldown(); print(e and e.name,r.lastEntryAt,c and c.start,c and c.duration,Buffsmith.Palette.cooldownDisplayKey)
```

Next source investigation follows that evidence: logical duplicates need an
event/selection trace; wrong artwork without a duplicate needs native frame and
cooldown-render inspection. Do not change buff priorities, aura rules or add an
arbitrary hiding timer to mask an unproven cause. Restricted Retail values can
limit diagnostic reads; run the first reproduction on Forever out of combat.
