# Known issues

Cubicle Chaos is a work-in-progress Meta Global AI Developer Hackathon prototype.
Levels 1 and 2 are implemented; levels 3–5 are placeholders. The Web build uses
keyboard and mouse controls; mobile touch controls are not implemented.

## Regression baseline — November 2, 2026

A review ran the full regression runner in a fresh project copy using Godot
4.7.2 on macOS. Of 33 suites, 25 passed and eight failed. The runner reported
nine failures because it separately counted an object-leak warning in one of
the failing suites. A fresh Web export completed successfully.

The failing suites were:

| Suite | Reported area |
| --- | --- |
| `context_integration_regression.gd` | Pause/resume, equipment reservations, and interaction priority |
| `dialogue_regression.gd` | Conversation pause/resume and expectations for the earlier water-delivery quest |
| `equipment_regression.gd` | Equipment progress while pausing |
| `menu_regression.gd` | Pause/menu transitions and input behavior |
| `mouse_controls_regression.gd` | Aim cancellation and camera controls following menu transitions |
| `player_actions_regression.gd` | Bathroom activities and animation expectations |
| `prop_handling_regression.gd` | Carrying, placement, nearby actions, and interruption |
| `seated_cup_regression.gd` | Cup placement after resume/support deletion, plus a shutdown object leak |

Some expectations refer to earlier behavior: tests still expect a separate
pause state and Maya's water-delivery quest, while the current game returns
to the level menu and uses level objectives. These failures require checking
the intended behavior and updating tests or fixing the implementation as
appropriate. They have not all been established as independent gameplay bugs.

Run the current checks with:

```sh
bash tools/run_tests.sh
```

The GitHub Actions workflow runs the same suites on Ubuntu. The baseline above
is a local macOS result, not a claim that hosted checks have passed.
