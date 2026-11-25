import 'dart:convert';
import 'dart:math';

import 'package:interstellar/src/utils/utils.dart';

/// Reddit support for this personal fork.
///
/// Reddit is not a fediverse instance: there is exactly one host,
/// `reddit.com`, and all authenticated Data API calls go to
/// `oauth.reddit.com` with a bearer token. Unauthenticated traffic is
/// blocked by Reddit, so a Reddit account always needs OAuth.
///
/// Auth is the Authorization Code flow for an *installed app* (no client
/// secret). The user creates their own app at
/// https://www.reddit.com/prefs/apps (type: installed app) and enters its
/// client ID in the login screen. That client ID is stored in the
/// `Servers.oauthIdentifier` column, reusing the slot Mbin uses for its
/// registered OAuth identifier, so no database migration is needed.
///
/// `duration=permanent` is requested so Reddit returns a refresh token;
/// access tokens expire after one hour.
///
/// Scopes needed for browse / vote / comment:
/// identity, read, vote, submit, save, subscribe, mysubreddits, history,
/// edit. (`submit` covers commenting too; there is no separate comment
/// scope.)
const String redditHost = 'reddit.com';
const String redditApiHost = 'oauth.reddit.com';
const String redditAuthHost = 'www.reddit.com';

const List<String> redditScopes = [
  'identity',
  'read',
  'vote',
  'submit',
  'save',
  'subscribe',
  'mysubreddits',
  'history',
  'edit',
];

Uri get redditAuthorizeEndpoint =>
    Uri.https(redditAuthHost, '/api/v1/authorize');
Uri get redditAuthorizeCompactEndpoint =>
    Uri.https(redditAuthHost, '/api/v1/authorize.compact');
Uri get redditTokenEndpoint =>
    Uri.https(redditAuthHost, '/api/v1/access_token');

/// Reddit's required User-Agent format is
/// `<platform>:<app ID>:<version> (by /u/<username>)`. The username is not
/// known until after login, so the fork uses a unique descriptive agent
/// without the username part; if Reddit ever throttles it, set this to
/// include your own `/u/username`.
String redditUserAgent(String appVersion) =>
    'android:interstellar-reddit-fork:$appVersion';

/// Build the authorization URL for the installed-app code flow.
/// `duration=permanent` is what makes Reddit return a refresh token.
Uri redditAuthorizationUrl({
  required String clientId,
  required Uri redirectUri,
  required String state,
}) {
  return redditAuthorizeCompactEndpoint.replace(
    queryParameters: {
      'client_id': clientId,
      'response_type': 'code',
      'state': state,
      'redirect_uri': redirectUri.toString(),
      'duration': 'permanent',
      'scope': redditScopes.join(' '),
    },
  );
}

String redditRandomState() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}

// ---------------------------------------------------------------------------
// IDs
//
// Reddit IDs are base36 strings (`t3_abc123` for posts, `t1_...` for
// comments, `t5_...` for subreddits, `t2_...` for users). Interstellar's
// models use `int` IDs everywhere, so Reddit IDs are converted with base36
// into a Dart int (64-bit, plenty for Reddit's IDs) and the original
// fullname (`t3_abc123`) is kept in the model's `apId` field whenever the
// API needs it back. When `apId` is missing, the fullname is rebuilt from
// the int with [redditFullname].
// ---------------------------------------------------------------------------

const String _base36Digits = '0123456789abcdefghijklmnopqrstuvwxyz';

int redditBase36ToInt(String base36) {
  var value = 0;
  for (final char in base36.toLowerCase().codeUnits) {
    final digit = _base36Digits.indexOf(String.fromCharCode(char));
    if (digit < 0) throw FormatException('Invalid base36: $base36');
    value = value * 36 + digit;
  }
  return value;
}

String redditIntToBase36(int value) {
  if (value == 0) return '0';
  var result = '';
  var remaining = value;
  while (remaining > 0) {
    result = _base36Digits[remaining % 36] + result;
    remaining ~/= 36;
  }
  return result;
}

/// `t3_abc123` -> `abc123` (the bare ID) and `t3` (the kind prefix).
(String kind, String id) redditSplitFullname(String fullname) {
  final parts = fullname.split('_');
  return (parts.first, parts.sublist(1).join('_'));
}

String redditFullname(String kind, int id) =>
    '${kind}_${redditIntToBase36(id)}';

/// Strip an Interstellar-style `@reddit.com` suffix (and a leading
/// `r/` / `u/`) from a community or user name for use in Reddit paths.
String redditStripInstance(String name) {
  var result = name;
  if (result.contains('@')) result = result.split('@').first;
  if (result.startsWith('r/')) result = result.substring(2);
  if (result.startsWith('u/')) result = result.substring(2);
  return result;
}

/// The bare base36 ID from a fullname, or from a bare ID already.
String redditBareId(String idOrFullname) => idOrFullname.contains('_')
    ? redditSplitFullname(idOrFullname).$2
    : idOrFullname;

/// int ID for a Reddit object, from its fullname or bare base36 ID.
int redditIdToInt(String idOrFullname) =>
    redditBase36ToInt(redditBareId(idOrFullname));

// ---------------------------------------------------------------------------
// Listing helpers
// ---------------------------------------------------------------------------

/// A Reddit listing is `{kind: 'Listing', data: {children: [...], after,
/// before}}`. Each child is `{kind: 't3'|'t1'|..., data: {...}}`.
List<JsonMap> redditListingChildren(JsonMap listingJson) {
  final data = listingJson['data'] as JsonMap?;
  final children = data?['children'] as List<dynamic>? ?? [];
  return children
      .map((child) => (child as JsonMap)['data']! as JsonMap)
      .toList();
}

String? redditListingAfter(JsonMap listingJson) =>
    (listingJson['data'] as JsonMap?)?['after'] as String?;

DateTime redditDateTimeFromEpoch(num seconds) =>
    DateTime.fromMillisecondsSinceEpoch(
      (seconds * 1000).toInt(),
      isUtc: true,
    ).toLocal();

/// Reddit escapes `&` as `&amp;` in preview/media URLs.
String redditUnescapeUrl(String url) => url
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');
