# DAVID_CHAPTER_PLAN — from "it runs" to "it lands"

This is the design the audit in `docs/PROJECT_AUDIT.md` implies, expressed as
work with an order. It does not replace anything that already works: the six
acts exist, the duel works, the verses are verbatim, and the seam between the
shared machinery and this chapter's story is sound. What follows is what is
missing between a chapter that *functions* and one that a player finishes
without being told to care.

---

## The spine, as it is and as it should be

**Today:**

```
witness (elah) → BECOME → drill → errand → brothers → Saul → armour
→ brook → duel → aftermath → ending → [optional] Bethlehem / anointing
```

**1 Samuel's order, and the plan's:**

```
Act 1  shepherd (elah, the flock)          — needs building
Act 2  the anointing (bethlehem)            — built, wrong place
Act 3  the errand, the brothers, the king   — built
Act 4  the valley of fear (elah, the camp)  — built, under-used
Act 5  the duel                             — built, good
Act 6  after the victory                    — rewritten this pass
```

The witness frame already justifies showing the story out of chronological
order — the prologue says so ("到了那一天，你不会只是看着大卫——你会成为他"). So
the change is not a rewrite of the fiction; it is moving one region visit
earlier so that the anointing stops being an epilogue.

## 1. {P1, next pass} Make 1 Samuel 16 Act 2, not an epilogue

**Change.** The south road opens when the witness crosses the line
(`elah_met_the_line`) instead of when the chapter ends (`elah_ended`); a new
`elah` mission `bethlehem_call` sits between `witness_line` and `shepherd_drill`
and completes on `beth_anointed`; the HUD says so.

Because the runner starts a returning region at `first_unmet(ctx)`, walking back
from Bethlehem with `beth_anointed` set lands the player exactly on
`shepherd_drill`, whose `enter` is `become_david` — the BECOME happens on return,
which is precisely where the story wants it ("three days earlier" after the
anointing, not before it).

**Blast radius, exactly.** `data/regions/elah.json` (exit `requires`, one
mission, one objective string), `Main._update_guidance` (one branch, already
added this pass for the post-chapter arrow), and **~20 assertions in
`tests/smoke.gd`** which currently walk from the witness line straight into the
BECOME. That last item is why this is not in this pass: the suite cannot be run
locally, and a spine reorder verified only by inspection is how a working game
becomes a broken one.

**Acceptance.** The smoke run reaches Bethlehem and returns before
`act_id() == "shepherd"`; `elah_ended` is still the only thing that opens the
ending; a save taken in Bethlehem resumes in Bethlehem.

## 2. {P1} Give Act 1 a life to be taken away from

Right now "the shepherd" is four narration lines on a slope inside a war camp,
then a drill. David is introduced as somebody's youngest son rather than as a
person with a day.

**Build, in this order:**

1. **A flock.** Four to six sheep, non-blocking, wandering within a radius of
   the fold. Not a mechanic — a place that is alive. One new rig (idle + walk,
   2 directions is enough), reusing the 16 px scale and the existing palette.
2. **The lion at the fold** (17:34–36, now quoted in Saul's scene). One beaten
   patch of ground, a torn hurdle, a tuft of wool — and if the player walks to
   it, three lines of David's own memory. Environmental storytelling, optional,
   no marker.
3. **A task with a reason.** "Bring them in before the light goes" — herd three
   strays back to the fold with the stick. This is the one new mechanic worth
   building: it teaches movement, it is the job the calling interrupts, and it
   ends with the *call* arriving, so the player feels the interruption rather
   than reads about it.
4. **Jesse, visible.** He exists in `david_act.speakers` but never stands
   anywhere in the valley. Put him at the fold.

**Do not** turn any of this into a quiz, a checklist, or a line about how God
sees the heart. Act 2 says that; Act 1 only has to be a day worth losing.

## 3. {P2} Act 4: let the fear be a place, not a line

The camp already has the right three people (a boy who was told not to be
afraid, a woman whose husband went up, an old soldier counting days). What is
missing is that the player as **David** walks through the same camp and they do
not recognise him. `Npc.by_act` now makes that possible without new code.

Write, for each of the four, one act's worth of lines where they talk *past* the
boy from Bethlehem: the boy dismisses him, the woman feeds him anyway, the old
soldier is the only one who looks twice. That contrast is 17:28–30 played rather
than narrated.

## 4. {P2} Quiet beats

Between the armour and the brook, and between the victory and Corin, the chapter
goes straight on. Two places want twelve seconds of nothing: the walk down to
the water, and the moment after the giant falls before anyone speaks. Both are
data and camera, not code.

## 5. {P3} Presentation the chapter is missing

- The duel is the centrepiece and has one song. A second, quieter bed for the
  moment after the fall.
- The valley has no weather. One overlay (heat shimmer or dust) would do more
  for "a place in the afternoon" than any new building.
- The camp has tents and jars and no *work*: no mending, no cooking, no queue at
  the water.

## What this plan refuses

- More chapters. The directive is explicit, and this chapter is not finished.
- New systems for their own sake. Every item above either removes a gap between
  what the story says and what the player does, or it does not get built.
- Any change to the canonical outcome, or any invented sentence placed in
  Scripture's mouth. Fictional dialogue stays fictional and stays out of 「」.
