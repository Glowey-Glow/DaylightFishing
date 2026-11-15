# Daylight Fishing

## 1.6.8
- Its own icon: in the game's AddOns list and other menus (instead of the blank "?"), and on its page in DaylightUI's options. The Fishing Mode data text shows it too.

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
- Window opacity: follows DaylightUI's by default, or set your own on the options page.
- Daylight Fishing speaks German, French, Spanish, Russian, Korean and Simplified Chinese (machine drafts, corrections welcome).

## 1.6.3
- New: getting into a fight while in Fishing Mode puts your saved weapons back on at once and ends Fishing Mode (with "Put my weapons back on" on, as it is to start).
- Fix: taking the fishing pole off in a fight no longer causes a blocked-action error (SetCVar). Your sound and other settings go back once the fight ends.
- Fix: "Keep the minimap" off now fades the minimap too. The game draws its dots at full strength whatever the UI's opacity, so the minimap now goes fully away once the UI has faded out, the way DaylightUI's AFK screen hides it.
- Fix: "Keep the chat" on now keeps DaylightUI's chat on screen. It kept only the game's own chat windows, which DaylightUI hides, so the chat you see faded anyway.

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
- The quiet screen hands everything back to DaylightUI's AFK screen cleanly.
- "Fish Got Away" shows once per cast, and not when you jump or cast something else.
- Bait buttons update after a fight.

## 1.4.0
- The quiet screen keeps the minimap, chat and your bags, and the loot window no longer brings the UI back on each catch.
- New: a popup at the fishing menu's left after each cast, "Fish Caught!" with what came up, or "Fish Got Away".

## 1.3.1
- Option to hide DaylightUI's fishing water while in Fishing Mode.

## 1.3.0
- New: the quiet screen. The UI fades while you stand and fish, like DaylightUI's soft AFK screen.
- The slash command is now /dui fish (/dui fishing is DaylightUI's water preview).

## 1.2.0
- Click the catch counter for a list of your catch, fish by fish.

## 1.1.1
- The cast and bait buttons show properly. A bar shows the line's time in the water.

## 1.1.0
- Session catch counter on the data text and the fishing menu, with everything you caught on hover.

## 1.0.0
- Fishing Mode from a data text: fishing pole, sound, soft interact and auto loot, one-key cast and hook, and a bait menu under your character.
