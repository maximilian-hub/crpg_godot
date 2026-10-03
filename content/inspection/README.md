# Overworld inspection authoring

Inspection text uses the shared dialogue format with speakerless inspection pages:

```text
@conversation unique_object_id

@page mode=inspect
The first page of environmental text.

@page mode=inspect
An optional second page.
```

Add an `OverworldInspectable` node with `scripts/overworld/inspectable.gd` and
assign its `dialogue_path` in the Inspector. Place the marker anywhere inside
the target 16x16 grid cell; the editor outline shows the resolved cell.

Add one or more child nodes using
`scripts/overworld/inspectable_interaction_point.gd`. Each point marks a cell
where the player may stand and has a `required_facing` direction. The cyan
editor outline and arrow show the resolved player cell and facing.

- Make the marker a child of a prop when it should move with that prop.
- Place it independently under the overworld for hidden walls or locations
  without a dedicated visual node.
- Give separate parts of a larger prop separate markers and dialogue files.
- Add only the interaction points that make visual sense. A prop that can be
  approached from the front and walked behind normally has a front point below
  it facing Up and a behind point on its walkable cell facing Down.

The player activates an inspectable when their current cell and facing match
one of its interaction points. Interaction points are independent of the
prop's sprite and collision footprint. NPC interaction takes priority.
