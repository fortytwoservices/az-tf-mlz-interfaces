# Default example

A public IP address with all three interfaces from this module: diagnostic settings (all log category
groups and all metrics) sent to a Log Analytics workspace, a Reader role assignment for the identity that
runs the example, and a `CanNotDelete` lock. The second plan must be empty, and the destroy removes the
lock first.
