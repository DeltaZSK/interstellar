# Reddit support (personal fork)

This fork adds Reddit as a fourth backend to Interstellar, alongside
Mbin, Lemmy, and PieFed. It is **not** upstream Interstellar: Reddit is
not federated, its API is a paid/approved, rate-limited service, and a
shared OAuth client for every Interstellar user would not work. So this
fork is built for one person, with their own Reddit app.

## What works

- Browse: home feed (`/best`), All (`/r/all`), Popular (as "Local"),
  a subreddit, a user's posts, saved posts ("Favorited")
- Post page with the full comment tree, sorting, and pagination
  (Reddit's `after` cursor)
- Vote on posts and comments (up / down / undo)
- Reply to posts and comments, edit and delete your own comments
- Subreddit pages, subscribe / unsubscribe, subreddit search,
  post search, user pages, your own profile (`/api/v1/me`)
- Read posts are tracked in the local database (Reddit has no
  mark-as-read API)

## What does not work

- Posting new threads, image upload, polls, events, microblogs
- Messages, notifications, bookmarks lists, moderation, feeds/topics
  (PieFed-only), domains, community moderation
- Guest mode: Reddit blocks unauthenticated traffic, so a Reddit
  account must be logged in

Those surfaces throw `UnsupportedError('Not supported on Reddit')`
instead of silently doing the wrong thing.

## Setup: your Reddit app

Reddit requires OAuth for every call, and since late 2025 new apps
need manual approval. Free access is 100 queries/minute per OAuth
client ID, non-commercial only.

1. Go to https://www.reddit.com/prefs/apps while logged in to Reddit.
2. Click "create app" / "create another app".
3. Name: anything, e.g. `Interstellar fork`.
4. Type: **installed app** (not web app, not script). Installed apps
   get no client secret, which is what this fork expects.
5. Redirect URI: exactly one of these, matching the device you log
   in from:
   - Android / iOS: `interstellar://auth`
   - Desktop (Linux / Windows): `http://localhost:46837`
   - Web: your site origin + `/auth.html`
   You can add more than one redirect URI to the same app if you log
   in from several platforms.
6. Submit the API access request form if Reddit asks for one, and
   wait for approval. The app will not work until Reddit approves it.
7. Copy the client ID: it is the short string under the app name
   (e.g. `AbC123dEfGhIjK`).

## Login

1. In Interstellar, Add account, tap `reddit.com` in the list.
2. Paste your Reddit app client ID into the "Reddit app client ID"
   field and tap Login.
3. Reddit's authorize page opens. Approve the requested scopes
   (identity, read, vote, submit, save, subscribe, mysubreddits,
   history, edit).
4. You are redirected back into the app. The client ID is stored
   with the `reddit.com` server record; the OAuth access + refresh
   tokens are stored with the account, like Mbin's.

Access tokens expire after one hour; the refresh token obtained with
`duration=permanent` renews them automatically.

## How it is built

- `lib/src/controller/server.dart`: `ServerSoftware.reddit`
  (flag 8, orange `#ff4500`, no API path prefix).
- `lib/src/utils/reddit.dart`: constants, the installed-app authorize
  URL (`duration=permanent`), base36 ID conversion, listing helpers.
- `lib/src/api/client.dart`: Reddit calls go to `oauth.reddit.com`
  instead of the instance host, and `postForm()` sends the
  form-encoded bodies Reddit's write endpoints require.
- `lib/src/api/oauth.dart`: `exchangeRedditCode()` exchanges the
  authorization code with Basic auth `base64("<client_id>:")`.
- Models (`post.dart`, `comment.dart`, `community.dart`, `user.dart`,
  `search.dart`) each have `fromReddit` factories.

### IDs

Reddit IDs are base36 strings (`t3_abc123` posts, `t1_...` comments,
`t5_...` subreddits, `t2_...` users). Interstellar's models use `int`
IDs, so Reddit IDs are base36-decoded into a Dart int and the
original fullname is rebuilt from the int whenever the API needs it
(`redditFullname()`), or kept in the model's `apId` field.

### API surface

- `APIThreads.list/get/vote`, `APIComments.list/listFromUser/get/vote/
  create/edit/delete/report`, `APICommunity.list/get/getByName/subscribe`,
  `APIUsers.getMe/getByName/get/list`, `APISearch.get`.
- Everything else in `lib/src/api/` has a `case ServerSoftware.reddit:
  throw UnsupportedError('Not supported on Reddit')` arm, added
  mechanically (see `~/workspace/tools/add_reddit_cases.py` in the
  author's checkout; not part of the repo).

## Building

Same as upstream: install the Flutter SDK, then

```
dart run build_runner build -d   # only if you change a freezed/json model
flutter run
```

This fork was verified with `flutter analyze` (no issues) and a
`flutter build bundle --target-platform linux-x64`, which compiled
the whole app, including all Reddit code, to a kernel blob. A full
Linux desktop binary was not linked on this machine because the VM's
package set cannot install GTK dev headers (a libzstd version
conflict); that is environmental, and the native runner is untouched
upstream code. It has not been run against the live Reddit API yet:
that needs a Reddit account, an approved installed app, and its
client ID, entered at login as above.
