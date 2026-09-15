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
  a `target` ID. Target interpretation belongs to the eventual dialogue runner.

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

This initial grammar intentionally excludes timing, pauses, color, size, motion,
and audio tags. Those will extend the same visible-character event model after
the basic authoring experience has been evaluated.
