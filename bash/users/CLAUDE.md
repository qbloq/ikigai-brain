<!-- bash/users/CLAUDE.md — manual del dominio. Desde 2026-08-21 el
     directorio SÍ viaja a los copilotos, cercado por rol (docs/roles/acceso.json
     → bash/lib/acceso.sh: cerebro y `technology`; el resto exit 3). La
     documentación vive aquí y no en el CLAUDE.md raíz, que es byte-idéntico en
     todos los forks. `apis/` no viaja: el contrato se cita, no se enlaza. -->

## Users domain — Marketico API ([bash/users/](./))

The app's **user accounts** (login identities, ~28 — the layer behind
`users`/`persons`), managed through the Marketico backend HTTP API instead of
SQL (spec: `apis/mkt/users.openapi.json`, artefacto de operador; auth
`MARKETICO_JWT_TOKEN` in `.env`; base `MARKETICO_URL`, default
`https://ikigaigm.api.parallelo.ai`). Own helper lib
([bash/users/lib/common.sh](lib/common.sh) — `mkt_data` unwraps the
`{success,data}` envelope, `resolve_user` accepts id-prefix/name/email and
errors on ambiguity), independent of the Postgres lib. Same policy mirror:
reads by default, WRITE scripts print payload + before/after and support
`--dry-run` (nothing sent). All accept `--json`.

| Script | Use it to… |
|--------|-----------|
| `users.sh [--q FRAG] [--disabled\|--enabled]` | List app users (id, name, email, phone, disabled, created). |
| `contact_users.sh` | List the users assignable as contact owners (`{id, full_name}`). |
| `gh_users.sh --location ID` | GoHighLevel users of one GHL location (ids in `project_crm_configs.location_id`). Currently 422s for both known locations — upstream GHL call fails server-side. |
| `create_user.sh --name N --email E --password P [--lastname L] [--phone T]` **[WRITE]** | Create a user (POST). Prints payload (password redacted) + the created row. |
| `update_user.sh <id\|prefix\|name> [--name\|--lastname\|--email\|--phone] [--disable\|--enable]` **[WRITE]** | Patch one user's fields or toggle `disabled`. Prints before/after. |
| `add_team_member.sh <ref> --team T --role R [--whatsapp N] [--dry-run] [--json]` **[WRITE, SQL]** | Make an app user a member of a team with a role (one `team_members` row) — what turns an account into an **assignee** (`tasks.assignee[]` holds `team_members.id`, not `users.id`) and what the role layers / `acceso.sh` / WhatsApp onboarding key on. Team and role resolve by exact name (roles are duplicated per team, so the pair decides); refuses a second row for the same user×team. `psql_rw`, one txn, before/after, `--dry-run` rolls back. Born 2026-08-21 (alta de Tatiana Echeverry). |
| `set_ghl.sh <ref> --location LOC --ghl-user GID [--primary] [--remove]` **[WRITE, SQL]** | Bind the user's GoHighLevel identity: merges `{LOC: GID}` into `users.integrations` (jsonb map location→ghl_user); `--primary` also sets `users.crm_id` (what the calls-domain closer resolution reads). The API doesn't expose these columns, so this one writes via `psql_rw`. `--dry-run` rolls back. |

**Skill — alta de usuario:**
- `crear-usuario` ([.claude/skills/crear-usuario/](.claude/skills/crear-usuario/SKILL.md)):
  `/crear-usuario` — interactive alta of ONE app user: gathers nombre/apellido/
  email/teléfono (+ apodos and GHL location+user id, both optional), pre-checks
  duplicates, then `create_user.sh` → `set_ghl.sh` → nickname-map update.
  Team/role membership (`team_members`) → `add_team_member.sh` (the step after `create_user.sh` when the person must be assignable).
