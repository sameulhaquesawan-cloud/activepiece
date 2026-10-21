# Checklist — lead-ad alert (real accounts, once per template version)

Date: ____  Tested by: ____  Stack version: 0.92.3  Meta app mode: ____

- [ ] `opskit flows validate lead-ad-alert` passes
- [ ] Meta app created; redirect URI, webhook (Page / `leadgen`, verify token `activepieces`) saved
      — Meta accepted the callback URL (proves the stack answers the verify request)
- [ ] `META_APP_SECRET` in channels.env, `app_webhooks` in client.yaml, `opskit deploy` done;
      `docker compose -p <id> exec app sh -c 'case "$AP_APP_WEBHOOK_SECRETS" in *facebook-leads*) echo set;; *) echo missing;; esac'`
      prints `set` (never print the value itself)
- [ ] Imported with `opskit flows import`; flow off after import
- [ ] Facebook connection ("Custom OAuth2 App") created; page picked in the trigger
- [ ] HubSpot connection (OAuth2 and private-app token both tried) and Gmail connection picked
- [ ] Published; Lead Ads Testing Tool lead → HubSpot contact + email within a minute
- [ ] Phone-only test form → run FAILED at "Read lead", alert received
- [ ] Development mode was enough for the client's own page: yes / no (app review needed: ____)
- [ ] Results noted in `docs/PROGRESS.md`
