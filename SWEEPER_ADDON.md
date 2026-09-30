# CN Map Sweeper — our code inside the gamemode tree

Everything under these paths is OURS (the former `mapsweepers_skills` addon), merged in on
2026-09-25 so there is one tree to edit. Nothing else in this folder is ours.

    lua/autorun/sh_sweeper.lua     the loader: every include lives here
    lua/sweeper/                   43 files - classes, specs, missions, HUD, options, systems
    lua/entities/sweeper_*.lua     6 objective / deployable entities
    materials/sweeper/icons/       70 HUD icons

The gamemode's own files are untouched: we still change its behaviour only by wrapping `jcms.*`
functions and using hooks, with the `S.Wrapped` / `S.MarkWrapped` markers so two of our files can
never wrap the same function twice. That discipline is what keeps the merge reversible.

## Taking a new Map Sweepers version

Because our files sit in their own folders and edit none of theirs, an update is a swap:

    1. Copy the four paths above somewhere safe.
    2. Drop the new gamemode version in.
    3. Copy the four paths back.
    4. Start the server and watch the console for "[Implants] couldn't ..." errors - those mean a
       function we wrap was renamed or removed upstream. Everything wraps inside pcall, so the
       addon degrades rather than crashing the gamemode.

## Naming

Our identifiers all start with `sweeper` (global table, entity classes, networked vars, commands,
data folders, SQL table). Convars we added that tune the gamemode's own features keep its `jcms_`
prefix on purpose - `jcms_thirdperson`, `jcms_iconhud_*`, `jcms_team_*`, `jcms_vtokens_*`,
`jcms_records*`, `jcms_shop_*`, `jcms_implant_*` - so they sit with its settings in the options tab.
