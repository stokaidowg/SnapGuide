# SnapGuide

A step-by-step **Alliance** levelling guide, **level 18 to 40**, built from the OctoWoW quest database (including OctoWoW/Turtle's custom quests). For **OctoWoW** (the 1.12 client). It may work on Turtle WoW and other 1.12 servers, but it was only made and tried on OctoWoW.

> [!WARNING]
> **Made with AI.** This add-on was written by an AI (Claude, by Anthropic) using Claude Code. I'm not a programmer: I described what I wanted, played with it on OctoWoW, and reported problems back for the AI to fix. It has automated tests against a simulated WoW API, but some features have only been tried by me, and a few not in game at all yet, so expect bugs. Please report them under **Issues**.

## What's in it

- **One step at a time**: accept, do, hand in, travel, fly, set your hearth. Quest steps tick themselves off from your quest log, and travel steps tick when you arrive.
- **An arrow** to the next spot, following walkable paths around mountains and water.
- **Targeting**: one key targets the mobs or NPC the current step needs. Quests you can do together are shown as one step.
- **Ahead of the route?** It quietly skips small quests that wouldn't be worth your time.
- **Extras**: a talent advisor (Retribution Paladin only, for now), an arrow back to your corpse when you die, and the window fades inside dungeons until you mouse over it.

Routes: Darkshore → Ashenvale → Stonetalon → Wetlands → Redridge/Duskwood → Ashenvale → Hillsbrad → Arathi → Alterac → Stranglethorn → Dustwallow → Desolace/Badlands → Swamp of Sorrows → Stranglethorn (to 40).

## Requirements

- Optional: **pfQuest** (it uses pfQuest's history of quests you've done), **SnapUI**, and **pfQuestGuide** (follows SnapGuide's current step).

## Install

1. Download `SnapGuide.zip` from the [Releases](../../releases) page. Don't use GitHub's green **Code → Download ZIP** button: it gives a folder named `SnapGuide-main`, which WoW won't load until you rename it to `SnapGuide`.
2. Extract it into `Interface\AddOns`, so you end up with `Interface\AddOns\SnapGuide\SnapGuide.toc`.
3. Restart the game, or type `/reload` if you're already logged in.

## Usage

- `/sg`: show or hide the guide
- `/sg routes` lists the routes, and `/sg route <number>` picks one
- `/sg skip` skips a step, and `/sg back` brings back the last one
- `/sg talents on|off`, `/sg fade`, `/sg arrow`

## For developers

`tools/` holds the route scripts (`tools/route/*.txt`) and the Node.js scripts that build `Routes/*.lua` and `Paths.lua` from the pfQuest database and the game's terrain. See `tools/README.md`. They expect the game in `H:/Games/OctoWoW`: change the paths in `tools/pfdb.js` and `tools/terrain.js`. The release zip leaves `tools/` out.

## Licence

MIT, see [LICENSE](LICENSE). Quest data comes from [pfQuest](https://github.com/shagu/pfQuest) and pfQuest-octo.
