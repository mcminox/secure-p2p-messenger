abstract final class P2pConstants {
  static const multicastHost = '239.255.77.77';
  static const udpPort = 52525;

  static const heartbeatInterval = Duration(seconds: 4);

  static const onlineIfHeardWithin = Duration(seconds: 16);

  static const hideChatIfSilentFor = Duration(minutes: 8);

  static const graceIfNeverSeen = Duration(minutes: 3);

  static const minSyncGap = Duration(seconds: 3);

  static const maxMessagesPerBatch = 40;
}
