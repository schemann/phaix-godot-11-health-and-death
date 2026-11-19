# Health and Death

Project files for tutorial 11 of the Godot 4 series by Phaix on YouTube (https://www.youtube.com/@Phaix).

Add health, a hazard that hurts and a death screen to a game like Roblox DOORS in Godot 4, and give the player one revive per run.
A Health node on the player, an Area3D hazard that hits on a Timer, a death screen that says what hit you, and a revive that puts the player back in the room where they died.

Health is a node of its own, so whatever hurts only looks for a child called Health and never needs to know what it belongs to. The hazard is an Area3D that reports every body that steps in or out, finds that body's Health node and hits it on a Timer, so every hit has the same size and the HUD counts down in clear steps. The run gets a state of its own, DEAD, and the death screen names the cause: Hit by Live Wire, Hit by Broken Glass. One revive per run puts the player back just inside the entrance of the room they died in, with full health and the clock still running; nothing is saved, because the run is still there. Every step is its own project folder.

## Steps

Every step of the video is its own folder in `steps/`, the exact state at the end of that
part. Open the project in Godot 4.7, then open `steps/<step>/main.tscn` and press F6 to run
that step. The project's main scene is the final step.

| Folder | Part of the video |
|---|---|
| `steps/step_00_start` | Starting point (the final state of tutorial 10) |
| `steps/step_01_health` | Step 1 - Health |
| `steps/step_02_a_hazard_that_hurts` | Step 2 - A hazard that hurts |
| `steps/step_03_the_death_screen` | Step 3 - The death screen |
| `steps/step_04_one_revive_per_run` | Step 4 - One revive per run |

## Controls

- W A S D or the arrow keys walk, and so does the left stick of a gamepad.
- The mouse or the right stick looks around.
- Space or the A button jumps.
- Esc gives the mouse back, and a left click captures it again.
- Hold Shift, or hold the left stick pressed in, to walk slowly.
- V or the left shoulder button shows your body from a second camera above the door, and V again gives the view back.
- Tab or the Back button shows and hides the map.
- R or the Y button starts the run again on the same seed.
- N or the right shoulder button starts a run on the next seed.
- T opens the seed box: type a seed and press Enter to start a run with it, or press Esc to close the box and change nothing. While the box is open, every other key you press goes into it.
- C or the X button copies the seed to the clipboard.
- F3 shows and hides the gizmos: the box of every planned room and its markers, drawn through the walls.
- F4 lifts the camera above the rooms to watch the generator, Enter plans the next room while you watch, and F4 again gives the view back.
- O or the Start button opens the settings. In them, the arrow keys, the d-pad or the left stick move between the rows, left and right change a volume, Enter, Space or the A button turns an effect on or off, and O, Start or Esc closes them.
- After a death, E gets you back up once per run, at the entrance of the room you died in.

## Tests

```sh
godot --headless --path . -s res://tests/run_tests.gd
```

## Support

Support the channel: https://ko-fi.com/phaix or https://github.com/sponsors/schemann

## License

Code and scenes: MIT (see LICENSE).
The figure and its animations: Animated Characters Protagonists by Kenney (www.kenney.nl), CC0, see character/License.txt.
The sounds (footsteps, doors, lock, key): RPG Audio by Kenney (www.kenney.nl, https://kenney.nl/assets/rpg-audio), CC0, see sounds/CREDITS.md.
