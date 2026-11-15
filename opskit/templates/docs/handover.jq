# Handover pack: data object (opskit/lib/docs.sh docs_data) → one self-contained HTML page (inline CSS, prints
# to PDF). Every value from data goes through @html. Wording is for non-technical clients; Activepieces screen
# names ("Automations", "Runs", "Connections", the "Flow is on/off" switch) are those of the pinned 0.92.3 UI.

def esc: tostring | @html;
def short: sub("^@[a-z0-9-]+/piece-"; "");
def known_apps: {
  "gmail": "Gmail", "google-sheets": "Google Sheets", "google-drive": "Google Drive", "slack": "Slack",
  "hubspot": "HubSpot", "facebook-leads": "Facebook Lead Ads", "smtp": "Email (SMTP mail server)",
  "openai-compatible": "AI provider (OpenAI-compatible)", "openai": "OpenAI", "airtable": "Airtable",
  "notion": "Notion", "microsoft-excel-365": "Microsoft Excel 365", "stripe": "Stripe", "shopify": "Shopify",
  "woocommerce": "WooCommerce", "telegram-bot": "Telegram"
};
def no_account: ["webhook", "schedule", "store", "delay", "tables", "data-mapper", "text-helper", "date-helper",
  "math-helper", "approval", "forms", "manual-trigger", "connections", "file-helper", "crypto", "csv", "json",
  "xml", "subflows", "http", "graphql", "sftp-helper"];
def app_name: short as $s | (known_apps[$s] // ($s | split("-") | map((.[:1] | ascii_upcase) + .[1:]) | join(" ")));
def accounts: [.[] | select((short) as $s | no_account | index($s) | not) | app_name] | unique;
def starts(f): (f.trigger_piece // "" | short) as $p
  | if $p == "webhook" then "when data is sent to its web address (for example your website form or shop)"
    elif $p == "schedule" then "on a fixed schedule"
    elif $p == "" then "when it is started"
    else "when something new happens in " + (f.trigger_piece | app_name) end;
def at_time: split(" ") | if length >= 2 and (.[0] | test("^[0-9]+$")) and (.[1] | test("^[0-9]+$"))
  then "every night at \(.[1] | tonumber | tostring | if length == 1 then "0" + . else . end):\(.[0] | tonumber | tostring | if length == 1 then "0" + . else . end) (server time)"
  else "every night" end;
def li: "<li>" + . + "</li>";

. as $d
| ($d.client.domain | "https://" + .) as $url
| ($d.flows | map(.pieces) | add // [] | accounts) as $apps
| [
"<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">",
"<title>Handover pack — \($d.client.name | esc)</title>",
"<style>",
"body{font:15px/1.55 -apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2328;max-width:800px;margin:0 auto;padding:24px 16px;background:#fff}",
"h1{font-size:26px;margin:0 0 4px}h2{font-size:19px;margin:32px 0 8px;padding-top:8px;border-top:1px solid #d0d7de}h3{font-size:16px;margin:18px 0 4px}",
".muted{color:#59636e}.box{background:#f6f8fa;border:1px solid #d0d7de;border-radius:8px;padding:12px 16px;margin:10px 0}",
"table{border-collapse:collapse;width:100%;margin:8px 0}td,th{border:1px solid #d0d7de;padding:6px 8px;text-align:left;vertical-align:top}th{background:#f6f8fa}",
"ol,ul{padding-left:22px}code{background:#f6f8fa;padding:1px 4px;border-radius:4px}",
"@media print{body{max-width:none;padding:0}h2{break-after:avoid}.box,table{break-inside:avoid}}",
"</style></head><body>",
"<h1>Your automation system</h1>",
"<p class=\"muted\">Handover pack for \($d.client.name | esc) · prepared by \($d.business.name | esc) · \($d.generated | esc)</p>",

"<h2>1. Welcome</h2>",
"<p>\(($d.notes.welcome // "This pack explains what runs for you, how to pause it, who owns which account, how we look after the system and where your data lives. Keep it with your company documents.") | esc)</p>",
"<div class=\"box\"><strong>Your builder:</strong> <a href=\"\($url | esc)\">\($url | esc)</a><br>Log in with your own account (email and password). Inside you will find <strong>Automations</strong> (your flows), <strong>Runs</strong> (every time a flow ran, with its result) and <strong>Connections</strong> (the accounts your flows use).</div>",

"<h2>2. Your active flows</h2>",
(if ($d.flows | length) == 0 then "<p>No flow is switched on at the moment.</p>" else
  "<p>These \($d.flows | length) flow(s) are switched on today.</p>",
  ($d.flows[] as $f
   | ($d.notes.flows[$f.name] // ([$d.templates[] | select(.name == $f.name) | .description][0]) // "") as $what
   | "<h3>\($f.name | esc)</h3>",
     "<ul>",
     (if $what != "" then ("<strong>What it does:</strong> " + ($what | esc)) | li else empty end),
     (("<strong>Starts:</strong> " + (starts($f) | esc)) | li),
     (("<strong>Uses your accounts:</strong> " + (($f.pieces | accounts) as $a | if ($a | length) == 0 then "none" else ($a | map(esc) | join(", ")) end)) | li),
     (if $f.last_run then ("<strong>Last ran:</strong> " + ($f.last_run[:10] | esc)) | li else empty end),
     (("<strong>To pause it:</strong> open <strong>Automations</strong>, find “" + ($f.name | esc) + "” and click its switch so the tooltip says “Flow is off”. Nothing is deleted; switch it on again the same way.") | li),
     "</ul>")
end),
"<div class=\"box\"><strong>Pausing is always safe.</strong> A paused flow keeps its settings and its run history. While it is off it does not react to new events: form entries or emails arriving meanwhile are not processed later, so tell us before you pause something important.</div>",

"<h2>3. Your accounts and who owns them</h2>",
"<p>Your flows sign in to these accounts. They belong to you, not to us: you pay for them, you can change their passwords and you keep them if you ever leave.</p>",
(if ($apps | length) == 0 then "<p>Your active flows use no outside accounts.</p>" else
  "<table><thead><tr><th scope=\"col\">Account</th><th scope=\"col\">Owner and where the login is kept</th></tr></thead><tbody>",
  ($apps[] as $a | "<tr><td>\($a | esc)</td><td>\(($d.notes.accounts[$a] // "Not recorded yet — please tell us who owns it.") | esc)</td></tr>"),
  "</tbody></table>"
end),
"<ul>",
("Keep these logins in your company password manager, never in email or chat." | li),
("When someone leaves your company, change the password of every account they knew, then open <strong>Connections</strong> in the builder and reconnect the account (or ask us)." | li),
("Never send us a password. When a flow needs a new account, you connect it yourself in the builder while we are on a call with you." | li),
"</ul>",

"<h2>4. Support</h2>",
"<ul>",
(("<strong>Contact:</strong> " + ($d.business.email | esc) + (if $d.business.phone != "" then " · " + ($d.business.phone | esc) else "" end) + (if $d.business.website != "" then " · " + ($d.business.website | esc) else "" end)) | li),
(if $d.business.hours != "" then ("<strong>Support hours:</strong> " + ($d.business.hours | esc)) | li else empty end),
("<strong>Response time:</strong> within \($d.client.response_hours | esc) hours on business days; faster when everything is down." | li),
("<strong>Included:</strong> \($d.client.included_hours | esc) hour(s) of fixes and small changes per month (unused hours do not roll over)." | li),
("<strong>When you report a problem</strong>, tell us the flow name, roughly when it happened and what you expected; a link from <strong>Runs</strong> is ideal." | li),
"</ul>",

"<h2>5. Backups and where your data lives</h2>",
"<ul>",
(("<strong>Your server:</strong> a private server used only for you" + (if $d.host.location != "" then ", located in " + ($d.host.location | esc) else "" end) + (if $d.host.provider != "" then " (provider: " + ($d.host.provider | esc) + ")" else "" end) + ".") | li),
(("<strong>Backups:</strong> " + ($d.client.backup_schedule | at_time) + ", encrypted, kept \($d.client.local_days | esc) days on your server" + (if $d.client.offsite then " and \($d.client.remote_days | esc) days in a second location" else "" end) + ".") | li),
(("<strong>Restore tests:</strong> once a month we restore your latest backup into a separate test copy and check it works." + (if $d.restore then " Last test: " + ($d.restore.at[:10] | esc) + ", " + (if $d.restore.result == "pass" then "passed" else "did not pass (we are on it)" end) + "." else "" end)) | li),
("<strong>Monitoring:</strong> we check every minute that your system answers, watch for failed flow runs and are alerted when a backup is missing." | li),
"</ul>",

"<h2>6. Data and privacy</h2>",
"<ul>",
("<strong>What is stored on your server:</strong> your flows and their settings; the accounts they use (stored encrypted with a key that exists only on your server and, sealed, in our key safe); the history of runs with the data that passed through them (details are kept 30 days)." | li),
("<strong>Who can see it:</strong> you and the people you give a builder account; we, as your service provider, only to set up, maintain and repair the system, under our data-processing agreement." | li),
("<strong>Who else is involved:</strong> the server provider and the backup storage provider (they store encrypted or technical data only); the alert channels you chose" + (if ($d.client.channels | length) > 0 then " (" + ($d.client.channels | map(esc) | join(", ")) + ")" else "" end) + ", which receive flow names and short error notes, never your customers' data; the apps your flows connect to, under your own contracts with them." | li),
("<strong>If you connected an account with the “Connect” button</strong>, Activepieces' sign-in service keeps that account's sign-in token; accounts connected with “Try another method” stay entirely on your server." | li),
("<strong>When we stop working together</strong> you get a full copy of your data and your flows; we delete your server and our backups within \($d.client.offboard_days | esc) days and confirm it in writing." | li),
"</ul>",

"<h2>7. Moving from Zapier or Make</h2>",
"<p>If some of your automations still run in Zapier or Make, we move them one by one, without a gap:</p>",
"<ol>",
("List each Zap or scenario with what starts it, which apps it uses and how often it runs; mark the ones nobody needs." | li),
("We check every app exists in your builder (or can be reached through its web API) and give you a fixed price per flow." | li),
("You connect your accounts in the builder yourself; we rebuild the flow and test it with sample data." | li),
("Both run side by side for a few days with the new one switched off or writing to a test sheet; we compare the results." | li),
("We switch the new flow on, you switch the Zap off (do not delete it yet), and after a quiet week you cancel what you no longer need." | li),
("Things that work differently: Zapier “Paths” become a <em>Router</em>, “Formatter” steps become small text or code steps, and Zapier’s task history stays in Zapier — keep an export if you need it." | li),
"</ol>",

"<h2>8. If something breaks</h2>",
"<ol>",
("You and we get an alert naming the flow and the failed step; often we have fixed it before you read it." | li),
("If a flow does something wrong (for example sends wrong emails), pause it right away as shown in section 2, then contact us." | li),
("Failed runs can usually be repeated after the fix with the <strong>Retry</strong> button in <strong>Runs</strong>, so nothing is lost." | li),
("If the whole builder does not open, contact us — we restore it from the nightly backup if needed." | li),
"</ol>",
(if $d.business.signature != "" then "<p class=\"muted\">\($d.business.signature | esc)</p>" else empty end),
"</body></html>"
] | join("\n")
