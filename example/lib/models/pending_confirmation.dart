class PendingManualConfirmation {
  final int amountInCents;
  final int sequenceNumber;
  final String stan;
  final String cardMasked;
  final String expirationDate;
  final DateTime approvedAt;

  const PendingManualConfirmation({
    required this.amountInCents,
    required this.sequenceNumber,
    required this.stan,
    required this.cardMasked,
    required this.expirationDate,
    required this.approvedAt,
  });
}
