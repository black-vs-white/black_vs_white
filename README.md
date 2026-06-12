# Black vs White

The idea was to create a game that's based on an old warcraft 3 mod (Rabbits vs. Sheep), mixed with Vampire Survivor like gameplay.

## About this Project
This project is a somewhat working prototype for the idea to blend `Rabbits vs. Sheep` and `Vampire Survivors` into a unique,
tug-of-war style couch-coop game.

I plan to publish this to steam one day (free to play),
but because of a shift in priorities I'm not working on this as actively as I should, if I want to get this onto steam.

Because of that and because I wanted to release the code some time after the steam release anyway,
I decided to release the code ahead of time, in the hope that someone finds it useful.

## Licensing

The source code in this repository is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

Assets are licensed separately. See [assets/LICENSE](assets/LICENSE) and [assets/ATTRIBUTIONS.txt](assets/ATTRIBUTIONS.txt) for asset-specific licensing and attribution information.

## Setup
The project was set up so that it automatically downloads and builds the Odin compiler on windows.
This was done to help keep the Odin version in sync between contributors.

If you don't use vscode, make sure you run `git submodule update --init --recursive` once after cloning the repo.

## External Libraries Used
- raylib
  - vendored from Odin
- [sol](https://github.com/hardliner66/sol)
  - small collection of code I though might be useful outside of the game, so I made it available separately

## Directories and descriptions:
| Directory        | Description                                                                                                                                                           |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| assets           | Game assets that get distributed with the game. (sprites, backgrounds, default settings, etc.)                                                                        |
| extern           | Submodules for 3rd party code.                                                                                                                                        |
| publish          | Small helper I wrote to automate creating the description text for itch.io, including attributions.                                                                   |
| scripts          | The scripts used for setting up and building the project. (Currently Windows Only)                                                                                    |
| shader_templates | Simple templates for creating new shaders.                                                                                                                            |
| tools            | Tooling to build the engine. This folder is hidden in vscode because there normally isn't a need to see it. Currently only contains a submodule to the Odin compiler. |
| src              | The source code files.                                                                                                                                                |

## Files and descriptions:
| File Name   | Description                                                                                                                                 |
| ----------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 0_CONSTANTS | Contains all constants used in the game. Used to configure most things in the game.                                                         |
| 1_GAME      | Contains most struct definitions and most general game code. Contains the init and update functions.                                        |
| 2_GRAPHICS  | Contains most rendering/drawing related code.                                                                                               |
| 3_PHYSICS   | Contains most physics related code like collision detection and collision resolution.                                                       |
| 4_ENEMIES   | Contains most code related to enemies like enemy creation, as well as the `hit_enemy` and `enemy_died` functions.                           |
| 5_PLAYER    | Contains player creation. Most gameplay related code is actually handled in `1_GAME` or `3_PHYSICS`.                                        |
| 99_UTIL     | Utility and helper functions that don't fit into another category. Also contains wrappers for platform specific code to read file contents. |
| z_*         | Implementation details for specific platforms. **DON'T TOUCH UNLESS YOU KNOW WHAT YOU'RE DOING**                                            |

## Debug Flags
When starting a debug build, it will automatically enable debug mode.

Debug mode allows you to use your mousewheel to zoom and toggle some of the debug flags.
To toggle between debug mode on or off, you can use the key combination `LCtrl+LAlt+.`.

If debug mode is on, the title bar of the window will show that its running in debug mode (desktop only).

It will also enable the following key combinations:
| Key Combination | Description                                                                |
| --------------- | -------------------------------------------------------------------------- |
| `mwheelup`      | Zoom In                                                                    |
| `mwheeldown`    | Zoom Out                                                                   |
| `R`             | Press: Reset Zoom                                                          |
| `.`             | Press: Spawn Enemy                                                         |
| `LCtrl+LAlt+G`  | Toggle: God Mode                                                           |
| `LCtrl+LAlt+F`  | Toggle: Grid Text                                                          |
| `F7`            | Toggle: Draw Collision Boxes for Players                                   |
| `F8`            | Toggle: Draw Collision Boxes for Enemies                                   |
| `F9`            | Toggle: Draw Collision Boxes for Projectiles                               |
| `F10`           | Toggle: Draw Collision Boxes for Players, Enemies and Projectiles together |
| `LShift`        | Hold: Run at 1/5th of the speed                                            |
| `Space`         | Hold: Run at 5 times the speed                                             |
| `LShift+Space`  | Hold: Run at 10 times the speed                                            |
| `Space`         | Hold: Run at 15 times the speed                                            |

There are also some debug flags with don't have a key combination assigned. These can be set in
[here](https://github.com/black-vs-white/black_vs_white/blob/main/src/0_CONSTANTS.odin#L4).

For all available debug flags check
[here](https://github.com/black-vs-white/black_vs_white/blob/main/src/0_CONSTANTS.odin#L6).

## Rendering
To keep performance on the web acceptable, make sure you don't render more than necessary.
Objects that are out of view (+ some safety) don't need to be rendered.
You can check the other draw functions on how this is done.

## Shaders
If you want to add shaders, make sure they work on both desktop and web.
You can check the existing shaders to see how thats done.

### Main differences
Web starts with `#version 100` instead of `#version 330` and needs to set `precision mediump float;`.

#### In vs Varying
Instead of
```glsl
in vec2 fragTexCoord;
in vec4 fragColor;
```

web uses
```glsl
varying vec2 fragTexCoord;
varying vec4 fragColor;
```

#### Predefined output
Instead of defining its out value like this
```glsl
out vec4 finalColor;
```

web uses a predefined variable called `gl_FragColor`.

## Attribution for stuff you create
If you have created art and want to be attributed for it, add it to the list of
attributions.

For that, please add an entry to the end of the file in the following format:
```
File: <path/to/file>
Description: <Description>
Attribution: <Attribution>
Link: <Link>
License: <License>
---
```

including the 3 `-` as a separator.

- File: The path to the file you added, relative to the project root.
- Description: Describes what the asset is used for.
- Attribution: How you want to be attributed. This is normally the full name or nickname of the artist.
- Link: Optional. If the file is published somewhere, like [OpenGameArt](https://opengameart.org/), so that people can download the file.
- License: Optional. If you want to license your work, this is where the license name should go.