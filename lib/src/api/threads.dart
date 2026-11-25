import 'package:collection/collection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/api/feed_source.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/event.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/models.dart';
import 'package:interstellar/src/utils/reddit.dart';
import 'package:interstellar/src/utils/utils.dart';

const Map<FeedSort, String> lemmyFeedSortMap = {
  FeedSort.active: 'Active',
  FeedSort.hot: 'Hot',
  FeedSort.newest: 'New',
  FeedSort.oldest: 'Old',
  FeedSort.top: 'TopAll',
  FeedSort.commented: 'MostComments',
  FeedSort.topDay: 'TopDay',
  FeedSort.topWeek: 'TopWeek',
  FeedSort.topMonth: 'TopMonth',
  FeedSort.topYear: 'TopYear',
  FeedSort.newComments: 'NewComments',
  FeedSort.topHour: 'TopHour',
  FeedSort.topSixHour: 'TopSixHour',
  FeedSort.topTwelveHour: 'TopTwelveHour',
  FeedSort.topThreeMonths: 'TopThreeMonths',
  FeedSort.topSixMonths: 'TopSixMonths',
  FeedSort.topNineMonths: 'TopNineMonths',
  FeedSort.controversial: 'Controversial',
  FeedSort.scaled: 'Scaled',
};

class APIThreads {
  new(this.client);

  final ServerClient client;

  Future<PostListModel> list(
    FeedSource source, {
    String? sourceId,
    String? page,
    FeedSort? sort,
    bool combined = false,
    bool includeBoosts = false,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = switch (source) {
          FeedSource.all => '/${combined ? 'combined' : 'entries'}',
          FeedSource.local => '/${combined ? 'combined' : 'entries'}',
          FeedSource.subscribed =>
            '/${combined ? 'combined' : 'entries'}/subscribed',
          FeedSource.moderated =>
            '/${combined ? 'combined' : 'entries'}/moderated',
          FeedSource.favorited =>
            '/${combined ? 'combined' : 'entries'}/favourited',
          FeedSource.community =>
            '/magazine/${sourceId!}/${combined ? 'combined' : 'entries'}',
          FeedSource.user =>
            '/users/${sourceId!}/${combined ? 'content' : 'entries'}',
          FeedSource.domain => '/domain/${sourceId!}/entries',
          FeedSource.feed => throw Exception(
            'Feeds source not allowed for mbin',
          ),
          FeedSource.topic => throw Exception(
            'Topics source not allowed for mbin',
          ),
          FeedSource.tag => '/tag/${sourceId!}/entries',
        };
        final query = {
          'p': page,
          if (source == FeedSource.tag) 'sortBy': mbinGetSort(sort)?.name,
          if (source != FeedSource.tag) 'sort': mbinGetSort(sort)?.name,
          'time': mbinGetSortTime(sort),
          if (source == FeedSource.local) 'federation': 'local',
          if (combined && includeBoosts) 'includeBoosts': 'true',
        };

        final response = await client.get(path, queryParams: query);

        if (combined && source != FeedSource.tag) {
          return PostListModel.fromMbinCombined(response.bodyJson);
        }
        return PostListModel.fromMbinEntries(response.bodyJson);

      case ServerSoftware.lemmy:
        if (source == FeedSource.user) {
          const path = '/user';
          final query = {
            'person_id': sourceId.toString(),
            'page': page,
            'sort': lemmyFeedSortMap[sort],
          };

          final response = await client.get(path, queryParams: query);

          final json = response.bodyJson;

          json['next_page'] = lemmyCalcNextIntPage(
            json['posts']! as List<dynamic>,
            page,
          );

          return PostListModel.fromLemmy(
            json,
            langCodeIdPairs: await client.languageCodeIdPairs(),
          );
        }

        const path = '/post/list';
        final query = {'page_cursor': page, 'sort': lemmyFeedSortMap[sort]}
          ..addAll(switch (source) {
            FeedSource.all => {'type_': 'All'},
            FeedSource.local => {'type_': 'Local'},
            FeedSource.subscribed => {'type_': 'Subscribed'},
            FeedSource.moderated => {'type_': 'ModeratorView'},
            FeedSource.favorited => {'liked_only': 'true'},
            FeedSource.community => {'community_id': sourceId},
            FeedSource.user => throw UnreachableError(),
            FeedSource.domain => throw Exception(
              'Domain source not allowed for lemmy',
            ),
            FeedSource.feed => throw Exception(
              'Feeds source not allowed for lemmy',
            ),
            FeedSource.topic => throw Exception(
              'Topics source not allowed for lemmy',
            ),
            FeedSource.tag => throw Exception(
              'Tags source not allowed for lemmy',
            ),
          });

        final response = await client.get(path, queryParams: query);

        return PostListModel.fromLemmy(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/post/list';
        final query = {'page': page, 'sort': lemmyFeedSortMap[sort]}
          ..addAll(switch (source) {
            FeedSource.all => {'type_': 'All'},
            FeedSource.local => {'type_': 'Local'},
            FeedSource.subscribed => {'type_': 'Subscribed'},
            FeedSource.moderated => {'type_': 'ModeratorView'},
            FeedSource.favorited => {'liked_only': 'true'},
            FeedSource.community => {'community_id': sourceId},
            FeedSource.user => {'person_id': sourceId.toString()},
            FeedSource.domain => throw Exception(
              'Domain source not allowed for fromPiefed',
            ),
            FeedSource.feed => {'feed_id': sourceId.toString()},
            FeedSource.topic => {'topic_id': sourceId.toString()},
            FeedSource.tag => throw Exception(
              'Tags source not allowed for Piefed',
            ),
          });

        final response = await client.get(path, queryParams: query);

        return PostListModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final sortName = switch (sort) {
          null ||
          FeedSort.hot ||
          FeedSort.active ||
          FeedSort.commented => 'hot',
          FeedSort.newest || FeedSort.oldest => 'new',
          FeedSort.top ||
          FeedSort.topDay ||
          FeedSort.topWeek ||
          FeedSort.topMonth ||
          FeedSort.topYear ||
          FeedSort.topHour ||
          FeedSort.topSixHour ||
          FeedSort.topTwelveHour ||
          FeedSort.topThreeMonths ||
          FeedSort.topSixMonths ||
          FeedSort.topNineMonths => 'top',
          FeedSort.controversial => 'controversial',
          _ => 'hot',
        };
        final topTime = switch (sort) {
          FeedSort.topDay => 'day',
          FeedSort.topWeek => 'week',
          FeedSort.topMonth => 'month',
          FeedSort.topYear => 'year',
          _ => 'all',
        };
        final path = switch (source) {
          FeedSource.all => '/r/all/$sortName',
          // Reddit has no "local" feed; popular is the closest analogue.
          FeedSource.local => '/r/popular/$sortName',
          // The home feed for a logged-in user.
          FeedSource.subscribed => '/best',
          FeedSource.community =>
            '/r/${await _redditCommunityName(sourceId!)}/$sortName',
          FeedSource.user =>
            '/user/${await _redditUserName(sourceId!)}/submitted',
          FeedSource.favorited => '/user/me/saved',
          _ => throw Exception('Feed source not allowed for Reddit: $source'),
        };
        final query = {
          'after': page,
          'limit': '25',
          'raw_json': '1',
          if (sortName == 'top') 't': topTime,
        };

        final response = await client.get(path, queryParams: query);

        return PostListModel.fromReddit(response.bodyJson);
    }
  }

  /// Resolve a cached community id (an int, as stored by
  /// `fetchCachedFeedInput`) back to a subreddit name via `/api/info`.
  /// A non-numeric source id is already a name and is used as-is.
  Future<String> _redditCommunityName(String sourceId) async {
    final id = int.tryParse(sourceId);
    if (id == null) return sourceId;
    final response = await client.get(
      '/api/info',
      queryParams: {'id': redditFullname('t5', id)},
    );
    final children = redditListingChildren(response.bodyJson);
    if (children.isEmpty) throw Exception('Unknown subreddit id $sourceId');
    return children.first['display_name']! as String;
  }

  Future<String> _redditUserName(String sourceId) async {
    final id = int.tryParse(sourceId);
    if (id == null) return sourceId;
    final response = await client.get(
      '/api/info',
      queryParams: {'id': redditFullname('t2', id)},
    );
    final children = redditListingChildren(response.bodyJson);
    if (children.isEmpty) throw Exception('Unknown user id $sourceId');
    return children.first['name']! as String;
  }

  Future<PostModel> get(int postId) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/entry/$postId';

        final response = await client.get(path);

        return PostModel.fromMbinEntry(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/post';
        final query = {'id': postId.toString()};

        final response = await client.get(path, queryParams: query);

        return PostModel.fromLemmy(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/post';
        final query = {'id': postId.toString()};

        final response = await client.get(path, queryParams: query);

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final response = await client.get(
          '/api/info',
          queryParams: {'id': redditFullname('t3', postId)},
        );

        final children = redditListingChildren(response.bodyJson);
        if (children.isEmpty) throw Exception('Post not found: $postId');
        return PostModel.fromReddit(children.first);
    }
  }

  Future<PostModel> vote(
    int postId,
    int choice,
    int newScore, {
    String? emoji,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = choice == 1
            ? '/entry/$postId/favourite'
            : '/entry/$postId/vote/$choice';

        final response = await client.put(path);

        return PostModel.fromMbinEntry(response.bodyJson);

      case ServerSoftware.lemmy:
        final response = await client.post(
          '/post/like',
          body: {'post_id': postId, 'score': newScore},
        );

        return PostModel.fromLemmy(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        final response = await client.post(
          '/post/like',
          body: {'post_id': postId, 'score': newScore, 'emoji': ?emoji},
        );

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        // Reddit's vote endpoint is form-encoded and returns an empty
        // body, so re-fetch the post to get its updated score/vote.
        await client.postForm(
          '/api/vote',
          fields: {
            'id': redditFullname('t3', postId),
            'dir': choice.toString(),
          },
        );

        return get(postId);
    }
  }

  Future<PostModel> boost(int postId) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/entry/$postId/vote/1';

        final response = await client.put(path);

        return PostModel.fromMbinEntry(response.bodyJson);

      case ServerSoftware.lemmy:
        throw Exception('Tried to boost on lemmy');

      case ServerSoftware.piefed:
        throw Exception('Tried to boost on piefed');
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> votePoll(int postId, List<int> choiceIds) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        throw Exception('Tried to vote on a poll on mbin');
      case ServerSoftware.lemmy:
        throw Exception('Tried to vote on a poll on lemmy');
      case ServerSoftware.piefed:
        const path = '/post/poll_vote';
        final response = await client.post(
          path,
          body: {'post_id': postId, 'choice_id': choiceIds},
        );
        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> edit(
    int postId,
    String title,
    bool? isOc,
    String body,
    String? lang,
    bool? isAdult,
  ) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/entry/$postId';

        final response = await client.put(
          path,
          body: {
            'title': title,
            'tags': [],
            'isOc': isOc,
            'body': body,
            'lang': lang,
            'isAdult': isAdult,
          },
        );

        return PostModel.fromMbinEntry(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/post';

        final response = await client.put(
          path,
          body: {
            'post_id': postId,
            'name': title,
            'body': body,
            'nsfw': isAdult,
          },
        );

        return PostModel.fromLemmy(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/post';

        final response = await client.put(
          path,
          body: {
            'post_id': postId,
            'name': title,
            'body': body,
            'nsfw': isAdult,
          },
        );

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<void> delete(int postID) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final response = await client.delete('/entry/$postID');

        return;

      case ServerSoftware.lemmy:
        final response = await client.post(
          '/post/delete',
          body: {'post_id': postID, 'deleted': true},
        );

        return;

      case ServerSoftware.piefed:
        final response = await client.post(
          '/post/delete',
          body: {'post_id': postID, 'deleted': true},
        );

        return;
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> assignFlairs(int postId, List<int> flairIds) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        throw UnsupportedError(
          'Mbin doesnt support assigning flairs to a post',
        );
      case ServerSoftware.lemmy:
        throw UnsupportedError(
          'Lemmy doesnt support assigning flairs to a post',
        );
      case ServerSoftware.piefed:
        const path = '/post/assign_flair';
        final response = await client.post(
          path,
          body: {'post_id': postId, 'flair_id_list': flairIds},
        );

        return PostModel.fromPiefed({
          'post_view': response.bodyJson,
        }, langCodeIdPairs: await client.languageCodeIdPairs());
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> create({
    required int communityId,
    required String title,
    required String lang,
    String? body,
    String? url,
    XFile? image,
    String? alt,
    bool isAdult = false,
    bool isOc = false,
    List<String> tags = const [],
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        assert(
          body?.isNotEmpty != null || url?.isNotEmpty != null || image != null,
          'Post needs either a body an url or an image.',
        );
        tags = tags.where((tag) => tag.isNotEmpty).toList();

        final path = '/magazine/$communityId/entries';

        final response = await client.postMultipart(
          path,
          fields: {
            'title': title,
            'url': ?url,
            for (var i = 0; i < tags.length; ++i) 'tags[$i]': tags[i],
            'isOc': isOc.toString(),
            if (body != null && body.isNotEmpty) 'body': body,
            'lang': lang,
            'isAdult': isAdult.toString(),
            'alt': ?alt,
          },
          files: {'uploadImage': ?image},
        );

        return PostModel.fromMbinEntry(response.bodyJson);

      case ServerSoftware.lemmy:
        if (image != null) {
          const uploadPath = '/pictrs/image';

          final pictrsResponse = await client.postMultipart(
            uploadPath,
            files: {'images[]': image},
          );

          final imageName =
              ((pictrsResponse.bodyJson['files']! as List<Object?>).first!
                      as JsonMap)['file']
                  as String?;

          url = 'https://${client.domain}/pictrs/image/$imageName';
        }

        const path = '/post';
        final response = await client.post(
          path,
          body: {
            'name': title,
            'community_id': communityId,
            'url': url,
            'body': body,
            'nsfw': isAdult,
            'alt_text': alt,
            'language_id': await client.languageIdFromCode(lang),
          },
        );

        return PostModel.fromLemmy(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        if (image != null) {
          const uploadPath = '/upload/image';

          final uploadResponse = await client.postMultipart(
            uploadPath,
            files: {'file': image},
          );

          final imageUrl = uploadResponse.bodyJson['url'] as String?;

          url = imageUrl;
        }

        const path = '/post';
        final response = await client.post(
          path,
          body: {
            'title': title,
            'community_id': communityId,
            'url': ?url,
            'body': ?body,
            'nsfw': isAdult,
            'alt_text': ?alt,
            'language_id': await client.languageIdFromCode(lang),
          },
        );

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> createPoll(
    int communityId, {
    required String title,
    required bool isOc,
    required String body,
    required String lang,
    required bool isAdult,
    required List<String> choices,
    required DateTime? endDate,
    required String mode,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        throw UnimplementedError('Polls are unsupported on mbin');

      case ServerSoftware.lemmy:
        throw UnimplementedError('Polls are unsupported on lemmy');

      case ServerSoftware.piefed:
        const path = '/post';
        final response = await client.post(
          path,
          body: {
            'title': title,
            'community_id': communityId,
            'body': body,
            'nsfw': isAdult,
            'language_id': await client.languageIdFromCode(lang),
            'poll': {
              if (endDate != null)
                'end_poll': endDate.toUtc().toIso8601String(),
              'mode': mode,
              'choices': choices
                  .mapIndexed(
                    (index, choice) => {
                      'id': index,
                      'choice_text': choice,
                      'sort_order': index,
                    },
                  )
                  .toList(),
            },
          },
        );

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<PostModel> createEvent(
    int communityId, {
    required String title,
    required bool isOc,
    required String body,
    required String lang,
    required bool isAdult,
    required DateTime startDate,
    required DateTime endDate,
    required String timezone,
    String? onlineUrl,
    JoinMode joinMode = JoinMode.free,
    bool online = true,
    String feeCurrency = 'USD',
    int fee = 0,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        throw UnimplementedError('Events are unsupported on mbin');

      case ServerSoftware.lemmy:
        throw UnimplementedError('Events are unsupported on lemmy');

      case ServerSoftware.piefed:
        const path = '/post';
        final response = await client.post(
          path,
          body: {
            'title': title,
            'community_id': communityId,
            'body': body,
            'nsfw': isAdult,
            'language_id': await client.languageIdFromCode(lang),
            'event': {
              'start': startDate.toUtc().toIso8601String(),
              'end': endDate.toUtc().toIso8601String(),
              'timezone': timezone,
              'online_link': ?onlineUrl,
              'join_mode': joinMode.name,
              'online': online,
              'event_fee_currency': feeCurrency,
              'event_fee_amount': fee,
            },
          },
        );

        return PostModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<void> report(int postId, String reason) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/entry/$postId/report';

        final response = await client.post(path, body: {'reason': reason});

      case ServerSoftware.lemmy:
        const path = '/post/report';

        final response = await client.post(
          path,
          body: {'post_id': postId, 'reason': reason},
        );

      case ServerSoftware.piefed:
        const path = '/post/report';

        final response = await client.post(
          path,
          body: {'post_id': postId, 'reason': reason},
        );
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<void> markAsRead(List<int> postIds, bool read) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        throw UnsupportedError('Mbin doesnt support marking posts as read');
      case ServerSoftware.lemmy:
        const path = '/post/mark_as_read';

        final response = await client.post(
          path,
          body: {'post_ids': postIds, 'read': read},
        );
      case ServerSoftware.piefed:
        const path = '/post/mark_as_read';

        final response = await client.post(
          path,
          body: {'post_ids': postIds, 'read': read},
        );
      case ServerSoftware.reddit:
        // Reddit has no mark-as-read API; read state is tracked in the
        // local database by AppController instead.
        return;
    }
  }
}
