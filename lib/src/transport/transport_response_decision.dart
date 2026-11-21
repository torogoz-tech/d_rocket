/// Decision returned after a transport response is observed.
class TransportResponseDecision {
  const TransportResponseDecision.accept()
      : retry = false,
        delay = Duration.zero;

  const TransportResponseDecision.retry({this.delay = Duration.zero})
      : retry = true;

  final bool retry;
  final Duration delay;
}
