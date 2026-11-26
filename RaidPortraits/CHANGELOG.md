# Changelog

## 1.5.1

- New health numbers on the party and raid frames, with six styles (Health bar > Health numbers).
- New clean thin outlines for target and threat on the frames, drawn over the health bar without the corner pieces (on by default, under Highlight).
- New option to centre the party frames in their Edit Mode box (Size & position > Party frames start from).
- New "Show all icons" button in the preview, to see every icon the game can put on a frame.
- New option to hide the game's white target outline on frames.
- Fixed 3D portraits sometimes staying black after a player comes into view.
- Fixed a Lua error when dragging the party frames in Edit Mode with your own frame hidden.

## 1.5.0

- Fixed party frames sometimes getting stuck with a white border and faded colours after joining a group, until /reload. Hiding your own frame no longer hides and shows Blizzard's frames from add-on code, which broke their updates.
- Fixed an empty row (or your invisible frame overlapping another) when your own frame is hidden and the party re-sorts.
- The game's white target outline is cleared if it gets left on a frame that is no longer your target (also guards against other add-ons that change it, such as ForeverImmersion).
- Health bar colours now update when a new member's details arrive after they join.
- Chat notices: a short note on what's new after you update, and a heads-up when someone in your guild or group has a newer version.

## 1.4.0

- Fixed a Lua error ("Attempt to access forbidden object") when enemy nameplates appeared, e.g. in dungeons.
- Fixed party portraits in "own column / row" mode drifting away from their frames when the game re-arranged the party frames during combat. Until combat ends they now sit beside their own frame, then go back to the column.
- New General > Show your own party / raid frame. Turn it off (or type /rpt me) to hide your own frame from the raid-style party frames and raid frames. The other frames close up over its slot (raid frames need Keep Groups Together for that). Blizzard doesn't let add-ons hide these frames in combat, so a change made in combat applies when it ends, and if the game shows your frame again mid-fight it stays invisible.

## 1.3.0

- The "Party" / "Group N" label above the raid-style frames is now hidden by default. Turn it back on under General > Show the "Party" / "Group" label above the frames.

## 1.2.0

- New Health bar section: restyle the game's party (and raid) health bars with class colours, a by-health green-to-red colour or a custom colour, a top-to-bottom or left-to-right gradient that fades darker, lighter or to a custom colour, five textures, and a recoloured missing-health background. Off by default; dead and offline players keep the game's grey, and turning it off puts the game's look back.
- The preview's health bars now match your real frames: the game's colour and texture when restyling is off, your style when it's on, and a grey bar for the dead sample.

## 1.1.1

- Fixed pressing Escape triggering "has been blocked from an action only available to the Blizzard UI". The designer now closes on Escape with its own key handler instead of joining the game's Escape list.
- Opening the designer from Options no longer closes the Options window from add-on code (which could cause the same error). The designer opens on top of it.

## 1.1.0

- Threat: an outline or corner badge in the game's threat colours for you and every party or raid member, from "close to pulling aggro" or "has aggro", against any enemy or just your target, plus an optional threat % on your target.
- One "Spacing between party members" setting now moves the party frames apart (out of combat) and spaces their portraits to match, so each portrait stays lined up with its frame. It replaces the portrait-only spacing.
- The designer's buttons are now flat and match the window, with a gold highlight on the selected choice. Buttons fit their text, and long rows of choices wrap.
- The designer has a thin scroll bar that matches the window, and scrolls with the mouse wheel.

## 1.0.0

First public release.

- Portraits on raid-style party frames, and optionally raid frames, your own frame and pet frames.
- 3D models, 2D portraits or class icons. 3D models fall back to a 2D portrait or class icon for players too far away to load.
- Seven positions: left, right, above, below, inside left, inside right, or filling the frame.
- Party portraits can sit beside each frame, or in their own column or row with spacing and top / centre / bottom alignment.
- Square or round shapes, borders in class, custom, white or black, a background, opacity and zoom.
- 3D model face zoom, camera distance, turn, and animation on or off.
- An optional resource bar (mana, energy, rage...), optionally only for healers.
- A gold outline on your target's portrait, and grey-out or darken for dead and offline players.
- Follows the game's out-of-range fading, and every Edit Mode party frame setting (size, layout, opacity...).
- Buffs, debuffs, dispel highlights and status icons stay above portraits that sit inside the frame.
- The designer (`/rpt`): sidebar sections, setting search, a live preview, a reset icon on each setting, Reset this section, six built-in looks, your own saved looks shared across characters, and a Changes page.
