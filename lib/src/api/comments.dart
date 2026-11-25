import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:interstellar/src/api/client.dart';
import 'package:interstellar/src/controller/controller.dart';
import 'package:interstellar/src/controller/server.dart';
import 'package:interstellar/src/models/comment.dart';
import 'package:interstellar/src/models/community.dart';
import 'package:interstellar/src/models/post.dart';
import 'package:interstellar/src/utils/models.dart';
import 'package:interstellar/src/utils/reddit.dart';
import 'package:interstellar/src/utils/utils.dart';
import 'package:interstellar/src/widgets/selection_menu.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

enum CommentSort { hot, top, newest, active, oldest }

const Map<CommentSort, String> lemmyCommentSortMap = {
  CommentSort.active: 'Controversial',
  CommentSort.hot: 'Hot',
  CommentSort.newest: 'New',
  CommentSort.oldest: 'Old',
  CommentSort.top: 'Top',
};

SelectionMenu<CommentSort> commentSortSelect(BuildContext context) =>
    SelectionMenu(l(context).sortComments, [
      SelectionMenuItem(
        value: CommentSort.hot,
        title: l(context).sort_hot,
        icon: Symbols.local_fire_department_rounded,
      ),
      SelectionMenuItem(
        value: CommentSort.top,
        title: l(context).sort_top,
        icon: Symbols.trending_up_rounded,
      ),
      SelectionMenuItem(
        value: CommentSort.newest,
        title: l(context).sort_newest,
        icon: Symbols.nest_eco_leaf_rounded,
      ),
      if (context.read<AppController>().serverSoftware != ServerSoftware.piefed)
        SelectionMenuItem(
          value: CommentSort.active,
          title: l(context).sort_active,
          icon: Symbols.rocket_launch_rounded,
        ),
      if (context.read<AppController>().serverSoftware != ServerSoftware.piefed)
        SelectionMenuItem(
          value: CommentSort.oldest,
          title: l(context).sort_oldest,
          icon: Symbols.access_time_rounded,
        ),
    ]);

const Map<PostType, String> _postTypeMbin = {
  PostType.thread: 'entry',
  PostType.microblog: 'posts',
};
const Map<PostType, String> _postTypeMbinComment = {
  PostType.thread: 'comments',
  PostType.microblog: 'post-comments',
};

class APIComments {
  new(this.client);

  final ServerClient client;

  Future<CommentListModel> list(
    PostType postType,
    int postId, {
    String? page,
    CommentSort? sort,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbin[postType]}/$postId/comments';
        final query = {'p': page, 'sortBy': sort?.name};

        final response = await client.get(path, queryParams: query);

        return CommentListModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/comment/list';
        final query = {
          'post_id': postId.toString(),
          'page': page,
          'sort': lemmyCommentSortMap[sort],
          'max_depth': '8',
          'type_': 'All',
        };

        final response = await client.get(path, queryParams: query);

        return CommentListModel.fromLemmyToTree(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/post/replies';
        final query = {
          'post_id': postId.toString(),
          'page': page,
          'sort': lemmyCommentSortMap[sort],
        };

        final response = await client.get(path, queryParams: query);

        return CommentListModel.fromPiefed(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final sortName = switch (sort) {
          null || CommentSort.hot => 'confidence',
          CommentSort.top => 'top',
          CommentSort.newest => 'new',
          CommentSort.oldest => 'old',
          CommentSort.active => 'controversial',
        };
        // Reddit returns a JSON *array* `[postListing, commentListing]`,
        // so this cannot use `bodyJson` (which expects a JSON object).
        final response = await client.get(
          '/comments/${redditFullname('t3', postId)}',
          queryParams: {'sort': sortName, 'raw_json': '1', 'limit': '100'},
        );
        final jsonList = jsonDecode(response.body) as List<dynamic>;
        final postChildren = jsonList.isNotEmpty
            ? redditListingChildren(jsonList[0] as JsonMap)
            : <JsonMap>[];
        final community = postChildren.isEmpty
            ? const CommunityModel(id: 0, name: '', icon: null, apId: null)
            : CommunityModel.fromReddit(postChildren.first);
        return CommentListModel.fromReddit(
          jsonList,
          postId: postId,
          community: community,
        );
    }
  }

  Future<CommentListModel> listFromUser(
    PostType postType,
    int userId, {
    String? page,
    CommentSort? sort,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/users/$userId/${_postTypeMbinComment[postType]}';
        final query = {'p': page, 'sort': sort?.name};

        final response = await client.get(path, queryParams: query);

        return CommentListModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/user';

        var s = lemmyCommentSortMap[sort];
        if (s == 'Top') s = 'TopAll';
        final query = {'person_id': userId.toString(), 'page': page, 'sort': s};

        final response = await client.get(path, queryParams: query);

        final json = response.bodyJson;

        json['next_page'] = lemmyCalcNextIntPage(
          json['comments']! as List<dynamic>,
          page,
        );

        return CommentListModel.fromLemmyToFlat(
          json,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/comment/list';
        final query = {
          'person_id': userId.toString(),
          'page': page,
          'sort': lemmyCommentSortMap[sort],
        };

        final response = await client.get(path, queryParams: query);

        return CommentListModel.fromPiefedToFlat(
          response.bodyJson,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final response = await client.get(
          '/user/${await _redditUserName(userId)}/comments',
          queryParams: {'after': page, 'limit': '25', 'raw_json': '1'},
        );

        return CommentListModel.fromRedditFlat(response.bodyJson);
    }
  }

  Future<String> _redditUserName(int userId) async {
    final response = await client.get(
      '/api/info',
      queryParams: {'id': redditFullname('t2', userId)},
    );
    final children = redditListingChildren(response.bodyJson);
    if (children.isEmpty) throw Exception('Unknown user id $userId');
    return children.first['name']! as String;
  }

  Future<CommentModel> get(PostType postType, int commentId) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbinComment[postType]}/$commentId';

        final response = await client.get(path);

        return CommentModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/comment/list';
        final query = {'parent_id': commentId.toString(), 'type_': 'All'};

        final response = await client.get(path, queryParams: query);

        return CommentModel.fromLemmy(
          (response.bodyJson['comments']! as List<dynamic>).firstWhere(
            (item) => item['comment']['id'] == commentId,
          ),
          possibleChildrenJson: response.bodyJson['comments']! as List<dynamic>,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/post/replies';
        final query = {'parent_id': commentId.toString()};

        final response = await client.get(path, queryParams: query);

        return CommentModel.fromPiefed(
          (response.bodyJson['comments']! as List<dynamic>).firstWhere(
            (item) => item['comment']['id'] == commentId,
          ),
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final response = await client.get(
          '/api/info',
          queryParams: {'id': redditFullname('t1', commentId)},
        );

        final children = redditListingChildren(response.bodyJson);
        if (children.isEmpty) throw Exception('Comment not found: $commentId');
        final data = children.first;
        final linkId = data['link_id'] as String?;
        return CommentModel.fromReddit(
          data,
          postId: linkId == null ? 0 : redditIdToInt(linkId),
          community: CommunityModel.fromReddit(data),
        );
    }
  }

  Future<CommentModel> vote(
    PostType postType,
    int commentId,
    int choice,
    int newScore, {
    String? emoji,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = choice == 1
            ? '/${_postTypeMbinComment[postType]}/$commentId/favourite'
            : '/${_postTypeMbinComment[postType]}/$commentId/vote/$choice';

        final response = await client.put(path);

        return CommentModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/comment/like';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'score': newScore},
        );

        return CommentModel.fromLemmy(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/comment/like';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'score': newScore, 'emoji': ?emoji},
        );

        return CommentModel.fromPiefed(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        await client.postForm(
          '/api/vote',
          fields: {
            'id': redditFullname('t1', commentId),
            'dir': choice.toString(),
          },
        );

        return get(postType, commentId);
    }
  }

  Future<CommentModel> boost(PostType postType, int commentId) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbinComment[postType]}/$commentId/vote/1';

        final response = await client.put(path);

        return CommentModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        throw Exception('Tried to boost on lemmy');

      case ServerSoftware.piefed:
        throw Exception('Tried to boost on piefed');
      case ServerSoftware.reddit:
        throw UnsupportedError('Not supported on Reddit');
    }
  }

  Future<CommentModel> create(
    PostType postType,
    int postId,
    String body, {
    required String lang,
    int? parentCommentId,
    XFile? image,
    String? alt,
    bool isAdult = false,
  }) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        if (image == null) {
          final path =
              '/${_postTypeMbin[postType]}/$postId/comments${parentCommentId != null ? '/$parentCommentId/reply' : ''}';

          final response = await client.post(
            path,
            body: {'body': body, 'lang': lang},
          );

          return CommentModel.fromMbin(response.bodyJson);
        } else {
          final path =
              '/${_postTypeMbin[postType]}/$postId/comments${parentCommentId != null ? '/$parentCommentId/reply' : ''}/image';

          final response = await client.postMultipart(
            path,
            fields: {
              'body': body,
              'lang': lang,
              'isAdult': isAdult.toString(),
              'alt': alt ?? '',
            },
            files: {'uploadImage': image},
          );

          return CommentModel.fromMbin(response.bodyJson);
        }

      case ServerSoftware.lemmy:
        const path = '/comment';

        final response = await client.post(
          path,
          body: {
            'content': body,
            'post_id': postId,
            'parent_id': parentCommentId,
            'language_id': await client.languageIdFromCode(lang),
          },
        );

        return CommentModel.fromLemmy(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/comment';

        final response = await client.post(
          path,
          body: {
            'body': body,
            'post_id': postId,
            'parent_id': ?parentCommentId,
            'language_id': await client.languageIdFromCode(lang),
          },
        );

        return CommentModel.fromPiefed(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        if (image != null) {
          throw UnsupportedError('Image comments are not supported on Reddit');
        }
        // Reddit returns the new comment inside a `json.data.things`
        // wrapper, not as a bare comment object.
        final response = await client.postForm(
          '/api/comment',
          fields: {
            'thing_id': parentCommentId != null
                ? redditFullname('t1', parentCommentId)
                : redditFullname('t3', postId),
            'text': body,
          },
        );
        final data = _redditNewCommentData(response.bodyJson);
        final linkId = data['link_id'] as String?;
        return CommentModel.fromReddit(
          data,
          postId: linkId == null ? postId : redditIdToInt(linkId),
          community: CommunityModel.fromReddit(data),
        );
    }
  }

  /// Unwrap Reddit's `/api/comment` / `/api/editusertext` response:
  /// `{json: {data: {things: [{data: <comment>}]}}}`.
  JsonMap _redditNewCommentData(JsonMap json) {
    final things =
        (((json['json'] as JsonMap?)?['data'] as JsonMap?)?['things']
                as List<dynamic>?)
            ?.firstOrNull;
    if (things == null) throw Exception('Reddit did not return the comment');
    return (things as JsonMap)['data']! as JsonMap;
  }

  Future<CommentModel> edit(
    PostType postType,
    int commentId,
    String body,
  ) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbinComment[postType]}/$commentId';

        final response = await client.put(path, body: {'body': body});

        return CommentModel.fromMbin(response.bodyJson);

      case ServerSoftware.lemmy:
        const path = '/comment';

        final response = await client.put(
          path,
          body: {'comment_id': commentId, 'content': body},
        );

        return CommentModel.fromLemmy(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.piefed:
        const path = '/comment';

        final response = await client.put(
          path,
          body: {'comment_id': commentId, 'body': body},
        );

        return CommentModel.fromPiefed(
          response.bodyJson['comment_view']! as JsonMap,
          langCodeIdPairs: await client.languageCodeIdPairs(),
        );

      case ServerSoftware.reddit:
        final response = await client.postForm(
          '/api/editusertext',
          fields: {'thing_id': redditFullname('t1', commentId), 'text': body},
        );
        final data = _redditNewCommentData(response.bodyJson);
        final linkId = data['link_id'] as String?;
        return CommentModel.fromReddit(
          data,
          postId: linkId == null ? 0 : redditIdToInt(linkId),
          community: CommunityModel.fromReddit(data),
        );
    }
  }

  Future<void> delete(PostType postType, int commentId) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbinComment[postType]}/$commentId';

        final response = await client.delete(path);

      case ServerSoftware.lemmy:
        const path = '/comment/delete';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'deleted': true},
        );

      case ServerSoftware.piefed:
        const path = '/comment/delete';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'deleted': true},
        );

      case ServerSoftware.reddit:
        await client.postForm(
          '/api/del',
          fields: {'id': redditFullname('t1', commentId)},
        );
    }
  }

  Future<void> report(PostType postType, int commentId, String reason) async {
    switch (client.software) {
      case ServerSoftware.mbin:
        final path = '/${_postTypeMbinComment[postType]}/$commentId/report';

        final response = await client.post(path, body: {'reason': reason});

      case ServerSoftware.lemmy:
        const path = '/comment/report';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'reason': reason},
        );

      case ServerSoftware.piefed:
        const path = '/comment/report';

        final response = await client.post(
          path,
          body: {'comment_id': commentId, 'reason': reason},
        );

      case ServerSoftware.reddit:
        await client.postForm(
          '/api/report',
          fields: {
            'thing_id': redditFullname('t1', commentId),
            'reason': reason,
          },
        );
    }
  }
}
