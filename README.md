# lml-admin-cli

A command line client for the Live Music Locator admin API, and a worked example
of how to talk to it.

The client is stdlib only — `net/http` and `json`, no gems at runtime. If you are
writing your own integration, `lib/lml_admin/client.rb` is about eighty lines and
shows everything the API expects.

```
$ lml venues list --q tote
ID                                    NAME      LOCATION   CAPACITY
9f8e7d6c-5b4a-3928-1716-051423324150  The Tote  melbourne  400

page 1 of 1 - 1 in total
```

## Getting a token

Tokens belong to a single admin and are issued in backstage:

**<https://www.livemusiclocator.com.au/backstage/api_tokens>**

The secret is shown once, on the page that issues it — we only store a digest, so
if you lose it, revoke it and issue another. Revoking takes effect on the next
request.

Give the client the token by environment variable:

```sh
export LML_ADMIN_TOKEN=lml_admin_...
```

or in a file, which is friendlier for a cron job:

```sh
mkdir -p ~/.config/lml
printf 'lml_admin_...' > ~/.config/lml/credentials
chmod 600 ~/.config/lml/credentials
```

There is deliberately **no `--token` flag**. Command line arguments show up in
`ps` output and in your shell history, and a leaked token is one somebody has to
notice and revoke.

Check it works:

```sh
$ lml check
Token accepted by https://api.lml.live.
```

## Install

Ruby 3.0 or newer, nothing else.

```sh
git clone git@github.com:livemusiclocator/lml-admin-cli.git
ln -s "$PWD/lml-admin-cli/bin/lml" ~/bin/lml
```

## Usage

```
lml check
lml <venues|acts> list   [--q QUERY] [--page N] [--per-page N] [--json]
lml <venues|acts> show   <id> [--json]
lml <venues|acts> create --name NAME [--field value ...] [--json]
lml <venues|acts> update <id> [--field value ...] [--unset FIELD] [--json]
```

`lml help` lists every writable field for both resources.

### Examples

```sh
# find a venue
lml venues list --q curtin

# create one - time zone is required, and must be a real IANA zone
lml venues create --name "The Curtin" \
                  --location melbourne \
                  --time-zone Australia/Melbourne \
                  --capacity 200

# change one thing, leave everything else alone
lml venues update 9f8e7d6c-... --capacity 350 --tags "band room,late"

# acts take a pasted social url and keep the handle
lml acts create --name "Cash Savage" --country Australia --genres "blues,country"
lml acts update 3c2b1a09-... --instagram https://www.instagram.com/cashsavage

# clear a field
lml acts update 3c2b1a09-... --unset instagram

# pipe it somewhere
lml venues list --per-page 100 --json | jq -r '.records[] | [.id, .name] | @tsv'
```

Comma separated values become JSON arrays (`--tags`, `--genres`). `--capacity`
becomes a number, `--latitude` and `--longitude` become floats.

### Exit status

| Status | Meaning |
| --- | --- |
| 0 | fine |
| 1 | the API rejected the request (validation, not found) |
| 2 | bad usage, or no token configured — nothing was sent |
| 3 | the token was refused (401 or 403) |

Worth telling apart in a wrapper script: `3` means go and look at your token,
`1` means go and look at your data.

## The API it talks to

Base URL `https://api.lml.live`. Everything below needs
`Authorization: Bearer <token>`.

| Method | Path |
| --- | --- |
| GET | `/v1/admin/venues` `?q=&page=&per_page=` |
| GET | `/v1/admin/venues/:id` |
| POST | `/v1/admin/venues` |
| PATCH | `/v1/admin/venues/:id` |
| GET | `/v1/admin/acts` `?q=&page=&per_page=` |
| GET | `/v1/admin/acts/:id` |
| POST | `/v1/admin/acts` |
| PATCH | `/v1/admin/acts/:id` |

Collections are wrapped, and always paginated — `per_page` defaults to 50 and is
capped at 100:

```json
{
  "venues": [{ "id": "...", "name": "The Tote" }],
  "meta": { "page": 1, "per_page": 50, "total": 1 }
}
```

Single records are wrapped in the singular name, and writes take the same shape:

```json
{ "venue": { "name": "The Curtin", "time_zone": "Australia/Melbourne" } }
```

Only the documented fields are writable. Anything else in the payload is
dropped, including `google_place_id` and `address_components` — those are
resolved from Google and writing them by hand breaks address matching.

Errors are JSON, with per field detail on a 422:

```json
{ "error": "That record is not valid.", "details": { "time_zone": ["invalid time zone"] } }
```

`null` clears a field. There is no `DELETE` on either resource: a venue owns its
gigs, so deleting one would take its whole history with it.

## Notes for writing your own client

Three things this one does that yours should too:

1. **Token in the `Authorization` header, never the query string.** The API
   rejects a token in the query string outright, because query strings end up in
   router logs, proxy logs and referrers.
2. **Refuse to send the token over plain `http`.** This client raises unless the
   base URL is `https://`; `LML_ALLOW_INSECURE=1` overrides it for a local
   development server.
3. **Treat a 401 as "stop and get a new token", not "retry".** Retrying a
   refused token just fills the logs.

## Development

```sh
bundle install
bundle exec rspec
```

Tests use webmock, so nothing reaches the real API. Against a local copy of the
Rails app:

```sh
LML_API_URL=http://api.lml.test:3000 LML_ALLOW_INSECURE=1 bin/lml check
```
