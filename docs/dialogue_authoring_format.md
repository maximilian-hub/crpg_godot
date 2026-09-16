# Dialogue authoring format

Dialogue source uses UTF-8 text files with the `.dialogue` extension. One file
contains one conversation and its ordered pages. Lines beginning with `//` are
comments.

```text
@conversation hood_challenge

@page speaker=hood name="???" known=false portrait=hood_neutral
You made it this far.

@page speaker=hood name="Hood" known=true portrait=hood_neutral
[portrait=laugh_a]ha[portrait=laugh_b]ha.

@page speaker=hood name="Hood" known=true portrait=hood_neutral
Will you challenge me?
@choice text="Yes" target=accept_challenge
@choice text="No" target=decline_challenge
```

## Directives

- `@conversation <ID>` is required once and identifies the conversation.
- `@page` begins an ordered page. It requires `speaker` and `name`. `known` is
  `true` by default. `portrait` accepts a presentation ID or `none`.
- `@choice` belongs to the current page and requires a visible `text` label and
  a `target` ID. Choices remain hidden and inactive until the page finishes
  revealing. Up/down navigation wraps, confirm emits the highlighted target ID,
  and cancel emits a neutral request. Target interpretation belongs to the
  eventual gameplay dialogue runner; the presentation layer never executes it.

Attribute values containing spaces must be wrapped in double quotes.
Directive names and IDs are case-sensitive. IDs may contain letters, numbers,
underscores, dots, and hyphens. Unknown attributes are errors so authoring typos
cannot silently change behavior.

## Inline events

`[portrait=<ID>]` changes expression when reveal reaches that location. Tags do
not appear in visible text. The parser stores their positions as Unicode-visible
character indices, so earlier tags do not shift later events. For example:

```text
[portrait=laugh_a]ha[portrait=laugh_b]ha
```

produces visible text `haha` with portrait events at indices `0` and `2`.
Event index `0` occurs before the first character is revealed. Asset paths stay
outside prose; a speaker/presentation catalog will eventually resolve IDs such
as `laugh_a` to textures.

## Text presentation

`[color=<semantic-ID>]...[/color]` applies a named color supplied by the active
`DialogueSkin`. Dialogue files use names such as `emphasis`, `warning`, and
`mystery`, never asset-specific RGB or hexadecimal values. This lets another
compatible skin reinterpret the same narrative intent.

`[caps]...[/caps]` transforms its contents to uppercase before layout and reveal.
Color, capitalization, and speed spans may nest:

```text
[color=warning][caps]Do not[/caps] open the door.[/color]
```

Presentation tags do not count as visible characters. Capitalization is stored
in the page's final visible text, while semantic color remains a visible-indexed
span resolved by the view. Portrait events, authored speeds, voice requests, and
reveal therefore share one stable character-index space. A capitalization whose
Unicode uppercase form would change the number of characters is rejected to
prevent later event indices from becoming ambiguous.

### Semantic font size

`[size=<semantic-ID>]...[/size]` changes the size of its visible contents. The
initial shared skin defines `small`, `normal`, and `large`; their logical pixel
sizes belong to `DialogueSkin`, not to conversation prose.

```text
You hear a [size=small]faint whisper[/size], then:
[size=large][color=warning][caps]Run![/caps][/color][/size]
```

Size spans may nest or cross other presentation spans without changing visible
indices. The complete mixed-size document is shaped and wrapped before reveal.
If its measured width or height exceeds the dialogue text region, the Dialogue
Lab reports `OVERFLOW`; the runtime does not silently shrink it or create pages.
Authors should split or revise the page until automatic pagination receives its
own explicit design.

### Jiggly text

`[jiggle]...[/jiggle]` applies the shared `standard` jiggly-text style.
`[jiggle=<semantic-ID>]...[/jiggle]` selects another skin-defined style; the
initial skin provides `subtle`, `standard`, and `strong`.

```text
[jiggle=subtle]Something is nearby.[/jiggle]
[jiggle=strong][size=large][color=warning][caps]Run![/caps][/color][/size][/jiggle]
```

Dialogue source never specifies raw amplitude, frequency, phase, or randomness.
Those belong to `DialogueSkin`. Motion begins independently for each character
when reveal reaches its visible index. Offsets are deterministic and snapped to
whole logical pixels, and they affect drawing only—not shaping, wrapping, or
overflow measurement. Disabling animated text or enabling reduced motion renders
the same authored content statically.

Other animated effects and authored audio tags remain outside this milestone.

## Authored reveal speed

`[speed=<multiplier>]...[/speed]` changes reveal speed for its visible contents.
Values must be positive finite numbers. Spans may nest; nested values multiply.

```text
This is [speed=0.5]slow[/speed] and [speed=2.0]fast[/speed].
```

The parser resolves a multiplier for every visible Unicode character before
presentation begins. A player speed setting multiplies the authored value rather
than replacing it, preserving relative emphasis. Speed tags affect layout only
by being removed; all text is laid out in full before reveal starts.

## Reveal semantics

An indexed event fires immediately before the character at that index appears.
This includes events at index zero. Punctuation pauses occur after punctuation
and before the following character. Confirm completes a page that is still
revealing; confirm on an already complete page requests advancement. Immediate
completion executes all remaining events in source order.
