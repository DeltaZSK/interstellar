import 'package:flutter/widgets.dart';

enum ServerSoftware {
  mbin,
  lemmy,
  piefed,
  // Personal-fork addition: Reddit is not federated and has no instances.
  // It is a single fixed host (reddit.com) backed by Reddit's OAuth Data
  // API (oauth.reddit.com). See lib/src/utils/reddit.dart.
  reddit;

  String get apiPathPrefix => switch (this) {
    ServerSoftware.mbin => '/api',
    ServerSoftware.lemmy => '/api/v3',
    ServerSoftware.piefed => '/api/alpha',
    // Reddit paths are used as-is against oauth.reddit.com; see
    // ServerClient._uri, which overrides the host for Reddit.
    ServerSoftware.reddit => '',
  };

  String get title => switch (this) {
    ServerSoftware.mbin => 'Mbin',
    ServerSoftware.lemmy => 'Lemmy',
    ServerSoftware.piefed => 'PieFed',
    ServerSoftware.reddit => 'Reddit',
  };

  Color get color => switch (this) {
    ServerSoftware.mbin => const Color(0xff4f2696),
    ServerSoftware.lemmy => const Color(0xff03a80e),
    ServerSoftware.piefed => const Color(0xff0e6ef9),
    ServerSoftware.reddit => const Color(0xffff4500),
  };

  // Use const ints as bitflags since using enums directly as bitflags is a bit awkward in dart.
  static const int mbinFlag = 1;
  static const int lemmyFlag = 2;
  static const int piefedFlag = 4;
  static const int redditFlag = 8;

  int get bitFlag => switch (this) {
    ServerSoftware.mbin => mbinFlag,
    ServerSoftware.lemmy => lemmyFlag,
    ServerSoftware.piefed => piefedFlag,
    ServerSoftware.reddit => redditFlag,
  };
}
