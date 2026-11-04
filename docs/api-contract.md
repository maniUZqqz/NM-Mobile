# NM-Mobile ⇄ NM API contract (phase 1, version 1)

Base URL: whatever the user types as "server address", e.g. `http://87.107.160.17:8040`.
All mobile endpoints live under `{base}/api/v1/mobile/` (trailing slash required).
JSON in / JSON out (UTF-8). Times are ISO-8601 with offset (`2026-11-04T10:15:00+03:30`).

## Auth
* `POST pair/` is public (rate limited). It exchanges an NM **staff** username+password for a
  **device token** and never stores the password.
* Every other device call sends `Authorization: Device <token>`.
* The token is revocable from the NM panel («دستگاه‌های موبایل»). A revoked / unknown token => `401`
  with `{"error":{"code":"device_revoked"}}`; the app must wipe the token and go back to the Connect screen.
* A device whose user lost `is_staff` / was deactivated => `403 {"error":{"code":"not_staff"}}`.

## Errors
Always `{"error": {"code": "<snake_case>", "message": "<Persian sentence for the user>"}}`, plus
HTTP status. Throttled => `429` with `Retry-After`. Show `message` to the user as-is.

## Lists
`?limit=` (default 30, max 100) and `?offset=`. Response: `{"count": N, "results": [...]}`.

## Phone numbers
Send numbers as the phone shows them. The server normalises (Persian digits, `+98`, `0098`, leading `0`)
to digits with country code, e.g. `989121234567`, and returns that as `normalized`.
For deep links to messengers use `normalized` (digits only, no `+`).

---
## Pairing and device

### POST pair/
```
{ "username": "...", "password": "...", "device_name": "Pixel of Ali",
  "install_id": "<uuid generated once by the app>", "model": "Pixel 7", "android_version": "14",
  "app_version": "0.1.0" }
```
201:
```
{ "device_token": "nmd_....",
  "device": {"uid": "<uuid>", "name": "...", "created_at": "..."},
  "user": {"id": 1, "username": "faraz", "display_name": "..."},
  "server": {"api_version": 1, "time": "..."},
  "settings": <same as GET me/ "settings"> }
```
Re-pairing with the same `install_id` replaces the old token (the old one stops working).
Errors: 400 `missing_fields`; 401 `bad_credentials`; 403 `not_staff`; 429 `too_many_attempts`.

### GET me/
```
{ "device": {"uid","name","model","android_version","app_version","last_seen_at","sms_enabled":true},
  "user": {"id","username","display_name"},
  "server_time": "...",
  "settings": {
     "sms_enabled": true,                  // global switch (false = SMS queue paused)
     "forward_incoming_sms": false,        // may the app upload incoming SMS?
     "calls_upload_enabled": true,
     "asr_enabled": true,
     "max_sms_per_hour": 120, "max_sms_per_day": 600,
     "claim_batch": 5, "poll_interval_s": 5 },
  "sms": {"sent_last_hour": 3, "remaining_hour": 117, "remaining_day": 597, "queued_total": 2} }
```

### POST heartbeat/
Send about every 60 s while the gateway service runs.
```
{ "battery_percent": 80, "charging": false, "network": "wifi|mobile|none",
  "sims": [{"slot":0,"subscription_id":1,"carrier":"Irancell","label":"SIM 1"}],
  "sms_ready": true, "app_version": "0.1.0" }
```
=> `{"ok": true, "server_time": "...", "settings": {...}, "pending_sms": 2}`

### POST unpair/
=> `{"ok": true}`; the token is revoked.

---
## Monitoring and actions

### GET monitor/summary/
```
{ "generated_at": "...",
  "health": {"status": "ok|degraded|down",
             "checks": [{"name":"database","label":"پایگاه داده","ok":true,"detail":""}, ...]},
  "nodes": [{"id":1,"name":"...","online":true,"enabled":true,"last_seen":"...","gpu":"RTX 3060",
             "services":{"voice":true,"ollama":true},"jobs_done":12}],
  "queue": {"compute":{"queued":0,"running":1}, "jobs":{"queued":0,"processing":2,"waiting_approval":1},
            "celery": {"celery":0,"ai":0,"gpu":0}},     // celery may be null when unknown
  "failures": [{"kind":"job|compute_job","id":"17","type":"video_generation","error":"...","at":"..."}],
  "ai": {"priority":"local_first|metis_first","priority_label":"...",
         "local":{"online":true,"node":"...","last_error":null},
         "metis":{"configured":true,"last_error":null,"circuit_open":false}},
  "disk": {"path":"/","total_gb":40.0,"used_gb":35.0,"free_gb":2.7,"percent_used":93,"low":true},
  "mobile": {"devices_online":1,"sms_queued":0,"sms_sent_today":4,"calls_today":2},
  "actions": [{"action":"compute_job.cancel","label":"لغو کار","target_kind":"compute_job",
               "confirm_text":"این کار لغو شود؟","danger":false}] }
```
(`last_error`, when present, is `{"kind","message","at"}`.) Any value NM cannot determine is `null`
(never a made-up number).

### POST monitor/actions/
```
{ "action": "compute_job.cancel", "target": "<uid or id>", "params": {} }
```
Allowed actions (everything else => 400 `unknown_action`):
`job.cancel` (target = Job id), `compute_job.cancel` (uid), `compute_job.retry` (uid, only FAILED/CANCELLED),
`compute_node.disable` / `compute_node.enable` (id), `ai.reset_circuit` (params.provider optional),
`sms.pause` / `sms.resume` (no target; pauses the whole SMS queue), `sms.cancel` (sms uid, only QUEUED).
=> `{"ok":true,"action":"...","target":"...","message":"<Persian>"}`. Errors: 404 `target_not_found`,
409 `bad_state`. Every call is written to the audit log with user + device. The app MUST show a
confirmation dialog (use `actions[].confirm_text`) before sending.

### GET monitor/actions/?limit=
Audit log: `{"count":N,"results":[{"at","user","device","action","target","ok","message"}]}`

---
## SMS gateway

SMS jobs are queued by NM (panel / other NM apps). The phone claims and sends them with its own SIM,
then reports. Idempotent everywhere.

### POST sms/claim/
```
{ "max": 5, "sim_slot": 0 }          // both optional
```
=>
```
{ "messages": [ {"uid":"<uuid>","to":"09121234567","normalized":"989121234567","body":"...",
                 "kind":"otp|transactional|marketing","sim_slot":null,"attempt":1,
                 "lease_seconds":120} ],
  "paused": false, "limited": null, "retry_after_s": 5,
  "limits": {"remaining_hour": 117, "remaining_day": 597} }
```
(`limited` is `null`, `"hour"` or `"day"`; `sim_slot` is `null`, `0` or `1`.)
Rules the server already enforces (the app does not re-implement them): opted-out numbers are never
handed out; marketing only from human-approved campaigns and only outside quiet hours (21:00–08:00 Tehran);
per-device hourly/daily caps; global pause. The app must persist `uid` locally **before** it calls
the SMS API so a crash/restart never sends the same uid twice.

### POST sms/<uid>/report/
```
{ "state": "sent|delivered|failed", "error_code": "no_service|generic|radio_off|null_pdu|...",
  "error": "free text", "at": "...", "parts": 1 }
```
=> `{"ok":true,"state":"SENT"}`. States only move forward (QUEUED→CLAIMED→SENT→DELIVERED, or FAILED);
repeating a report is a no-op. If a claim lease (120 s) passes with no report the server marks the
message `FAILED` with error `lease_expired` (transactional/otp are re-queued once; marketing never).

### POST sms/incoming/
Only upload when `settings.forward_incoming_sms` is true, or when the text looks like a STOP word.
```
{ "messages": [ {"client_id":"<stable id e.g. sha1(from+received_at+body)>","from":"09121234567",
                 "body":"لغو","received_at":"...","sim_slot":0} ] }
```
=> `{"accepted":1,"duplicates":0,"opt_outs_added":1,"forwarding":false}`.
If forwarding is off server-side only STOP words («لغو», «stop», «لغو عضویت», «unsubscribe», «توقف»…)
are processed (the number joins the global opt-out list); every other message is discarded unstored.

### POST sms/queue/   (staff JWT; panel / other NM apps — the phone does not call this)
`{ "to","body","kind","campaign_ref"?,"idempotency_key"?,"not_before"? }` (+ `Idempotency-Key` header).

---
## Calls

### POST calls/log/
```
{ "calls": [ {"client_id":"<stable id from the call log row>","number":"09121234567",
              "direction":"in|out|missed|rejected","started_at":"...","duration_s":125,
              "contact_name":null,"sim_slot":0} ] }
```
=> `{"results":[{"client_id","uid","created":true,"caller":{"display":"..."|null,"known":true}}]}`
Idempotent per `(device, client_id)`.

### Consent (recording is refused without it)
NM has one rule, shared with its existing «بازاریابی تلفنی» module: **no consent row, no stored recording.**

`GET calls/consent/?number=` => `{"number","normalized","granted":true,"how":"verbal","obtained_at":"...","source":"mobile"}`
(`granted` false => `how`/`obtained_at`/`source` are null; `source` is `mobile` or `prospect`.)

`POST calls/consent/` `{"number","granted":true,"how":"verbal|written|contract","obtained_how":"گفتم ضبط می‌شود و موافقت کرد"}`

`POST calls/consent/revoke/` `{"number"}` (past recordings stay, new ones are refused)

The app asks the marketer once per number («به طرف مقابل گفتید که تماس ضبط می‌شود و موافقت کرد؟»).

### POST calls/<uid>/recording/   (multipart)
Fields: `audio` (file; m4a/aac/mp3/wav/amr/3gp/ogg/opus/flac, ≤ 100 MB), `source` =
`builtin_recorder|app|manual`, `duration_s`. => 201 `{"uid","status":"UPLOADED"}`;
403 `no_consent`; 409 `uploads_disabled`; 413 `too_large`; 415 `bad_audio`.
Processing is asynchronous: poll `GET calls/<uid>/` (status goes UPLOADED→TRANSCRIBING→TRANSCRIBED→ANALYSED,
or FAILED with `error`).

### GET calls/?number=&status=&limit=&offset=   and   GET calls/<uid>/
```
{ "uid","number","normalized","direction","started_at","duration_s","contact_name",
  "caller": {"display": null,"known": true},
  "status": "LOGGED|NO_CONSENT|UPLOADED|TRANSCRIBING|TRANSCRIBED|ANALYSED|FAILED",
  "has_audio": true, "error": "",
  // detail only:
  "transcript": "...", "segments": [{"start":0.0,"end":3.2,"text":"..."}], "asr_engine": "node|local|metis",
  "summary": "...", "sentiment": "POSITIVE|NEUTRAL|NEGATIVE|", "objections": ["..."],
  "commitments": ["..."], "next_steps": ["..."] }
```
### POST calls/<uid>/reprocess/  => 202 `{"ok":true}`
### GET calls/<uid>/audio/  => the audio file (device token or staff JWT).

---
## In-call helpers

### GET products/search/?q=<text>&limit=20
```
{ "count": 1, "results": [ {
   "id": 5, "name": "...", "sku": "...", "brand": "...", "store": {"id":1,"name":"..."},
   "currency": "IRT", "price": 1200000, "compare_at_price": null,
   "stock": {"available": 7, "on_hand": 9, "reserved": 2, "status": "IN_STOCK", "status_label": "موجود"},
   "cost": null,
   "unit_profit": null, "margin_percent": null,
   "floor_price": null,
   "floor_basis": "owner_override|cost_plus|unknown",
   "max_discount_percent": null, "max_discount_amount": null,
   "short_description": "...", "attributes": [{"key":"رنگ","value":"سیاه"}],
   "image_url": null, "variants": [{"name":"L","price":null,"available":3}] } ] }
```
Numbers are plain numbers (IRT, no decimals) or `null`. `null` is ALWAYS shown as «ثبت نشده», never as 0.
`floor_price` = the lowest price that is not a loss (cost + extra costs + the owner's minimum margin),
or the owner's manual floor; `null` when cost is not registered.
Cost / profit / floor are returned only to authenticated staff devices.

### GET callerid/?number=<number>
```
{ "number":"0912...","normalized":"98912...","display":"Ali Rezaei","known":true,
  "matches":[{"source":"customer|prospect|lead|growth_lead|synced_contact|previous_call|previous_sms",
              "name":"...","detail":"...","store":"...","last_contact_at":null}],
  "history":{"calls":3,"sms_out":1,"sms_in":0,"last_call_at":"..."},
  "consent":{"granted":false} }
```
(`display` is `null` when unknown.) Only NM's own data: customers, prospects, website leads,
Growth Engine leads (read-only), past calls/SMS, contacts the user chose to sync.
**No social-network lookups.**

### POST assistant/ask/
`{ "question": "...", "number": "09121234567", "product_ids": [5], "call_uid": "..." }`
(all but `question` optional)
=> `{ "replies":[{"text":"..."}], "notes":"...", "facts_used":{}, "engine":"local|metis" }`
503 `ai_unavailable` (the Persian message says why). The model is told: never reveal cost or profit to
the customer; the floor price is an internal limit.

### POST contacts/sync/   (only if the user switched contact sync on in the app)
`{ "contacts":[{"name":"...","numbers":["0912..."]}], "replace": true }` => `{"count": 42}`
`DELETE contacts/sync/` removes everything this device synced.

---
## Live call registration (added)

### POST calls/live/
Call this as soon as the phone starts ringing (incoming) or dialling (outgoing), BEFORE the system call log has the row.
```
{ "number": "09121234567", "direction": "in|out", "started_at": "...", "client_id": null }
```
=> `{"uid":"<call uid>","created":true,"normalized":"98912...","caller":{"display":null,"known":false}}`
The later `calls/log/` entry for the same call (same number, `started_at` within 5 minutes) UPDATES this row
(sets `client_id`, `duration_s`, final direction) instead of creating a second one. This `uid` is what
lookups reference as `call_uid`.

---
## Messenger profile lookup (owner-approved, tightly scoped)

**Purpose: caller identification.** Who may be looked up: (1) a number from an ACTUAL call of this paired phone
(registered via `calls/live/` or `calls/log/`, incoming or outgoing), or (2) one single manual lookup typed by a
staff user. Never lists: there is no endpoint that accepts several numbers, and the server refuses a lookup that
has no matching call / manual quota. The phone logs into the messengers itself (the OWNER logs in, in the in-app
WebViews); NM never receives a messenger password or cookie. What may be stored is only what the platform shows a
normal user: display name, username, profile photo, bio/about, and "is on the platform yes/no". Results are cached
30 days; the user can press "refresh". Every platform has an on/off switch in the NM panel (default OFF) and a
Persian warning that unofficial access can get the account restricted or banned.

Platforms: `telegram` (done by the SERVER with the owner's linked account, official MTProto — `method:"server"`),
`whatsapp`, `eitaa`, `bale`, `soroush`, `rubika` (done on the PHONE in WebViews — `method:"webview"`).

### GET lookups/config/
```
{ "cache_days": 30,
  "platforms": [ {"key":"telegram","label":"تلگرام","enabled":true,"method":"server","ready":true,
                  "warning":"<Persian ban-risk warning>","left_today":42}, ... ],
  "rules": "<Persian text of the rules, show it on the messengers screen>" }
```
`ready` is false when the platform is enabled but not usable yet (e.g. Telegram account not linked on the server).
Platforms with `enabled:false` must not be looked up and their login screens may still be shown.

### POST lookups/authorize/   (ALWAYS call before a lookup)
```
{ "number":"09121234567", "platform":"whatsapp", "trigger":"call|manual",
  "call_uid":"<uid from calls/live or calls/log>", "refresh": false }
```
200 allowed: `{"allowed":true,"ticket":"<opaque, single use, valid 10 min>","method":"webview|server","normalized":"98912..."}`
200 cached:  `{"allowed":false,"reason":"cached","cached":<profile object>}`  (a result younger than 30 days exists and `refresh` is false)
Refusals (HTTP + error code): 403 `platform_disabled`; 403 `no_matching_call` (trigger=call without a call of this device
for that number in the last 24 h); 403 `not_staff`; 409 `recently_refreshed` (refresh only after 60 minutes);
429 `rate_limited` (per device/hour, per device/day, per platform/day, manual per user/day) with `Retry-After`;
429 `bulk_blocked` (too many DIFFERENT numbers from one device in an hour); 400 `bad_number`.

### POST lookups/    (webview platforms: the phone submits what it read)
```
{ "ticket":"...", "status":"found|not_found|hidden|login_required|error",
  "on_platform": true,                         // true / false / null (unknown)
  "display_name":"...", "username":"...", "bio":"...", "deep_link_id":"...",
  "avatar_b64":"<base64 JPEG/PNG/WebP, <= 300 KB>" , "extra":{},
  "field_sources":{"display_name":"WhatsApp: push name","bio":"WhatsApp: about","avatar":"WhatsApp: profile photo"},
  "error":"" }
```
201 `{"uid","platform","status","looked_up_at", ...profile object...}`. A ticket works once. Submit only what the
platform really returned; leave fields out (not empty strings) when absent. `login_required` is recorded without
counting against the daily quota.

### POST lookups/server/    (telegram: the server does the lookup)
`{ "ticket":"..." }` => 201 profile object, or 503 `platform_not_ready` (account not linked / session expired /
FloodWait — message in Persian).

### Profile object
```
{ "uid","number","normalized","platform","label","method":"webview|server","status","on_platform",
  "display_name","username","bio","deep_link_id","avatar_url":"/api/v1/mobile/lookups/<uid>/avatar/"|null,
  "field_sources":{...},"looked_up_at":"...","age_days":3,"stale":false,"trigger":"call|manual" }
```
### GET lookups/?number=&platform=&limit=      timeline, newest first (history = one row per lookup)
### GET lookups/latest/?number=      newest profile per platform: `{"number","normalized","profiles":[<profile object>]}`
### GET lookups/<uid>/avatar/        image bytes (device token or staff JWT)
`callerid/` additionally returns `"profiles": [<profile object>]` (latest per platform).

---
## Opt-out list for the phone's LOCAL campaigns (optional endpoint, added in phase 1b)

The app's own contact campaigns (local feature of the original app) must never message a number that
opted out. The phone remembers numbers that replied STOP/لغو by itself; to also honour NM's GLOBAL list it
pulls it:

### GET sms/optouts/?since=<iso>&limit=500   (device token)
```
{ "numbers": ["989121234567", "989351111111"], "next_since": "2026-11-04T11:00:00Z", "has_more": false }
```
`numbers` are normalised digits (with country code) of the global opt-out list, oldest first; `next_since`
is the cursor to send as `since` next time (the app stores it). If the server does not have this endpoint
(404/405) the app silently skips it. Poll interval: every 10 minutes.
