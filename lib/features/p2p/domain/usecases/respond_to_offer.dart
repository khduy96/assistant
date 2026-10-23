import '../../../../core/domain/result.dart';
import '../../../../core/domain/usecase.dart';
import '../repositories/transfer_repository.dart';

/// What [RespondToOffer] takes: the waiting offer, and the user's answer.
typedef RespondToOfferParams = ({String id, bool accept});

/// Accepts or declines an incoming file waiting for an answer.
class RespondToOffer implements UseCase<void, RespondToOfferParams> {
  RespondToOffer(this._transfers);

  final TransferRepository _transfers;

  @override
  Future<Result<void>> call(RespondToOfferParams params) =>
      _transfers.respond(params.id, accept: params.accept);
}
