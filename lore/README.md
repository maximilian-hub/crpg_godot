# Lore

This directory is the narrative source of truth for writing, continuity, and
quest planning. It should stay concise enough to load at the start of a writing
session and specific enough to settle a continuity question.

It is not a scrapbook. Superseded ideas belong in Git history, final dialogue
belongs in `content/`, and technical implementation belongs with the code and
design documents that own it.

## Start here

For any narrative task, read in this order:

1. [Current focus](current-focus.md)
2. [Creative vision](vision.md) and the [core theme](themes/core.md)
3. [Writing framework](writing-framework.md)
4. [World](world.md) and [story overview](story/overview.md) when the task
   touches the wider game
5. [Narrative design](narrative-design.md) when designing choices, quests,
   relationships, location outcomes, or endings
6. The relevant page from the [location](locations/index.md),
   [character](characters/index.md), [faction](factions/index.md), or
   [quest](quests/index.md) index
7. Pages directly linked by that page

Do not load every entity page by default. The links are the context-routing
system: start broad, then follow only what the current task touches.

## Truth labels

Every page has one overall status:

- **Canon:** deliberately committed. Change it only as an explicit revision.
- **Working:** the current direction and safe to design against, but still
  revisable.
- **Seed:** a useful structure or possibility with important decisions still
  open.

Within a page, keep these kinds of information separate:

- **Confirmed canon:** facts the project has consciously committed to.
- **Current direction:** the best present answer, not yet locked.
- **Existing material:** facts or implications found in prototypes, dialogue,
  or implementation. Existing material is evidence, not automatically canon.
- **In-world claim:** something a character, culture, or text believes. It may
  be incomplete or false.
- **Open questions:** undecided matters. Never silently answer these while doing
  unrelated writing.

When two pages conflict, flag the conflict rather than quietly choosing one.

## Ownership and links

Each fact should have one natural owner. A character page owns that character's
motives; a location page links to the character rather than restating the whole
profile. Short summaries are fine when they explain the local relationship.

Use ordinary relative Markdown links. Link to implementation when it is useful
evidence, but summarize narrative meaning here instead of requiring a writer to
read scene or script files.

Create a page when an idea has enough substance to retrieve later. Do not make
empty pages for every possible person, item, faction, or historical event.

## Maintenance rule

After a brainstorming session produces a real decision:

1. Update the page that owns the decision.
2. Remove or rewrite the resolved open question.
3. Check directly linked pages for contradictions.
4. Update [current focus](current-focus.md) if the active writing target changed.

Git is the change log. Live pages should describe the game as it is understood
now, not narrate how the idea evolved.

## Templates

- [Theme](templates/theme.md)
- [Character](templates/character.md)
- [Location](templates/location.md)
- [Quest or questline](templates/quest.md)
- [Item](templates/item.md)
