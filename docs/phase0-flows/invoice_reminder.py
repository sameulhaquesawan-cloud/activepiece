import json

NOW = "2026-10-20T00:00:00.000Z"


def code_step(name, display, code, inputs):
    return {
        "name": name, "displayName": display, "type": "CODE", "valid": True, "lastUpdatedDate": NOW,
        "settings": {
            "sourceCode": {"code": code, "packageJson": "{}"},
            "input": inputs,
            "errorHandlingOptions": {"continueOnFailure": {"value": False}, "retryOnFailure": {"value": False}},
        },
    }


fetch = code_step(
    "step_1", "Fetch invoices (sample data)",
    "export const code = async () => [\n"
    "  { id: 'INV-1', customer: 'Acme', paid: false, amount: 120 },\n"
    "  { id: 'INV-2', customer: 'Globex', paid: true, amount: 80 },\n"
    "  { id: 'INV-3', customer: 'Initech', paid: false, amount: 45 },\n"
    "];",
    {},
)

reminder = code_step(
    "step_3", "Build reminder text",
    "export const code = async (inputs) => {\n"
    "  const inv = inputs.invoice;\n"
    "  return inv.paid ? { skipped: inv.id } : { to: inv.customer, text: `Reminder: ${inv.id} for ${inv.amount} is unpaid` };\n"
    "};",
    {"invoice": "{{step_2['item']}}"},
)

loop = {
    "name": "step_2", "displayName": "For each invoice", "type": "LOOP_ON_ITEMS", "valid": True,
    "lastUpdatedDate": NOW, "settings": {"items": "{{step_1}}"}, "firstLoopAction": reminder,
}

delay = {
    "name": "step_4", "displayName": "Wait 10 seconds", "type": "PIECE", "valid": True, "lastUpdatedDate": NOW,
    "settings": {
        "pieceName": "@activepieces/piece-delay", "pieceVersion": "0.4.0", "actionName": "delayFor",
        "propertySettings": {}, "input": {"unit": "seconds", "delayFor": 10},
        "errorHandlingOptions": {"continueOnFailure": {"value": False}, "retryOnFailure": {"value": False}},
    },
}

done = code_step("step_5", "Summary", "export const code = async (inputs) => ({ done: true, at: new Date().toISOString() });", {})

fetch["nextAction"] = loop
loop["nextAction"] = delay
delay["nextAction"] = done

trigger = {
    "name": "trigger", "displayName": "Every minute", "type": "PIECE_TRIGGER", "valid": True, "lastUpdatedDate": NOW,
    "settings": {
        "pieceName": "@activepieces/piece-schedule", "pieceVersion": "0.1.22", "triggerName": "every_x_minutes",
        "propertySettings": {}, "input": {"minutes": 1},
    },
    "nextAction": fetch,
}

print(json.dumps({"type": "IMPORT_FLOW", "request": {
    "displayName": "Phase 0 - Invoice reminder (practice)", "trigger": trigger, "schemaVersion": None, "notes": None}}))
