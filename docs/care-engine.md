# Care engine rules

The care engine (`Packages/PlantyKit/Sources/PlantyKit/CareEngine`) is deterministic: the same plant, history and date always give the same result. It never says a plant definitely needs water. It says a plant *may* need care, and the app asks the user to check the soil.

## Watering window

1. **Species baseline.** Each species has a watering range in days for spring and autumn (for example Monstera 7 to 12), backed by a cited source.
2. **Season.** Summer × 0.85, spring and autumn × 1.0, winter × 1.4. The season comes from the date and the user's hemisphere. No location permission is needed.
3. **Pot size.** Small × 0.8, medium × 1.0, large × 1.2.
4. **Light.** Low × 1.2, medium × 1.0, bright indirect × 0.9, direct × 0.85.
5. **Exposed spot.** Balcony or outdoors in summer × 0.8.
6. **Personal history.** Once there are 3 or more intervals between waterings, the median of the last 5 intervals is compared with the expected interval. The ratio is clamped to 0.5–2.0 and blended in at 30%.
7. **"Not needed yet".** When the user checks the soil and logs that the plant does not need water, the window starts at least 2 days (or a quarter of the shortest interval) after the check.

The window runs from `last watering + min days × factors` to `last watering + max days × factors`.

| State | When |
| --- | --- |
| Scheduled | before the window opens |
| Recommended | inside the window |
| Overdue | after the window ends |

Every recommendation carries a list of reasons (`CareReason`), so the app can explain why a task is suggested.

## Mood (first match wins)

| Mood | Rule |
| --- | --- |
| Needs attention | the last inspection in the past 30 days noted a problem, or watering is overdue by more than half the window length (at least 2 days) |
| Thirsty | the watering window is open or overdue |
| Thriving | 4 or more care actions in the last 30 days, spread over at least 14 days |
| Happy | any care action in the last 14 days |
| Neutral | everything else, including new plants |

The water gauge shows 5 steps from "recently watered" to "likely dry", always labelled as an estimate.

## XP

Server-side (`xp_for_event` in the migration) is the source of truth; PlantyKit mirrors it for display.

| Action | XP |
| --- | --- |
| Add a plant (first 30 plants ever) | 20 |
| Water | 10, or 0 if sooner than 60% of the species' shortest interval since the last watering |
| Fertilize, repot | 15 |
| Prune | 10 |
| Inspect, note, "not needed yet" | 5 |

A deleted (corrected) event gives its XP back. Plant levels start at 0, 50, 150, 350 and 700 XP. Garden level L starts at round(100 × (L − 1)^1.5) XP.
