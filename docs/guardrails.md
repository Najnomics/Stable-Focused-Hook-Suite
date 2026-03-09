# Guardrails

`PegGuardrailsModule` enforces deterministic constraints per regime:

- `maxSwapAmount`
- `maxImpactTicks` (when custom price limits are supplied)
- hard-regime cooldown window

Notes:

- Routers often use global min/max price limits; impact checks apply when users provide custom price limit bounds.
- Cooldown is strict in hard-depeg regime and blocks immediate repeated stress swaps.
