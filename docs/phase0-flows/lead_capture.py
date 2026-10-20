import json

NOW = "2026-10-20T00:00:00.000Z"


def code_step(name, display, code, inputs, next_action=None, retry=False):
    step = {
        "name": name, "displayName": display, "type": "CODE", "valid": True, "lastUpdatedDate": NOW,
        "settings": {
            "sourceCode": {"code": code, "packageJson": "{}"},
            "input": inputs,
            "errorHandlingOptions": {"continueOnFailure": {"value": False}, "retryOnFailure": {"value": retry}},
        },
    }
    if next_action:
        step["nextAction"] = next_action
    return step


normalize = code_step(
    "step_1", "Normalize lead",
    "export const code = async (inputs) => {\n"
    "  const b = inputs.body || {};\n"
    "  const email = String(b.email || '').trim().toLowerCase();\n"
    "  return { name: String(b.name || '').trim(), email, valid: /^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$/.test(email) };\n"
    "};",
    {"body": "{{trigger['body']}}"},
)

notify = {
    "name": "step_3", "displayName": "Send lead (HTTP stand-in for sheet/email)", "type": "PIECE", "valid": True,
    "lastUpdatedDate": NOW,
    "settings": {
        "pieceName": "@activepieces/piece-http", "pieceVersion": "0.13.0", "actionName": "send_request",
        "propertySettings": {},
        "input": {
            "method": "POST", "url": "https://postman-echo.com/post",
            "headers": {}, "queryParams": {}, "body_type": "json",
            "body": {"data": {"lead": "{{step_1}}", "source": "opskit-phase0"}},
            "authType": "NONE", "authFields": {}, "failureMode": "all", "timeout": 30,
            "response_is_binary": False, "use_proxy": False, "followRedirects": True,
        },
        "errorHandlingOptions": {"continueOnFailure": {"value": False}, "retryOnFailure": {"value": True}},
    },
}

reject = code_step(
    "step_4", "Reject invalid lead",
    "export const code = async (inputs) => {\n  throw new Error('Invalid email: ' + inputs.email);\n};",
    {"email": "{{step_1['email']}}"},
)

router = {
    "name": "step_2", "displayName": "Valid email?", "type": "ROUTER", "valid": True, "lastUpdatedDate": NOW,
    "settings": {
        "executionType": "EXECUTE_FIRST_MATCH",
        "branches": [
            {"branchName": "Valid", "branchType": "CONDITION",
             "conditions": [[{"firstValue": "{{step_1['valid']}}", "operator": "BOOLEAN_IS_TRUE"}]]},
            {"branchName": "Otherwise", "branchType": "FALLBACK"},
        ],
    },
    "children": [notify, reject],
}
normalize["nextAction"] = router

trigger = {
    "name": "trigger", "displayName": "Lead form webhook", "type": "PIECE_TRIGGER", "valid": True,
    "lastUpdatedDate": NOW,
    "settings": {
        "pieceName": "@activepieces/piece-webhook", "pieceVersion": "0.1.42", "triggerName": "catch_webhook",
        "propertySettings": {}, "input": {"authType": "none", "authFields": {}},
    },
    "nextAction": normalize,
}

print(json.dumps({"type": "IMPORT_FLOW", "request": {
    "displayName": "Phase 0 - Lead capture (practice)", "trigger": trigger, "schemaVersion": None, "notes": None}}))
