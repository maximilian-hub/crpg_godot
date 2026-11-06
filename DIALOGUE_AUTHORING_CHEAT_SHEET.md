# Dialogue Authoring Quick Reference

Dialogue files are UTF-8 text files ending in `.dialogue`. One file contains one conversation and its ordered pages.

## Minimal file

```text
@conversation hood_greeting

@page speaker=hood name="Hood" known=true portrait=neutral
You made it this far.
```

## Page header

```text
@page speaker=hood name="Hood" known=true portrait=neutral
```

- `speaker`: stable speaker/profile ID.
- `name`: name stored for the page; quote it if it contains spaces.
- `known=true`: show the name.
- `known=false`: show `???`.
- `portrait`: starting portrait ID, or `none` for the empty portrait state.

Start another page with another `@page` directive. A page must contain visible text.

## Inline tags

### Change portrait

```text
[portrait=laugh_a]Ha!
I am [portrait=laugh_b]not amused.
```

The portrait changes immediately before the following visible character appears.

```text
[portrait=laugh_a]ha[portrait=laugh_b]ha[portrait=laugh_a]ha!
```

Portrait IDs must already exist in the speaker profile. Inline `portrait=none` is not currently supported.

Hood currently provides these portrait IDs:

```text
neutral
laugh_a
laugh_b
annoyed
disappointed
thinking
wistful
```

`hood_neutral` remains accepted as a legacy alias, but new dialogue should use `neutral`.

Portrait IDs belong to the page's speaker. Multiple characters can all define
`angry`; `speaker=hood portrait=angry` selects Hood's version, and inline
`[portrait=angry]` continues using that page's speaker. Start a new page to
change speakers.

### Reveal speed

```text
[speed=0.5]slow[/speed]
[speed=2.0]fast[/speed]
```

Positive multipliers are accepted. The player's global speed setting also applies.

### Semantic color

```text
[color=emphasis]important[/color]
[color=warning]dangerous[/color]
[color=mystery]unknown[/color]
```

### Uppercase

```text
[caps]Run now![/caps]
```

### Semantic size

```text
[size=small]a whisper[/size]
[size=normal]ordinary text[/size]
[size=large]RUN![/size]
```

Large text affects wrapping. The system reports overflow but does not paginate or shrink text automatically.

Text size also controls character-voice volume:

- `small`: speaker base volume −12 dB
- `normal` or untagged: speaker base volume
- `large`: speaker base volume +6 dB

Skipping a partially revealed page plays one blip, using the loudest text size
remaining in the skipped range. It does not play every remaining character blip.

### Jiggly text

```text
[jiggle]standard motion[/jiggle]
[jiggle=subtle]subtle motion[/jiggle]
[jiggle=strong]strong motion[/jiggle]
```

Reduced-motion settings display the same text without movement.

## Combining tags

Tags can nest. Close them in reverse order:

```text
[jiggle=strong][size=large][color=warning][caps]Run![/caps][/color][/size][/jiggle]
```

Portrait tags are instantaneous events and do not need closing tags:

```text
[color=warning]I said [portrait=laugh_a][speed=0.5][caps]run[/caps][/speed]![/color]
```

Tags do not appear in the displayed text or disturb portrait-event indices.

## Choices

Place choices after the page text:

```text
@page speaker=hood name="Hood" known=true portrait=neutral
Will you challenge me?
@choice text="Yes" target=accept_challenge
@choice text="No" target=decline_challenge
```

- `text`: visible choice label.
- `target`: stable ID emitted when chosen.
- Choices appear only after the page finishes revealing.
- Left/right changes the selection; confirm emits the target.
- Targets are reported but not interpreted by the dialogue system yet.

## Comments and line breaks

```text
// This entire line is ignored.
```

Lines within a page are preserved. Prefer natural UI wrapping unless an authored line break matters.

## Syntax rules

- Quote attribute values containing spaces: `name="Mysterious Voice"`.
- IDs may contain letters, numbers, `_`, `.`, and `-`.
- IDs and directive names are case-sensitive; lowercase `snake_case` is recommended.
- Unknown directives, attributes, and inline tags are errors.
- Every opening span tag requires its matching closing tag.
- One page currently has one speaker.

## Full compact example

```text
// Hood confronts the player.
@conversation hood_confrontation

@page speaker=hood name="Hood" known=false portrait=neutral
You made it this far.

@page speaker=hood name="Hood" known=true portrait=laugh_a
They call me [color=mystery][caps]Hood[/caps][/color].

@page speaker=hood name="Hood" known=true portrait=neutral
I have waited [speed=0.5]a very long time[/speed].

@page speaker=hood name="Hood" known=true portrait=neutral
[portrait=laugh_a]ha[portrait=laugh_b]ha[portrait=laugh_a]ha!

@page speaker=hood name="Hood" known=true portrait=neutral
Will you challenge me?
@choice text="Draw your weapon" target=accept_challenge
@choice text="Walk away" target=decline_challenge
```

## Not supported yet

Branch labels/jumps, automatic target interpretation, automatic pagination, explicit pause tags, inline sound commands, mid-page speaker changes, inline `portrait=none`, bold/italic tags, and a visual authoring editor.

## Adding an overworld NPC

The reusable NPC scenes live in `scenes/overworld/npcs/`. To populate an
overworld, instantiate `grunch.tscn` or `tavernkeeper.tscn` as a child of that
scene's `YSortedWorld`, then place it on a 16-pixel cell center (for example,
cell `(4, 3)` is position `(72, 56)`). The tavern test world intentionally ships
empty so its cast can be authored in the editor.

Set the instance's `facing` property to its initial direction. Grunch follows
the usual convention and mirrors his right sprite when facing left. The
Tavernkeeper has an authored `left_texture`, so she never mirrors her side art.
Only the `0001` idle sprites are used for now.

For ordinary conversation, create a `.dialog` or `.dialogue` file and assign it
to the NPC instance's `dialogue_path`. For example:

```text
@conversation tavern_greeting
@page speaker=tavernkeeper name="Tavernkeeper" known=true portrait=smiling
Welcome in. Find yourself a seat.
```

The available Grunch portraits are `neutral`, `alert`, `drag_cig`, `exhale_1`,
`exhale_2`, `flick_cig`, `hold_cig`, and `light_cig`. Tavernkeeper supports
`neutral`, `smiling`, `laughing`, `flustered`, `sad`, `worried`, `surprised`,
`tired`, `crazy`, and `firm`. Both are silent until voice clips are assigned to
their speaker profiles. An NPC with an `encounter_profile` uses the battle
challenge flow instead of `dialogue_path`.

The Skeleton speaker ID is `skeleton` and currently supports the `neutral`
portrait. Its overworld NPC scene is `scenes/overworld/npcs/skeleton.tscn`.
