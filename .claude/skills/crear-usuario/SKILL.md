---
name: crear-usuario
description: Interactively create one Marketico user (app account) gathering the basics from the user — nombre(s), apellido(s), email, teléfono, apodos, GHL location+user id — then creating it via bash/users/create_user.sh (+ set_ghl.sh, + nickname map). Use whenever the user types /crear-usuario, or asks to create/register/add a user or account — e.g. "creemos un usuario para Mateo", "dar de alta a X en la app", "agrega una cuenta para el nuevo closer", even without naming the skill.
---

# Crear un usuario (Marketico)

An interactive alta session: gather the basic info conversationally, validate
against the live data, preview, then create through the WRITE scripts — never
inline SQL beyond what `bash/users/set_ghl.sh` owns. A "user" here is an **app
account** (`ikigaigm.users` + `persons`, fronted by the Marketico API) — not a
`team_members` row (that's out of scope, see §6).

**Interact in Spanish.** Script names and field values stay verbatim.

## 1. Gather the basics

Ask for everything in ONE message (don't drip-feed questions). Whatever the
user already gave in their request, don't re-ask — only ask for what's missing:

- **Nombre(s)** y **Apellido(s)**
- **Email** (será el login)
- **Teléfono** — digits only with country code (e.g. `573001234567`); no `+`,
  spaces or symbols (the table has dirty phone data with invisible RTL chars —
  don't add more)
- **Apodos** (opcional) — how meetings/tasks refer to this person (e.g. "Bala",
  "Jota")
- **GHL Location + User ID** (opcional) — the GoHighLevel identity, as one or
  more `location_id → ghl_user_id` pairs. Known locations live in
  `project_crm_configs.location_id`; a user may have entries in several.
- **Contraseña** — offer the choice: the user provides one, or generate it with
  `openssl rand -base64 12` and show it once so they can pass it on.

## 2. Pre-checks (read-only)

Before creating anything:

```
bash/users/users.sh --q <email>       # exact duplicate?
bash/users/users.sh --q <apellido>    # near-duplicates / homonyms
```

- Email already listed → stop; offer `update_user.sh` instead (maybe they meant
  to re-enable: `--enable`).
- Same name+lastname with another email → show it and ask before continuing
  (remember the David Guerrero homonym precedent).
- Email must look like an email; phone must be digits only. Fix format with the
  user, don't silently rewrite.

## 3. Preview and confirm

Show the exact payload as a dry-run and get an explicit **sí**:

```
bash/users/create_user.sh --name "…" --lastname "…" --email "…" \
  --phone "…" --password "…" --dry-run
```

The script prints the payload with the password redacted. Alongside it,
summarize what ELSE will happen (GHL binding, apodo registration) so the user
confirms the whole plan once.

## 4. Create

Same call without `--dry-run`. The script prints the created row (re-read from
the API). If the API rejects (`marketico: …`), report the message as-is and
stop — don't retry with mutated data without asking.

Then, if GHL was given (one call per location):

```
bash/users/set_ghl.sh <email> --location <LOC> --ghl-user <GID> [--primary] [--dry-run]
```

Use `--primary` when it's the user's only/main location (sets `users.crm_id`,
which the calls-domain closer resolution reads). Dry-run first, confirm the
before/after, then commit.

## 5. Register the apodos

If apodos were given, update the nickname map memory
(`~/.claude/projects/-projects-hermetico/memory/nickname-to-team-member-map.md`):
add one line in the existing list format —

```
- **<Apodo>** → **<Nombre Apellido>** (<rol si se sabe>, <email>).
```

— keeping the file's existing entries and notes intact. This map is what the
meeting pipeline uses to resolve owners, so a missing apodo means misassigned
tasks later.

## 6. Out of scope — redirect, don't improvise

- **Equipo/rol** (`team_members` row: team, role, WhatsApp): no write script
  exists yet. Say so; leave the alta as app-account only and flag it so the
  membership can be created later.
- **Deshabilitar / editar** an existing user → `bash/users/update_user.sh`.
- **Notion, CRM contacts, task assignment**: different domains; name the right
  tool (`bash/notion/`, `bash/tasks/reassign.sh`) and stop there.

## 7. Close the session

Re-render the final state and summarize:

```
bash/users/users.sh --q <email>
```

Report: created row (id prefix, name, email), GHL bindings applied (location →
ghl user, primary or not), apodos registered, and — if generated — the password
shown ONCE with a reminder to change it on first login. If anything was skipped
(no GHL id yet, no apodo), list it as pending.
