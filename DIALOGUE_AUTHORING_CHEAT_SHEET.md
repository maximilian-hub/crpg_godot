# Dialogue Authoring Quick Reference

Dialogue files are UTF-8 text files ending in `.dialogue`. One file contains one conversation and its ordered pages.

## Minimal file

```text
@conversation hood_greeting

@page speaker=hood name="Hood" known=true portrait=hood_neutral
You made it this far.
```

## Page header

```text
@page speaker=hood name="Hood" known=true portrait=hood_neutral
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
@page speaker=hood name="Hood" known=true portrait=hood_neutral
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

@page speaker=hood name="Hood" known=false portrait=hood_neutral
You made it this far.

@page speaker=hood name="Hood" known=true portrait=laugh_a
They call me [color=mystery][caps]Hood[/caps][/color].

@page speaker=hood name="Hood" known=true portrait=hood_neutral
I have waited [speed=0.5]a very long time[/speed].

@page speaker=hood name="Hood" known=true portrait=hood_neutral
[portrait=laugh_a]ha[portrait=laugh_b]ha[portrait=laugh_a]ha!

@page speaker=hood name="Hood" known=true portrait=hood_neutral
Will you challenge me?
@choice text="Draw your weapon" target=accept_challenge
@choice text="Walk away" target=decline_challenge
```

## Not supported yet

Branch labels/jumps, automatic target interpretation, automatic pagination, explicit pause tags, inline sound commands, mid-page speaker changes, inline `portrait=none`, bold/italic tags, and a visual authoring editor.
