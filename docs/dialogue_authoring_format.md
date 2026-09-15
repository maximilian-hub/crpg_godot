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

This initial grammar intentionally excludes authored pauses, color, size, motion,
and audio tags. Those can extend the same visible-character model after the
basic reveal behavior has been evaluated.

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
