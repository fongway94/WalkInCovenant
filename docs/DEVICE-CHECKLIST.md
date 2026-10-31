# Device checklist — what a phone must confirm

This is the list a human with a phone works through. It exists because the
authoring sandbox **cannot** do it: it has no Godot binary, no sound card, no
touch screen and no mobile browser. Everything below is therefore *unverified*
by the automated gates, no matter how green CI is. Say so in any report.

Play against the deployed build (the URL in the repo's Pages settings) in
**landscape** on at least:

- one iPhone, iOS 17+, Safari **and** the installed PWA
- one Android phone, Chrome, plus the installed PWA

For each, walk the whole of both chapters: the valley (1 Samuel 17) and
Bethlehem (1 Samuel 16).

## 1. Orientation and layout (P2)

- [ ] First frame is landscape and the game asks for landscape rather than
      rendering a squashed portrait canvas.
- [ ] Rotate mid-game: the HUD, dialogue box, touch buttons and camera re-lay
      themselves out with no black bars, clipping or one-frame flash.
- [ ] Address bar sliding away on scroll does not leave the picture letterboxed.
- [ ] Nothing sits under the notch / rounded corners in landscape (the HUD uses a
      2.5% edge inset; confirm it is enough).
- [ ] Dialogue text at 4 rows fits on the shortest screen you own, in **both**
      Chinese and English (the language toggle is `EN`/`中`, top right).
- [ ] Text never overflows the panel, in either language, on any quest line,
      verse or journal row.

## 2. Touch (P1)

- [ ] The floating stick appears where the thumb lands, in the lower-left half,
      and the player moves on the first millimetre (no dead tap).
- [ ] The A button (bottom right, biggest target) is reachable with the thumb of
      the hand holding the phone, without regripping.
- [ ] The run button » works, and so does pushing the stick past ~90%.
- [ ] Tapping the book (≡, top left) and the language/sound switches never moves
      the player instead.
- [ ] With a dialogue open: one tap advances exactly one line. No line is
      skipped, no line repeats.
- [ ] The brook (5 stones): tap takes, tap again puts back, the fifth enables
      KEEP THEM and the tap that presses it does not also advance a line.
- [ ] During the fight: throw and dodge both land with a thumb, and the giant's
      attack is readable *before* it lands.
- [ ] During the fight, the game draws **its own A circle** at the bottom right
      (the world's buttons are hidden while a setpiece owns the screen). It
      should be bright during the dodge and the aim, and dim while he winds up.
- [ ] Pressing **early** — while the giant is winding up — must answer on screen
      ("Not yet — he is winding up") rather than doing nothing, and that press
      should still count as the dodge when the spear arrives. This is the
      single most important thing to confirm: it is the fix for "cant click
      anything to fight", and CI can only prove it headless.
- [ ] Tapping anywhere on the screen during the fight also works, not just on
      the circle.
- [ ] In the drill before the fight: the same A circle is drawn, and a press
      made between shots says "Wait for the next jar" rather than nothing.
- [ ] A question with answers (the ending's question is the one that matters):
      the d-pad moves a visible highlight between the answers and the A button
      picks the highlighted one. Tapping an answer still works. Try it with the
      on-screen A specifically — the check behind it drives the button's action,
      not a finger.
- [ ] The journal opens, scrolls if needed, and closes with the close button.

## 3. Audio (P2)

- [ ] Sound starts after the first tap (browsers forbid audio before a gesture —
      this is expected, not a bug).
- [ ] Footsteps change with terrain (dirt / grass / sand / stone).
- [ ] Music ducks under dialogue and comes back without an audible click at
      either end.
- [ ] Walking from the valley to Bethlehem crossfades rather than cutting.
- [ ] The fight cue arrives faded in, not slammed in.
- [ ] 音 / 静 mutes everything, survives a reload, and the choice is remembered.
- [ ] Switching apps silences the game; coming back restores it.

## 4. Performance and browser behaviour (P2)

- [ ] First load completes; the second load comes from the service worker with
      the phone in flight mode.
- [ ] No stutter when a dialogue opens, when the BECOME transition plays, or
      when a region loads (the biggest known risks: the 32x32 map build and the
      first-time font load).
- [ ] Battery/thermal: 10 minutes of walking does not make the phone hot.
- [ ] The game survives backgrounding mid-conversation and mid-walk.

## 5. Progression, on the device (P1)

- [ ] Close the tab mid-chapter, reopen: same region, same act, same objective.
- [ ] Close the tab in Bethlehem, reopen: you are in Bethlehem, not the valley.
- [ ] Every person you have already met says their *later* lines, not their
      first ones.
- [ ] Pick up all three provisions, reload, and finish the errand.
- [ ] After the ending card, the road south to Bethlehem is open, and the road
      back to the valley still works.

## How to report

For every failure, record: device, OS, browser, whether it was the PWA, what you
did, what you expected, and what you saw. A screenshot or a screen recording is
worth more than a paragraph. Anything found goes into `docs/BUGS.md` with the
next free ID.
