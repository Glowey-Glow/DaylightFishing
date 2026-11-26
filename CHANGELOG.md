# Glowey's Fishing

## 1.10.0
- With another of Glowey's plugins on, Fishing's pages sit under one "Glowey's" entry on Daylight UI's options rail, each plugin a page there.

## 1.9.4
- The welcome no longer keeps asking every 5 seconds for the whole session while Daylight UI is busy: it gives up after ten minutes and asks at the next login.

## 1.9.3
- Settings dropdowns no longer catch the click outside them: a click on a data text, an addon drawer or anything else closes the menu and reaches what you clicked the first time.
- After Escape closes a tour card, the card no longer keeps your keys to itself (it could stop movement keys in a later fight).
- BugSack reports now end with this addon's name and version on its own errors, so a report says which version it came from.

## 1.9.2
- No more checking every frame while you fish. The quiet screen's fade now runs only while it fades out or back in (or while you fall), and wakes on moving, the still delay, AFK, chat, a jump or a window opening. The fishing menu runs every frame only while your line is out (the cast bar), once a second while bait is on, and not at all otherwise.
- The combat notice no longer keeps running after it has faded, and the first-time key question stops asking after ten minutes of you being busy (it asks at the next login instead).

## 1.9.1
- Lighter while you fish: each catch no longer redraws the menu, the catch list and the popup's frame when nothing they show changed, the quiet screen's watcher stops when Fade the UI While Fishing and Hide Daylight UI's Fishing Water are both off and checks what to keep visible once a second (at once when a bag, popup or the loot window opens), and the line's events are only listened to while Fishing Mode is on.
- Fishing Mode only changes (and later puts back) the sound, Soft Interact and Auto Loot settings that aren't already as it wants them.

## 1.9.0
- Follows Daylight UI's language, look and scale when it's installed: the menu, its lists, the key box and the tooltips take its colors and repaint when you change its look, and the menu's size goes with Daylight UI's own scale. Without it, its own Language choice and the look picked in /glowey.
- Without Daylight UI: dropdown menus fit their words. Each menu is as wide as its longest choice, its rows are as tall as the font, and in Blizzard Style it keeps the game's own margins (8 at the sides and top, 15 at the foot), so the last choice no longer runs past the bottom edge. Menus are solid, so the setting underneath no longer shows through.
- Without Daylight UI: a dropdown on a settings page is wide enough for its longest choice.
- Without Daylight UI: sliders on the settings pages can be dragged and clicked again. They were made without taking the mouse, so none of them moved.
- Without Daylight UI: a slider can be dragged all the way. The page was drawn again on every step, which let go of the slider under the mouse; it now waits until the slider is let go.
- Blizzard Style: bars are the profession window's own (its skill bar's border and fill, 14 high), such as the Chance of Skill Up bar.
- What's New lists this release.
- Blizzard Style: scroll bars are the game's own (its minimal scroll bar, with arrows at both ends): drag the thumb, click the track or the arrows, as in the game's windows.
- Works without Daylight UI. Daylight UI is no longer required: with it installed nothing changes, and without it the plugin runs on its own. Its settings are then in a Glowey's Plugins window (/glowey, or the game's Options > AddOns), shared by every Glowey plugin you have, with a General page for the accent color, window opacity and moving frames. Frames move with /glowey unlock (drag; right-click puts one back), and /glowey <command> stands in for /dui <command>.
- Your settings are kept either way: they are now also saved in the plugin's own saved variable, so taking Daylight UI out keeps them, and settings made without it are taken into Daylight UI when it comes back.
- Without Daylight UI: a Look choice on the General page of /glowey for every Glowey window: Glowey's own, Blizzard Style (Blizzard's own window frames from this client: the metal frame with its title bar and red close button, dialog borders, tooltip boxes, red buttons, edit boxes, check boxes, sliders, tabs and gold text), or Polestar's when Polestar is loaded. With Polestar, Polestar itself paints the windows in the look you picked in its settings, and they change when you change it there. And a minimap button: click it for the settings, right-click to move frames, drag it round the map. It also appears in the game's addon menu, and Minimap Icon on the General page hides it.
- Blizzard Style fits its borders to each window: a small box (Essentials' combat timer, the tabs) gets the tooltip's thin border instead of the dialog's, which overlapped itself there, and the border sits round the outside of a window so it never covers what's inside.
- Without Daylight UI: Fishing Mode, the menu, the key, the sound and the quiet screen all work as before, and the quiet screen fades the game's own UI. Turn it on with /fish, the macro, or any data broker display. Hide Daylight UI's Fishing Water and Daylight UI's opacity switches are left out without it.
- Controller navigation of the plugin's windows comes from Daylight UI's controller support, so it needs Daylight UI.

## 1.8.3
- A command of its own, with no "/dui" in front: /fish (or /fishing) turns Fishing Mode on or off. /dui fish still works.
- Fixed: the game stopped giving realm names on 2026-11-20, and Glowey's Fishing kept each character's Fishing Mode state under its name and realm. A character that logged out in Fishing Mode before that day now gets its weapons back and its settings restored as it should at its next login. The state is now kept by character, so a change like this can't unhook it again.
- Checked against Daylight UI 2.1.2. Nothing else to change.

## 1.8.2
- Fixed with Daylight UI 1.9.5: after Daylight UI's AFK screen closed, the UI could stay faded or invisible if Fishing Mode had faded it. Fishing's fade is now kept apart from the AFK screen's and the NPC scene's, and let go when the AFK screen ends.

## 1.8.1
- Daylight Fishing is now Glowey's Fishing (DaylightUI Plugin), so it's clear it's a plugin and not part of Daylight UI. Inside Daylight UI the section is Glowey's Fishing. Your settings and your Fishing Mode data text are kept.

## 1.8.0
- Controller support: the catch list, the trainer box, the tours and the welcome work with a controller (D-pad, A, B). Set Fishing Key takes a controller button as the key (Start cancels), and with the controller interface on, the D-pad, A and B work its Space and Clear buttons.
- New, for controller players: Catch List Always On and Trainer Box Always On (For Controller Only, on the options page). While you fish they stay open beside the menu without taking the cursor, so casting and your buttons keep working; the game's UI focus button goes into them and B hands control back.
- With the controller interface on, a catch list or trainer box left open closes when Fishing Mode ends, instead of taking the cursor later with nothing on screen.
- Labels and buttons in Title Case, and "Daylight UI" written with a space.

## 1.7.1
- Shift-clicking an item in the catch list puts its link in chat through the game's current call. The old one only exists while the game's deprecated-API addon is loaded, and without it the click raised a Lua error.

## 1.7.0
- New: Weapon Swap on the fishing menu, at its right: the weapon or weapons that go back on when Fishing Mode ends. Hover one for the item. It shows while "Put my weapons back on" is on.
- New: "Stay faded while moving" (on to start). Once the UI has faded, walking about keeps it faded; a fight, the chat box (with Keep the chat off) or Fishing Mode ending still bring it back. Off, the UI comes back as you move, as before.
- While the UI is faded, Polestar's target button faces no longer stay on the screen (3D models ignore the fade), and Daylight UI's 3D portraits fade with the rest (the fade now goes through Daylight UI's own).
- While the UI is faded, passing the mouse over a window out of sight (Polestar's guide) no longer shows its tooltip. Tooltips of the bobber, mobs and your catch still show.

## 1.6.14
- New: on the first start, Daylight Fishing asks for your fishing key before the welcome (the welcome and the tour wait until you've picked one). With Forever Fishing loaded, the box says which key Forever Fishing uses so you can pick a different one. Escape keeps Space. Players who already had Daylight Fishing aren't asked; Set Fishing Key in the options changes it any time.

## 1.6.13
- With Mastercraft installed, its "Hide the game's interface" stays on Never while "Fade the UI while fishing" is on. Both set the UI's opacity, so with both on the UI could stay faded after fishing. Turning our fade off, or Revert to Mastercraft, gives its setting back as it was.

## 1.6.12
- Everyone, including players who had Daylight Fishing before, sees the welcome and the tour once with this version. A Mastercraft fight setting you already picked stays as it is.
- New: a welcome on first launch that lists what Daylight Fishing takes over while Fishing Mode is on (your weapons, sound, one key, fights, and Mastercraft's fight setting when it's installed). Start Tour begins a short tour.
- New: a tour of Fishing Mode, the first time it turns on: the menu, baits, the fishing key (try a cast and it moves on), skill and catch, fights and settings. Back, Next and Skip tour; Escape skips; a fight ends it.
- New: after an update, a short note with what changed.
- New Help card in the options: Retake Tour, What's new, and (with Mastercraft installed) Revert to Mastercraft, which gives Mastercraft its "After the fight: your fishing gear back on" setting back.
- New: tells you when a newer version is out. Your copy and those of players in your guild and group trade version numbers in the background, and one chat line says when there is a newer one to get through CurseForge or WowUp (once a session). Turn it off with "Tell me when a newer version is out" on the plugin's first options page; then nothing is sent either.

## 1.6.11
- Fix: when a fight ends Fishing Mode, your one-hand weapon and your shield (or other off hand) both go back on at once. Before, only the main hand went on and the off hand waited for the fight to end. They now go on the way a two-line /equip macro does it: main hand, then off hand, in the same moment, just before the fight locks gear changes. Turning Fishing Mode off yourself works the same way.

## 1.6.10
- Translations tidied: lines for text the plugin no longer shows are taken out of all six languages.

## 1.6.9
- Translations: today's new text (Set Fishing Key, the fight message, the Mastercraft question and more) in German, French, Spanish, Russian, Korean and Simplified Chinese.

## 1.6.8
- Its own icon: in the game's AddOns list and other menus (instead of the blank "?"), and on its page in Daylight UI's options. The Fishing Mode data text shows it too.

## 1.6.7
- The fishing key can be any key you like: Set Fishing Key opens a small box, press the key you want (a mouse's middle or side button works too), or pick Space or Clear (no key: click the cast button). It replaces the short list of keys. Space is still the key to start, and a key you picked before is kept.
- A fight now always ends Fishing Mode, and it stays off after the fight. "Combat Detected, Exiting Fishing Mode" shows where the fishing menu was, then fades away.
- With Mastercraft loaded: its "After the fight: your fishing gear back on" put your pole back on after every fight. Daylight Fishing now handles fights by default and turns that one Mastercraft setting off (asked once; change it any time under Fishing > Fights while fishing, which gives Mastercraft its setting back).
- Fix: a fishing pole that goes back on during or right after the fight (another addon putting your fishing gear back on) no longer turns Fishing Mode back on.
- Fix: your weapons are never lost. The ones you held when Fishing Mode started are kept until they are back in your hands, so they go back on when Fishing Mode ends however it ends: from the button, after a fight (even with the pole back in hand since), after a /reload, or when you take the pole off and leave your hands empty. A pole you put on by hand brings back the weapons you held before it.

## 1.6.6
- Pulled into a fight while fishing: no more "blocked action" error. Your main hand still goes on at once; the off hand, which the game won't let an addon equip during a fight, goes on as the fight ends.

## 1.6.5
- On German, French, Spanish, Russian, Korean and Chinese clients, words the game already translates (like Fishing, Fishing Skill and Off) use the game's own translation instead of our draft.

## 1.6.4
- Fixes for non-English game clients: Krix in Powderfuse Port is found again (Riverglades is now looked up by its map number, not its English name), and the trainer box shows the places, the Expert Fishing book, the Artisan quest, Alliance and Horde, and the named fishing keys (Space, mouse buttons, Backspace) in the game's language. English clients see no change.
- Window opacity: follows Daylight UI's by default, or set your own on the options page.
- Daylight Fishing speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome).

## 1.6.3
- New: getting into a fight while in Fishing Mode puts your saved weapons back on at once and ends Fishing Mode (with "Put my weapons back on" on, as it is to start).
- Fix: taking the fishing pole off in a fight no longer causes a blocked-action error (SetCVar). Your sound and other settings go back once the fight ends.
- Fix: "Keep the minimap" off now fades the minimap too. The game draws its dots at full strength whatever the UI's opacity, so the minimap now goes fully away once the UI has faded out, the way Daylight UI's AFK screen hides it.
- Fix: "Keep the chat" on now keeps Daylight UI's chat on screen. It kept only the game's own chat windows, which Daylight UI hides, so the chat you see faded anyway.

## 1.6.2
- All text in American English (gray, color and the like), in the game and in the docs.

## 1.6.1
- Lighter while fishing: settings are read once and kept until they change (the quiet screen asked for several every frame), and the frames it keeps visible are no longer looked up by building their names four times a second.

## 1.6.0
- New: Fishing Skill on top of the fishing menu, with a bar to your rank's cap and a mark where the next rank can be learned (bright once you can). "Maximum Fishing Trained" once you have Artisan. Hover it for what the next rank takes; click it for where to go: the closest fishing trainers for Apprentice and Journeyman (your faction's and neutral, nearest first with how far), Old Man Heming in Booty Bay for the Expert book (1 gold, Fishing 125, level 20), or Nat Pagle in Dustwallow Marsh for the Artisan quest (Fishing 225, level 35). Each is a waypoint on click (TomTom when it's installed). Trainer and rank data from Wowhead's WoW: Forever pages; no other addon needed.
- New: "Make a Fishing Mode macro" in the settings. It makes a "Fishing Mode" macro with the Fishing icon (or brings yours up to date) and puts it on your cursor to drop on an action bar.
- New: putting a fishing pole on turns Fishing Mode on (taking it off already turned it off). A switch in the settings, on to start.

## 1.5.0
- Fishing Mode is remembered per character.
- Weapons go back into their own slots when Fishing Mode ends (dual wield and off-hands too).
- A /reload in a fight with Fishing Mode on resumes it when the fight ends.
- Sound settings are never lost if the game refuses a change in a fight; they are restored when it ends.
- The fishing key no longer recasts when held through the hook.
- The quiet screen hands everything back to Daylight UI's AFK screen cleanly.
- "Fish Got Away" shows once per cast, and not when you jump or cast something else.
- Bait buttons update after a fight.

## 1.4.0
- The quiet screen keeps the minimap, chat and your bags, and the loot window no longer brings the UI back on each catch.
- New: a popup at the fishing menu's left after each cast, "Fish Caught!" with what came up, or "Fish Got Away".

## 1.3.1
- Option to hide Daylight UI's fishing water while in Fishing Mode.

## 1.3.0
- New: the quiet screen. The UI fades while you stand and fish, like Daylight UI's soft AFK screen.
- The slash command is now /dui fish (/dui fishing is Daylight UI's water preview).

## 1.2.0
- Click the catch counter for a list of your catch, fish by fish.

## 1.1.1
- The cast and bait buttons show properly. A bar shows the line's time in the water.

## 1.1.0
- Session catch counter on the data text and the fishing menu, with everything you caught on hover.

## 1.0.0
- Fishing Mode from a data text: fishing pole, sound, soft interact and auto loot, one-key cast and hook, and a bait menu under your character.
