---
name: herdr-callsigns
description: Resolve a Herdr pane callsign (a short name like neon, mars, pluto shown on the pane border) to the pane ID that herdr commands require. Use whenever someone names a pane, terminal, or agent instead of giving an ID - "read the carbon pane", "what did bison say", "tell lima to rerun it" - before running any herdr pane or agent command. Also covers the plugin that assigns those callsigns.
---

# herdr-callsigns

Herdr panes carry a short callsign (`neon`, `mars`, `lima`) shown on the pane border. Users refer to panes by that callsign; the `herdr` CLI only accepts pane IDs (`wFB:p1`). Resolve the callsign to an ID first. In the API and the CLI the callsign is the pane's `label` field.

Never claim a pane does not exist until you have checked the label column. The `herdr` skill documents pane IDs and agent names only, so an agent following it alone will not expect `pluto` to resolve.

## Resolve a callsign

```sh
herdr api snapshot | jq -r --arg t bison '
  [.result.snapshot.panes[]?
   | select(.pane_id == $t or (.label // "") == $t)
   | "\(.pane_id)\t\(.workspace_id // "?")"]
  | unique | .[]'
```

The pane ID is the first tab-separated field. Read the number of lines:

* none - no such pane. A pane created moments ago may not be in the snapshot yet.
* one - use that pane ID.
* more than one - the callsign is duplicated across workspaces. Do not pick one silently: list the candidates with their workspace and ask which one.

A pane ID given instead of a callsign passes through unchanged, as long as it is present in the snapshot.

## List panes with both columns

```sh
herdr api snapshot | jq -r '.result.snapshot.panes[]? | "\(.label // "-") \(.pane_id) \(.workspace_id)"'
```

`herdr api snapshot` is server-global and is the right source for a lookup. `herdr pane list` carries the same panes and the same `label` column, and is server-global too unless you narrow it with `--workspace <id>`.

## Then act on the ID

```sh
herdr pane read <id> --source recent-unwrapped --lines 200
herdr pane run <id> "just test"
herdr agent prompt <id> "..."
```

A pane ID is a valid agent target when that pane hosts an agent.

## Callsigns are not agent names

They are independent namespaces. A pane with the callsign `pika` can host an agent named `con-3570-client-portal-web`, and panes without an agent still get a callsign. Resolve a callsign through the panes list; resolve an agent name through `herdr agent list`.

## Assignment

The plugin gives each new pane a callsign, and every pane still without one at startup. Existing callsigns are never overwritten, and they are unique across the server. Once the word list is exhausted it pairs two words, so a callsign may be compound (`bison-wapiti`). Beyond the pairs it can find, a pane is left without one rather than stalling the hook. The server may set `HERDR_CALLSIGNS_WORDS_FILE` to use a custom word list instead of the bundled one. To set one by hand: `herdr pane rename <id> <callsign>`.
