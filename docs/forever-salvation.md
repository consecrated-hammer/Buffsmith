# Forever Salvation removal

Blizzard's [November 2 development notes](https://us.forums.blizzard.com/en/wow/t/2360696/9)
removed Salvation, Mass Salvation, Revoke and Blessing of Light from Forever.

Buffsmith 1.3.1 removes the optional Salvation self-reminder
added in 1.3.0, including its settings text and build gate. Salvation is no
longer offered even if a client API still reports its old spell ID as known.
Might, Kings and Wisdom keep their existing behaviour. Retail is unchanged.

Old `forever-salvation` and numeric Salvation preferences, reminder thresholds
and learned durations remain in SavedVariables but aren't used. No migration
or settings reset is needed. Blessing of Light wasn't in Buffsmith's catalogue.

Lua tests cover stale known-spell results, opted-in and ignored preferences,
and retained blessing actions. They don't establish live Forever behaviour.
