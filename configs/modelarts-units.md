# ModelArts Standard inference units

Create one service with three inference units.

| Unit | ModelArts role | Instances | NPU flavor | `GLM52_ROLE` |
|---|---|---:|---|---|
| Entry Prefill | role-0 | 1 | `<8-NPU-A2-FLAVOR>` | `P_ENTRY` |
| Prefill workers | role-1 | 3 | same | `P_WORKER` |
| Decode workers | role-2 | 4 | same | `D_WORKER` |

All units use:

- image: `<SWR_IMAGE_URI>@<IMAGE_DIGEST>`;
- startup: `bash /cache/scripts/start.sh`;
- backend health: `bash /cache/scripts/health.sh`;
- model mount `<SFS_MODEL_DIRECTORY>` → `/model/weight` read-only;
- scripts mount `<SFS_SCRIPT_DIRECTORY>` → `/cache/scripts` read-only;
- config mount `<SFS_CONFIG_DIRECTORY>` → `/cache/config` read-only;
- logs/rendezvous `<SFS_LOG_DIRECTORY>` → `/logs` read-write.

Configure service port `8000/HTTP`, graceful shutdown, a cold-start window of
at least 60 minutes, maximum surge `0%`, and maximum unavailable `100%`.
