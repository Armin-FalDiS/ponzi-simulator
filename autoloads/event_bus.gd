extends Node
## Global signal hub. Registered as the `EventBus` autoload.
##
## The simulation never touches the UI and the UI never touches the simulation.
## Everything crosses this boundary as a typed signal carrying a `WeekReport`
## or a `SchemeState` — never a loose Dictionary.

## A fresh run has been set up. Carries the opening position.
signal run_started(state: SchemeState)

## One week of the scheme resolved. The report holds the snapshot, the cash
## movements, and the ledger lines to print.
signal week_advanced(report: WeekReport)

## The run is over — collapsed, busted, or cashed out. `report.outcome` says how.
signal run_ended(report: WeekReport)
