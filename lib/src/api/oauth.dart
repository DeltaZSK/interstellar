import 'dart:convert';

import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/utils/globals.dart';
import 'package:interstellar/src/utils/reddit.dart';
import 'package:oauth2/oauth2.dart' as oauth2;

const oauthName = 'Interstellar';
const oauthContact = 'appstore@jwr.one';
const oauthGrants = ['authorization_code', 'refresh_token'];
const oauthScopes = [
  'read',
  'write',
  'delete',
  'subscribe',
  'block',
  'vote',
  'report',
  'user',
  'moderate',
  'bookmark_list',
];

Future<String> registerOauthApp(String instanceHost) async {
  const path = '/api/client';
  final url = Uri.https(instanceHost, path);

  final response = await appHttpClient.post(
    url,
    headers: {'Content-Type': 'application/json; charset=UTF-8'},
    body: jsonEncode({
      'name': oauthName,
      'contactEmail': oauthContact,
      'public': true,
      'redirectUris': [oauthRedirectUri.toString()],
      'grants': oauthGrants,
      'scopes': oauthScopes,
    }),
  );
  ServerClient.checkResponseSuccess(url, response);

  return response.bodyJson['identifier']! as String;
}

/// Exchange a Reddit authorization code for OAuth credentials.
///
/// Reddit's installed-app flow has no client secret, so the token request
/// authenticates with HTTP Basic auth as `base64("<client_id>:")`.
/// `duration=permanent` was requested at the authorize step, so Reddit
/// returns a refresh token; the resulting [oauth2.Credentials] carry
/// Reddit's token endpoint, so `oauth2.Client` can refresh the hourly
/// access token automatically afterwards.
Future<oauth2.Credentials> exchangeRedditCode({
  required String clientId,
  required String code,
  required Uri redirectUri,
}) async {
  final response = await appHttpClient.post(
    redditTokenEndpoint,
    headers: {
      'Authorization': 'Basic ${base64Encode(utf8.encode('$clientId:'))}',
    },
    body: {
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri.toString(),
    },
  );
  ServerClient.checkResponseSuccess(redditTokenEndpoint, response);

  final json = response.bodyJson;
  final scope = json['scope'] as String?;
  return oauth2.Credentials(
    json['access_token']! as String,
    refreshToken: json['refresh_token'] as String?,
    tokenEndpoint: redditTokenEndpoint,
    scopes: scope == null || scope.isEmpty ? redditScopes : scope.split(' '),
    expiration: DateTime.now().add(
      Duration(seconds: json['expires_in'] as int? ?? 3600),
    ),
  );
}
