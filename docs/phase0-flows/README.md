# Phase 0 practice flows

Generators for the two starter flows built in Phase 0 (`python3 lead_capture.py > flow.json` prints an `IMPORT_FLOW` operation).
Apply to an existing flow with `POST /api/v1/flows/<flowId>` (user JWT), then publish with `{"type":"LOCK_AND_PUBLISH","request":{"status":"ENABLED"}}`.
Piece versions are those synced on 0.92.3 (webhook 0.1.42, schedule 0.1.22, http 0.13.0, delay 0.4.0). Reference for Phase 5 templates, not templates themselves.
