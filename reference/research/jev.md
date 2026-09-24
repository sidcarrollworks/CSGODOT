# Jev: where TypeSafe's decision model could fit in the game

Ideas, not a plan. Sid asked (2026-09-24) for ways to use Jev in the game,
starting from his note to "experiment with the bot AI and Jev". Nothing here
is built, and nothing here changes the roadmap's order.

## Sources, and what could not be read

- **TypeSafe's own docs could not be read from a cloud thread.**
  `docs.typesafe.ai` and `typesafe.ai` are refused by the thread's network
  proxy, so the use-case map Sid linked
  (https://docs.typesafe.ai/concepts/use-case-map) was not read directly.
  Sid can allow the host under Network access in Project settings, or paste
  the pages. Search summaries say the map is organised by industry
  (customer service, insurance, compliance, legal): routing, classifying,
  prioritising and escalating documents. It has no games section.
- TypeSafe's own agent skill, `typesafe-ai/skills` on GitHub
  (`skills/typesafe-ai/SKILL.md`, MIT, read 2026-09-24): the programming
  model and how to design questions. **Primary.**
- `walidboulanouar/awesome-jev-use-cases` (README, CC0, read 2026-09-24):
  an unofficial list that quotes TypeSafe's models, limits ("jaggedness",
  last reviewed 2026-09-17) and API pages, and lists the game demos.
  **Secondary**; the numbers below come from its quotes of TypeSafe's pages.
- `fhshaik/typesafe-mario` (read 2026-09-24): a working game loop with Jev
  choosing Super Mario Bros. inputs. Its `policy.py` is the closest example
  to what a bot would send.

## What Jev is, in the terms that matter here

- One HTTPS endpoint (`api.typesafe.ai/v1/systemone`). A request is a
  **state** (text or JSON) and a map of named **questions**; every question
  is answered in one parallel pass. Three question types:
  - **Choice** picks one of a set of options and gives each option's
    probability and a confidence.
  - **Score** places the state on an ordered rubric of levels.
  - **Noul** is a yes-or-no probability.
- It writes no text. Output is free; input is $0.042 per million tokens.
- **Latency 70 to 500 ms**, most near 100 ms, measured from the US West Coast
  where the service runs (TypeSafe's launch post). Limits: 1,200 requests a
  minute, 250,000 tokens a second, 32k tokens for the state plus the longest
  question, 64k per request. Text input only.
- It is not a calculator: counting, distances, angles and timing stay in
  code. Accuracy falls when the state carries things the question does not
  need, so the state is filtered first. Text in the state can steer the
  answer. Separate questions about the same thing need not agree.
- It is a hosted service only: no weights to download, no fine-tuning.
  Open stand-ins exist (`razorback16/openjev`, `wfzyx/von` "sub-15 ms,
  local", `logan-markewich/jeff`) but none has been tested here.

Game demos so far (all from the list above): Doom, Super Mario Bros., Smash
Bros., Subway Surfers, Tetris and Slay the Spire 2, and levels generated
while playing. The Doom and Mario players read **compact JSON of the game's
state** (enemies, distances, angles, projected contacts), not pixels; the
Mario one decides every eight emulator frames and holds its choice between.

## What this means for our game

A 64 Hz tick is 15.6 ms. Jev answers in 70 to 500 ms. So:

1. **Jev never runs inside the tick.** Aim, recoil control, strafing,
   reaction time and shooting stay in code, as now (`bot.gd` `_think`).
   `CLAUDE.md` already forbids reading the disk during a tick; a network call
   is worse.
2. **Jev decides the slow things**: what a team does this round, where a bot
   goes next, when to rotate or save. Those are decisions CS2's own bots make
   every few seconds at most, and a human team makes over voice.
3. **A request is asked on one tick and answered on a later one.** The answer
   enters the simulation the way a player's input does: on the tick it
   arrives, as data the bot reads. A match with Jev is then only
   reproducible if each answer is logged with the tick it was applied on, so
   a replay reads the log rather than asking again.
4. **Every decision needs a rule-based fallback**: no API key, no network,
   a timeout, or low confidence. The game must play without Jev (the Mario
   project keeps a `HeuristicPolicy` for the same reason). Our offline game
   would otherwise need the internet and a key.
5. **Code does the numbers; Jev reads the situation.** The state sent is
   already worked out: "3 CTs alive, bomb planted at B 12 s ago, last enemy
   seen at Tunnels 4 s ago", with place names from the map's `env_cs_place`
   entities (`SourceEntities.places`), not raw coordinates.
6. **Cost is small.** Ten bots each asking once every 2 s with a 2,000-token
   state is 5 requests a second (well under 1,200 a minute) and about
   18 million tokens in a 30-minute match: about $0.75. A per-team call once
   a round costs a fraction of a cent a match.

## Ideas

Ordered by how well each fits, best first. Each says what code keeps.

### 1. The team's round plan in freeze time (bots)

Roadmap item 24 still lacks a team plan ("full buy, force, save"), and B8 of
`round-hud-bots.md` found Valve's own dust2 routes (`goto_a_via_cat_from_t`,
`goto_b_site_from_t`, ...) picked by a random strategy number.

- **When:** once per team at the start of freeze time (15 s to answer).
- **State:** score, round number, each player's money and weapons, loss
  bonus, the last few rounds' outcomes and where they were won or lost, what
  the enemy did (which site they hit, what they bought).
- **Questions:** Choice of buy (full, force, eco, half), Choice of strategy
  from the route table (default, A long, A short, B rush, split, fake), a
  Noul "the enemy is likely to save".
- **Code keeps:** prices and what each bot buys (`BotBuying`), the routes
  themselves, who walks which.
- Why it fits: plenty of time, two calls a round, and it gives the bots a
  plan that reacts to the match instead of a random number. Fallback: CS2's
  random strategy, as now.

### 2. Mid-round calls (bots)

- **When:** on an event, not a timer: a teammate dies, the bomb is spotted,
  planted or dropped, an enemy is heard, 30 s left. At most one request per
  team in flight.
- **State:** alive counts, bomb state and place, last sightings and sounds by
  place and age, time left, each bot's place and health.
- **Questions:** Choice per bot of rotate / hold / retake / save / lurk /
  push, a Noul "the attack is a fake".
- **Code keeps:** the paths, the timing checks (can we reach B before the
  bomb goes off: code, not Jev), and a freshness check that drops an answer
  if the situation changed while it was asked.

### 3. Each bot's intent at about 2 Hz (bots)

The layer between the plan and the reflexes: hold this angle, peek, fall
back, wait for the flash, play for a trade, get out of the fire. Roadmap item
23 lists cover, holding angles and reacting to sound.

- A Choice of intent and a Score of danger, as the Mario player asks.
- **Code keeps** reaction time and aim error, which the roadmap calls "the
  honest way to set difficulty". Jev does not make bots aim better.
- Riskier than 1 and 2: 500 ms answers are stale in a gunfight, and ten bots
  asking twice a second is 20 requests a second, the whole 1,200-a-minute cap.
  One request per team with one question per bot stays under it, at some
  accuracy cost (the list's "many items in one state" pattern).

### 4. Orders to bots in plain words (single player)

The player types or says "two of you hold long, rest B" or "save this round",
and a Choice (with Score/Noul for counts and places) turns it into the same
orders idea 2 gives, with place names as options. This is the "function
calling" and "intent routing" patterns in TypeSafe's cookbooks. CS2 offers
radio commands only; this is an improvement over it, not a copy of it. It
needs a text box or speech-to-text, which Jev does not do.

### 5. The bots' voice lines

CS2's bots talk from `botchatter.db` (`round-hud-bots.md` B1).
A Choice can pick which line fits the moment ("enemy spotted at long",
"need backup", "I'm going B") from the lines the file has. No text is
generated, so it stays CS2's words. Cheap, but code rules may do nearly as
well.

### 6. A round coach (single player)

After a round, the event log (computed in code: died untraded, bought with
poor money, peeked while reloading, no flash before the peek) goes to Jev,
and Nouls and a Choice pick one tip from a fixed list to show in the
round-end panel. Useful for new players; off the tick entirely.

### 7. Multiplayer: chat moderation and report triage

When multiplayer lands (Phase 9): a Noul per chat message for abuse and spam
(the list's "live chat moderation" idea), and a Score to order player
reports for a human. Both are TypeSafe's documented strengths. The list
warns that text written to fool the classifier is the main risk, so the
threshold decides only what a person looks at first.

### Not a fit

- Anything per tick: aiming, movement, recoil, hit registration. Too slow
  by 5 to 30 ticks, and it would make the server depend on a network call.
- Anti-cheat by judging aim: that is arithmetic over timing and angles,
  which Jev's limits page says to keep in code.
- Deciding outcomes that must be the same on every run (tests, replays)
  without logging the answers.

## How it would plug in

A sketch for when Sid picks one, within `reference/systems/contracts.md`:

- A `JevClient` in `src/bots/` sends requests off the tick (Godot's
  `HTTPRequest`, per frame) and never blocks it. The API key comes from the
  environment or a user setting, never the repo.
- A bot "strategist" system joins `world.game`. On the events it listens to,
  it builds the state from `game.query` and the events, asks, and queues the
  answer; on the next tick after it arrives it applies it as the team's or
  bot's orders, which `bot.gd` reads the way it reads `route` today.
- Every request and answer is logged with its tick, so a round can be
  replayed and a bad call can be read afterwards.
- A fallback rule for every question, used on no key, a timeout or a
  confidence under a threshold tuned on logged rounds.
- Headless checks run with a fake client that returns fixed answers, since
  CI has no key.

## Suggested first experiment

Idea 1 on dust2: one call per team per round, with the route table from
Valve's dust2 training tree (B8) as the strategy options and CS2's random
pick as the fallback. It needs no change to how bots aim or move, costs
almost nothing, and shows quickly whether Jev's plans read as sensible
across a half. It needs an API key on Sid's machine, and bots that follow a
route table, which roadmap item 24 builds anyway.
