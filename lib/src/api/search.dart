import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/search.dart';
import 'package:interstellar/src/screens/explore/explore_screen.dart';
import 'package:interstellar/src/utils/reddit.dart';
import 'package:interstellar/src/utils/utils.dart';

class APISearch {
  new(this.client);

  final ServerClient client;

  Future<SearchListModel> get({
    String? page,
    String? search,
    ExploreFilter? filter,
    int? communityId,
    int? userId,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        const path = '/search';

        final response = await client.get(
          path,
          queryParams: {
            'p': page,
            'q': search,
            'authorId': userId?.toString(),
            'magazineId': communityId?.toString(),
          },
        );

        return SearchListModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/search';
        final query = {
          'q': search,
          'page': page ?? '1',
          'type_': 'All',
          'listing_type': switch (filter) {
            ExploreFilter.all => 'All',
            ExploreFilter.local => 'Local',
            _ => 'All',
          },
          'community_id': communityId?.toString(),
          'creator_id': userId?.toString(),
        };

        final response = await client.get(path, queryParams: query);

        final json = response.bodyJson;
        String? nextPage;
        if ((json['comments']! as List<dynamic>).isNotEmpty ||
            (json['posts']! as List<dynamic>).isNotEmpty ||
            (json['communities']! as List<dynamic>).isNotEmpty ||
            (json['users']! as List<dynamic>).isNotEmpty) {
          nextPage = (int.parse(page ?? '1') + 1).toString();
        }

        json['next_page'] = nextPage;

        return SearchListModel.fromLemmy(
          json,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/search';
        final query = {
          'q': search,
          'page': page ?? '1',
          // Only use "Posts" type until "All" type is supported in PieFed
          'type_': 'Posts',
          'listing_type': switch (filter) {
            ExploreFilter.all => 'All',
            ExploreFilter.local => 'Local',
            _ => 'All',
          },
          'community_id': communityId?.toString(),
        };

        final response = await client.get(path, queryParams: query);

        final json = response.bodyJson;
        String? nextPage;
        if ((json['comments']! as List<dynamic>).isNotEmpty ||
            (json['posts']! as List<dynamic>).isNotEmpty ||
            (json['communities']! as List<dynamic>).isNotEmpty ||
            (json['users']! as List<dynamic>).isNotEmpty) {
          nextPage = (int.parse(page ?? '1') + 1).toString();
        }

        json['next_page'] = nextPage;

        return SearchListModel.fromPiefed(
          json,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        // Two calls: post search, then subreddit search for the same
        // query. The subreddit call is best-effort.
        final postsResponse = await client.get(
          communityId != null
              ? '/r/${await _redditCommunityName(communityId)}/search'
              : '/search',
          queryParams: {
            'q': search,
            'type': 'link',
            'sort': 'relevance',
            'after': page,
            'limit': '25',
            'raw_json': '1',
            if (communityId != null) 'restrict_sr': 'true',
          },
        );

        JsonMap? communitiesJson;
        if (communityId == null) {
          try {
            final communitiesResponse = await client.get(
              '/subreddits/search',
              queryParams: {'q': search, 'limit': '10', 'raw_json': '1'},
            );
            communitiesJson = communitiesResponse.bodyJson;
          } catch (_) {
            // Subreddit search is a bonus; post results still stand.
          }
        }

        return SearchListModel.fromReddit(
          postsResponse.bodyJson,
          communitiesJson: communitiesJson,
        );
    }
  }

  Future<String> _redditCommunityName(int communityId) async {
    final response = await client.get(
      '/api/info',
      queryParams: {'id': redditFullname('t5', communityId)},
    );
    final children = redditListingChildren(response.bodyJson);
    if (children.isEmpty) throw Exception('Unknown subreddit id $communityId');
    return children.first['display_name']! as String;
  }
}
