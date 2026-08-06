<!-- bash/users/CLAUDE.md — manual del dominio. Este directorio NO viaja al
     copiloto (excluido en derivar_canal.sh); su documentación vive aquí y no
     en el CLAUDE.md raíz, que es byte-idéntico en todos los forks. -->

## Users domain — Marketico API ([bash/users/](bash/users/))

The app's **user accounts** (login identities, ~28 — the layer behind
`users`/`persons`), managed through the Marketico backend HTTP API instead of
SQL (spec: [apis/mkt/users.openapi.json](apis/mkt/users.openapi.json); auth
`MARKETICO_JWT_TOKEN` in `.env`; base `MARKETICO_URL`, default
`https://ikigaigm.api.parallelo.ai`). Own helper lib
([bash/users/lib/common.sh](bash/users/lib/common.sh) — `mkt_data` unwraps the
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
| `set_ghl.sh <ref> --location LOC --ghl-user GID [--primary] [--remove]` **[WRITE, SQL]** | Bind the user's GoHighLevel identity: merges `{LOC: GID}` into `users.integrations` (jsonb map location→ghl_user); `--primary` also sets `users.crm_id` (what the calls-domain closer resolution reads). The API doesn't expose these columns, so this one writes via `psql_rw`. `--dry-run` rolls back. |

**Skill — alta de usuario:**
- `crear-usuario` ([.claude/skills/crear-usuario/](.claude/skills/crear-usuario/SKILL.md)):
  `/crear-usuario` — interactive alta of ONE app user: gathers nombre/apellido/
  email/teléfono (+ apodos and GHL location+user id, both optional), pre-checks
  duplicates, then `create_user.sh` → `set_ghl.sh` → nickname-map update.
  Team/role membership (`team_members`) is out of scope (no write script yet).
