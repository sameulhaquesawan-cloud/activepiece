# Sub-processors (Annex 3 of the DPA)

*Template — fill in what you actually use per client and keep it current. Clients must be told before a
sub-processor is added or changed (DPA §5). Check each provider's own DPA and data location before use.*

| Provider | What it does for us | Data it can see | Location for EU clients | Notes |
|---|---|---|---|---|
| Hetzner Online GmbH (Germany) | client server (hosting) | everything processed by the client's automations | Germany (Falkenstein/Nuremberg) or Finland (Helsinki) | EU company; sign Hetzner's DPA in its console |
| DigitalOcean, LLC (US) | client server for US/other clients | as above | only if the client chooses a non-EU region | not used for EU clients by default |
| Backblaze, Inc. (US) | off-server backup storage | encrypted backups only (database and settings are encrypted before upload; the provider cannot read them) | EU Central region (Amsterdam) — choose it when creating the bucket *(verify)* | US company; standard contractual clauses in its DPA *(verify)* |
| Telegram (Telegram FZ-LLC) | alert messages to the provider (and the client, if chosen) | client name, flow name, failing step, error excerpt ≤ 300 characters | outside the EU *(verify)* | alerts may contain small data fragments; offer email/Slack instead if the client prefers |
| Slack (Salesforce) | alert messages, only if the client chooses Slack | as above | per the client's own Slack workspace | client's own account |
| [Email provider, e.g. Brevo (Sendinblue SAS, France)] | alert emails, only if email alerts are used | as above + recipient addresses | EU | |
| UptimeRobot | checks that the provider's monitoring server is up | no client data (only the monitoring server's address) | — | |

Not sub-processors (run by the provider itself, no third party): Uptime Kuma monitoring server
[location], the opskit tools on the provider's own computer.
