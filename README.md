# lml-admin-cli

A command line client for the Live Music Locator admin API, and a worked example
of how to talk to it.

The gem is stdlib only — `net/http` and `json`, no runtime dependencies. If you are
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
gem install lml_admin
```

or in a `Gemfile`:

```ruby
gem "lml_admin"
```

Either way you get the `lml` command. From a checkout instead:

```sh
git clone git@github.com:livemusiclocator/lml-admin-cli.git
ln -s "$PWD/lml-admin-cli/exe/lml" ~/bin/lml
```

## Usage

```
lml check
lml <venues|acts> list   [--q QUERY] [--page N] [--per-page N] [--json]
lml <venues|acts> show   <id> [--json]
lml <venues|acts> create --name NAME [--field value ...] [--json]
lml <venues|acts> update <id> [--field value ...] [--unset FIELD] [--json]
lml gigs list    [--venue-id ID] [--date-from DATE] [--date-to DATE] [--page N] [--json]
lml gigs show    <id> [--json]
lml gigs clipper [--venue-id ID] [--date-from DATE] [--date-to DATE]
lml uploads create --file PATH [--venue-id ID] [--source NAME] [--json]
lml uploads list   [--source NAME] [--page N] [--per-page N] [--json]
lml uploads show   <id> [--json]
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

## Reading a venue's gigs

`lml gigs` is read only. It exists to answer "what have we already got coming up
here", which is the question you have to answer before adding anything.

```sh
# what is coming up at one venue
lml gigs list --venue-id 9f8e7d6c-...

DATE        START  NAME             STATUS     VENUE             ID
2026-09-04  19:00  Songwriting...   confirmed  Golden Vine Hotel  1a2b...
2026-09-18  20:00  Andrew Swift     confirmed  Golden Vine Hotel  3c4d...

page 1 of 1 - 2 in total

# a window, and the full record for each
lml gigs list --venue-id 9f8e7d6c-... --date-to 2026-12-31 --per-page 100 --json
```

A listing is **upcoming by default** — pass `--date-from` to reach back. Dates are
`YYYY-MM-DD` and are checked strictly, because `Date.parse("next tuesdayish")` is
next Tuesday and a silently misread window means silently missing gigs.

Unlike the public API, this shows **drafts and hidden gigs**. That is the point: a
show already sitting here unpublished is one you must not add twice.

There is no `--q`. Filter by venue and date instead — the endpoint has no search
because the search scope would force `visible` and hide exactly what you need.

### Round tripping through clipper

`lml gigs clipper` prints the same text as the admin "Download Gigs" button, so
what comes out goes straight back in:

```sh
lml gigs clipper --venue-id 9f8e7d6c-... > vine.clipper
$EDITOR vine.clipper
lml uploads create --file vine.clipper --venue-id 9f8e7d6c-...
```

Entries keep their `id:` line, so an edited entry updates that gig rather than
creating a second one. `clipper` is not paginated — half a clipper file is not a
clipper file.

## Uploading gigs from a file

`lml uploads create` posts a file of **clipper** content — the same format the
admin upload form takes — and the API creates or updates the gigs it describes.
This is the quickest way to get a venue's week in.

```sh
lml uploads create --file friday.clipper --venue-id 9f8e7d6c-... --source cli
cat friday.clipper | lml uploads create --file - --venue-id 9f8e7d6c-...
```

Entries are separated by a line of `---`, and each entry is `key: value` lines:

```
name: Sniffers Live
date: 2026-09-01
time: 20:00
acts: Amyl and the Sniffers | Cable Ties
price: 30.00 | presale
---
name: Quiet Tuesday
date: 2026-09-02
time: 19:30
weeks: 4
```

Useful keys: `name`, `date`, `time`, `finish_time`, `duration`, `acts` (or `set`,
repeated), `price` (repeated), `genre`, `information`, `series`, `category`,
`tickets`, `url`, `internal_description`, `status`, `weeks` (repeat the entry
weekly), `venue_id`, and `id` to target an existing gig. `status: delete` removes
one. There is fuller prose in the clipper format document.

`--venue-id` sets the venue for entries that do not name their own with a
`venue_id:` line. Times are interpreted in that venue's time zone.

Three things worth knowing:

- **A gig is matched on name, date and venue.** Sending a corrected file again
  updates the same gigs rather than duplicating them, which is what makes a
  failed upload safe to retry.
- **Clipper stops at the first bad entry**, so entries before it have already
  been applied. The command prints which entry failed and the id of the upload
  it kept; fix the file and send it again.
- **A hundred entries per upload.** Processing happens inside the request, and
  entries carrying an `internal_description` each cost a genre-suggestion call,
  so a big file has to be split.

```sh
# what went in, and when
lml uploads list --source cli

# the content and every gig one upload touched
lml uploads show 3c2b1a09-... --json | jq '.gigs[].name'
```

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
| GET | `/v1/admin/uploads` `?source=&page=&per_page=` |
| GET | `/v1/admin/uploads/:id` |
| POST | `/v1/admin/uploads` |

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

`null` clears a field. There is no `DELETE` on venues or acts: a venue owns its
gigs, so deleting one would take its whole history with it. Uploads have no
`PATCH` either — an upload is the record of what was sent, so correcting content
means sending a new one.

A rejected upload comes back as `422` carrying both keys, so the uniform rule
(every non-2xx has an `error`) still holds and you can still see what landed:

```json
{
  "error": "2: 'not a date' is not a valid date",
  "upload": { "id": "...", "status": "Failed", "gigs": [{ "name": "Sniffers Live" }] }
}
```

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
bundle exec rake
```

Tests use webmock, so nothing reaches the real API. Against a local copy of the
Rails app:

```sh
LML_API_URL=http://api.lml.test:3000 LML_ALLOW_INSECURE=1 bundle exec exe/lml check
```

Releasing: bump `LmlAdmin::VERSION` in `lib/lml_admin/version.rb`, then

```sh
bundle exec rake release
```

which tags the version, builds the gem and pushes it to rubygems.org.
