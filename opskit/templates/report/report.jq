# Care report: data object (opskit/lib/report.sh report_collect) → HTML email/page. Inline styles only (mail
# clients drop <style> blocks), prints cleanly to PDF. Totals only. Run with TZ=<client time zone> so times
# show in the client's local time. $mode: "html" or "text".

def esc: tostring | @html;
def day: fromdate | strflocaltime("%-d %b");
def plural(n; one; many): "\(n) " + (if n == 1 then one else many end);
def pct: if . == null then "not measured" else (tostring + " %") end;
def event_text: if .event == "upgraded" then "Updated to version \(.tag)"
  elif .event == "upgrade_failed" then "Update to version \(.tag) tried and stopped"
  else "Returned to version \(.tag) automatically" end;

. as $r
| ($r.uptime.measured == true) as $measured
| ($r.backups.history) as $bhist
| {
  headline: [
    {k: "Availability", v: (if $measured then ($r.uptime.uptime | pct) else "not measured" end)},
    {k: "Flow runs", v: "\($r.runs.total)"},
    {k: "Failed runs", v: "\($r.runs.failed)"},
    {k: "Nightly backups", v: (if $bhist | not then "no record" elif $r.backups.nights == 0 then "none due yet"
      else "\($r.backups.complete) of \($r.backups.nights)" end)},
    {k: "Incidents", v: "\($r.incidents | length)"},
    {k: "Support hours", v: "\($r.hours.used) of \($r.hours.included)"}
  ],
  sections: [
    {title: "Your flows", lines: (
      if ($r.runs.flows | length) == 0 then ["No flow ran this month."] else
        ["\(plural($r.runs.total; "run"; "runs")) in total: \($r.runs.succeeded) succeeded, \($r.runs.failed) failed" + (if $r.runs.other > 0 then ", \($r.runs.other) cancelled, paused or still running" else "" end) + "."]
        + (if $r.runs.failed > 0 then ["Failed runs are usually caused by unexpected data (for example an invalid email address in a form). Each one alerted us; nothing failed silently."] else [] end)
      end), table: ($r.runs.flows | map([.name, .total, .succeeded, .failed]))},
    {title: "Availability", lines: (
      if $measured | not then ["Availability was not measured this month."]
      else ["Your system answered \($r.uptime.uptime | pct) of the time (checked every minute)."]
        + (if ($r.uptime.down_periods | length) == 0 then ["No interruptions."]
           else ["Interruptions:"] + ($r.uptime.down_periods | map("• \(.start | day): \(plural(.minutes; "minute"; "minutes"))")) end)
        + ["Planned update windows are not counted."]
      end)},
    {title: "Backups", lines: (
      (if $bhist | not then ["No backup record exists for this month yet (recording started later)."]
       elif $r.backups.nights == 0 then ["Nightly backups start the night after your system went live; none was due yet this month."]
       elif ($r.backups.missing | length) == 0 then ["A complete, encrypted backup was made every night (\($r.backups.nights) of \($r.backups.nights)), each copied to a second location."]
       else ["\($r.backups.complete) of \($r.backups.nights) nights had a complete backup. Missing: \($r.backups.missing | map(. + "T12:00:00Z" | day) | join(", ")). We were alerted and checked each one."] end)
      + (if $r.restore_test == null then ["No restore test yet."]
         elif $r.restore_test.result == "pass" then ["Latest restore test: \($r.restore_test.at | day) — your backup was restored into a test copy and worked."]
         else ["Latest restore test: \($r.restore_test.at | day) — did not pass; we are working on it."] end))},
    {title: "Updates", lines: (
      if ($r.upgrades | length) == 0 then ["No version update this month."]
      else $r.upgrades | map("• \(.at | day): \(event_text)") end)},
    {title: "Incidents", lines: (
      if ($r.incidents | length) == 0 then ["None."]
      else $r.incidents | map("• \(.at | day): \(.what)") end)},
    {title: "Support hours", lines: (
      ["\($r.hours.used) of \($r.hours.included) included hour(s) used."]
      + ($r.hours.entries | map("• \(.date + "T12:00:00Z" | day): \(.hours) h — \(.note)")))}
  ]
} as $doc
| if $mode == "text" then
    ([ "Care report — \($r.label)", "\($r.client.name), prepared by \($r.business.name)", "",
       ($doc.headline | map("\(.k): \(.v)") | join("\n")), "" ]
     + ($doc.sections | map("\(.title)\n" + (.lines | join("\n"))
         + (if .table and (.table | length) > 0 then "\n" + (.table | map("  \(.[0]): \(.[1]) runs, \(.[2]) succeeded, \(.[3]) failed") | join("\n")) else "" end)))
     + [ "", "Questions? \($r.business.email)", $r.business.signature ]) | join("\n")
  else
    ([ "<!DOCTYPE html><html lang=\"en\"><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width, initial-scale=1\"><title>Care report \($r.label | esc) — \($r.client.name | esc)</title></head>",
       "<body style=\"margin:0;padding:24px 12px;background:#f6f8fa;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2328;font-size:15px;line-height:1.5\">",
       "<div style=\"max-width:640px;margin:0 auto;background:#ffffff;border:1px solid #d0d7de;border-radius:8px;padding:24px\">",
       "<h1 style=\"font-size:22px;margin:0 0 4px\">Care report — \($r.label | esc)</h1>",
       "<p style=\"margin:0 0 16px;color:#59636e\">\($r.client.name | esc) · prepared by \($r.business.name | esc)</p>",
       "<table role=\"presentation\" style=\"width:100%;border-collapse:collapse;margin:0 0 8px\"><tbody><tr>",
       ($doc.headline[:3] | map("<td style=\"width:33%;padding:8px;border:1px solid #d0d7de;text-align:center\"><div style=\"font-size:20px;font-weight:600\">\(.v | esc)</div><div style=\"color:#59636e;font-size:13px\">\(.k | esc)</div></td>") | join("")),
       "</tr><tr>",
       ($doc.headline[3:] | map("<td style=\"width:33%;padding:8px;border:1px solid #d0d7de;text-align:center\"><div style=\"font-size:20px;font-weight:600\">\(.v | esc)</div><div style=\"color:#59636e;font-size:13px\">\(.k | esc)</div></td>") | join("")),
       "</tr></tbody></table>" ]
     + ($doc.sections | map(
         "<h2 style=\"font-size:17px;margin:22px 0 6px\">\(.title | esc)</h2>"
         + (.lines | map("<p style=\"margin:0 0 6px\">\(esc)</p>") | join(""))
         + (if .table and (.table | length) > 0 then
             "<table style=\"width:100%;border-collapse:collapse;margin:6px 0\"><thead><tr>"
             + (["Flow", "Runs", "Succeeded", "Failed"] | map("<th scope=\"col\" style=\"text-align:left;padding:6px;border:1px solid #d0d7de;background:#f6f8fa\">\(.)</th>") | join(""))
             + "</tr></thead><tbody>"
             + (.table | map("<tr>" + (map("<td style=\"padding:6px;border:1px solid #d0d7de\">\(esc)</td>") | join("")) + "</tr>") | join(""))
             + "</tbody></table>"
           else "" end)))
     + [ "<p style=\"margin:24px 0 0;color:#59636e\">Questions about this report? Write to \($r.business.email | esc).<br>\($r.business.signature | esc)</p>",
         "</div></body></html>" ]) | join("\n")
  end
