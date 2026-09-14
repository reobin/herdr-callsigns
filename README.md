# herdr-callsigns

Auto-names every herdr pane with a short, memorable callsign (`neon`, `mars`, `lima`), so you and your agent can refer to panes by name or label instead of ID.

![Demo: asked what is failing in the mars pane and to tell lima to fix it, the agent loads the herdr-callsigns skill, resolves both callsigns to pane IDs, reads the failing test from mars, then prompts the lima agent with the fix](assets/demo.gif)

## Install

```sh
herdr plugin install reobin/herdr-callsigns
herdr plugin action invoke herdr-callsigns.install-skill
```

The second command installs the `herdr-callsigns` skill into this machine's agent skill directories, for Claude and `~/.agents`-style harnesses. Check it landed with `herdr plugin log list --plugin herdr-callsigns`.

## Use

You never type pane IDs. Say the callsign:

- to an agent: `check output of pane neon`, `tell the agent in lima pane to rerun the scan`.
- the agent resolves the callsign to a pane ID with the `herdr api snapshot` filter from the skill, then runs `herdr pane read <id>` or `herdr agent prompt <id>`.

A callsign duplicated across workspaces is never guessed. The agent lists the candidates with their workspace and asks which one.

## Rules

- Existing callsigns are never overwritten.
- Callsigns are unique across the server.
- Once the word list is exhausted, callsigns pair two words (`neon-mars`). That is 30 single names plus hundreds of pairs; beyond that a pane is left without one.
- Callsigns and agent names are independent. A pane with the callsign `pika` can host an agent named `reviewer`.

## Custom word list

```sh
export HERDR_CALLSIGNS_WORDS_FILE="$HOME/.config/herdr/callsigns-words.txt"  # one single-word token per line, no spaces
# then (re)start the herdr server so the hook picks it up
```

Applies to the whole server, not per person. Switching later is safe: existing callsigns are kept.
