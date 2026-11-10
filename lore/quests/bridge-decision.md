# Starting village: bridge decision

Status: Working

## Purpose

- **Place in the story:** Village-scale storyline after the player has received
  their first king and spent time exploring the community
- **Major theme:** [Living a good life without becoming a piece or treating
  others as pieces](../themes/core.md)
- **Thematic question:** When a community's shared safety and prosperity require
  real sacrifice, how do good people decide who should bear it—and how much
  control can they trade away to escape the danger?
- **Primary location:** [Starting village](../locations/starting-village.md)
- **Institution:** [E4 Land Acquisition](../factions/e4.md)

The conflict should show fundamentally decent people disagreeing under pressure.
The village has coped with the illness of its most capable elder because nothing
serious required his old coordinating role. The bridge crisis is the first
problem large enough to expose that absence.

## Situation

- The storm associated with the player's arrival has left the crevice bridge in
  need of dangerous, difficult repair.
- The remaining elders are frightened by the practical risk and uncertain of
  their ability to coordinate a solution.
- E4's Land Acquisition division previously offered to buy the road and
  associated land or rights to build an interstate.
- The tavernkeeper's father opposed the proposal adamantly while he was active
  in village affairs.
- The bridge crisis puts the old offer—and its sizable cash payment—back on the
  table.

Selling offers professional infrastructure and security. Refusing preserves
local control but leaves the village responsible for organizing and surviving a
dangerous repair. Neither answer should be harmless.

## Pacing

This storyline must not begin immediately after the professor tutorial.

1. The player receives their first king piece.
2. The game enters a period of free village exploration across multiple parts
   of the day/night cycle.
3. Microquests and environmental encounters let the player meet residents,
   visit the village boundaries, understand the bridge, and experience ordinary
   life before deciding its future.
4. The deliberation becomes available only after enough time or local activity
   has passed.
5. Returning to the tavern or another communal space naturally places the
   player near the meeting.

The trigger should be progression-gated rather than a punishing real-time
deadline. Exploration order can remain flexible.

## Village deliberation

Residents and elders gather to discuss the bridge and E4 offer. There is genuine
disagreement rather than a unified village position.

The elders ask the tavernkeeper whether her father is well enough to speak that
day. She says he had a bad morning. Under pressure to see whether he is lucid
now, she reluctantly agrees to let the group visit him.

Why the player is included—especially after ignoring or joining the opening
bullying—remains a staging problem to solve. They do not need formal voting
rights; they only need a natural reason to be present.

## Father's death

The father is dying but lucid. He is happy to see his daughter, friends, and
neighbors. He is more interested in affectionate memories, farewells, and well
wishes than in conducting a practical bridge meeting.

Someone eventually presses him to say whether the village should sell or repair
the bridge itself. With his final smiling breath, he says approximately:

> Don't sell, you fools. [Village name] can fix it.

The line is intent, not final dialogue.

Only the player hears him clearly. As everyone tries to determine what he said,
the player can:

- Relay his words honestly, inspiring confidence in the village's ability to
  solve the problem and direct its own identity.
- Lie and say he supported selling the land to E4.

Additional responses such as withholding the words or separating honest
testimony from the player's own policy recommendation remain under consideration.

## Design requirements

- The father's death should primarily be a farewell between people who love one
  another, not a plot briefing delivered from a deathbed.
- His final words can change the village's confidence but should not magically
  repair the bridge or settle every practical disagreement.
- Selling must provide credible safety and material benefits.
- Repair must carry real danger, labor, expense, and risk of failure.
- The player needs a concrete personal incentive to favor the sale or lie about
  the final words.
- The village's response should depend on more than unquestioning obedience to
  a dead patriarch.
- Microquests completed before the meeting should be able to alter knowledge,
  relationships, available plans, or confidence.

## Possible state separation

Keep testimony and policy distinct enough to support nuanced reactions:

| State | Candidate values |
| --- | --- |
| Report of final words | `honest`, `lied_for_sale`, `withheld_or_uncertain` |
| Player's advocated solution | `repair`, `sell`, `alternative`, `none` |
| Village confidence | Low to high, or authored states |
| E4 relationship | Hostile, neutral, favorable |

This is a design recommendation, not a final branch specification.

## Open questions

- Why is the player present for the deliberation and intimate farewell on every
  opening branch?
- What reward makes helping E4 personally tempting at this early stage?
- Who revives the offer, and when does the player meet them?
- What exact land, road, and governance rights would the village sell?
- What does repairing the bridge require in labor, materials, expertise, and
  Chess Power?
- How can the canyon camp participate, and what would it ask in return?
- Which elders or residents embody the strongest competing positions?
- Does the father know the player is present, and has he heard about their first
  tavern choice?
- How do earlier microquests change the feasible solutions?
- What village states result from a sale, communal repair, coerced repair,
  failure, or neglect?

