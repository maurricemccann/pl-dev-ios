# Handover from the lead to lane C (PL Paint native)

**The founder's word, 11-13:** "You have our past transcripts on how we made PL Paint, so you could send it to one of the other sessions to one shot." Port the real app, every tool, sheet, gesture and setting, behaving as the laptop does. Don't port a reading of the spec.

## Read first, in this order
1. `C:\Users\maurr\PSYCHED LUXURIES\Plans\SPEC — PL PAINT (S332).md`: the app, built S332.
2. `...\Plans\SPEC — PL PAINT FOR IPHONE AND SYNC (S332).md`: the phone build and the sync door.
3. `...\Plans\SPEC — PL PAINT FEATURES FROM HIS HAND STUDY (S332).md`: the features that came from studying his hand.
4. `...\Plans\SPEC — PL PAINT SELECT ANY STROKE (S336).md`
5. `...\Plans\SPEC — PL PAINT SEAM MODE (S348).md`
6. `...\Plans\SPEC — PL PAINT SEND TO CURATE AND ARCHIVE, BAND GENERATOR (S332).md`
7. `...\Plans\RESEARCH — PAINT HANDBOOK (S332).md`, then the handbook itself, `C:\dev\pl-paint\src\handbook\`. It says what every tool does, the way he was taught it.
8. `git -C C:\dev\pl-paint log --stat --reverse`: the order things were built, and the commit messages that say why.
9. The source, which is the authority: `C:\dev\pl-paint\src\` (app.js, brush.js, blend.js, adjust.js, psd.js, abr.js, svg.js, lift.js, study.js, sync.js, settings.js, toolkit.js), and the toolkit `C:\dev\pl-toolkit` (brush packs, canvases, QuickMenu, gestures).

## The build-session transcripts
Find them with `python "C:\Users\maurr\PSYCHED LUXURIES\.claude\scripts\pl-ask-session.py" "PL Paint"`. It prints sessions newest first, each with its transcript file name. The files live in `C:\Users\maurr\.claude\projects\C--Users-maurr-PSYCHED-LUXURIES\`. Read the S332 to S348 sessions that built or changed PL Paint, especially the founder's own words: what he asked for, what he corrected, and what he crowned. Use `pl-session-asks` to pull only his messages from a transcript. These transcripts are large, so read them in parts.

## Rules
Lane rules as in `LANES.md`.
