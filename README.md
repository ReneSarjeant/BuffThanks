# Buff Thanks

WoW Forever beta addon. When a friendly player puts a buff on you, it identifies that caster and plays a random emote at them.

Forever does not give addons the combat log, so this listens to `UNIT_AURA` on you and reads `sourceUnit` from the aura that was just applied. Your own buffs, your pet, and debuffs are ignored. The same caster only gets one emote every 20 seconds, so Fortitude plus a Mark does not make you bow twice.

## Install

Copy the `BuffThanks` folder into:

`World of Warcraft/_forever_/Interface/AddOns/BuffThanks`

The folder must contain `BuffThanks.toc` and `BuffThanks.lua`. Enable it on the addon list and `/reload`.

## Use

`/bt` or `/buffthanks` turns it off and on.

Emotes: thank, wave, bow, salute, cheer, applaud, hello.

Most camp buffs land out of combat, which is when the caster unit is readable. If a buff lands in combat and the caster is sealed, the thank is held until you leave combat.
