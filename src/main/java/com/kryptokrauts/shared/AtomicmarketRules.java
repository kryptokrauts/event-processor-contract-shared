package com.kryptokrauts.shared;

/*-
 * our mirror of the checks atomicmarket makes on chain.
 *
 * Deliberately free of dependencies - no cache, no entities, no CDI - so that every consumer can
 * vendor it. BaseMapper cannot serve this purpose: it reaches into BaseCache for accounts, fees,
 * precision and exchange rates, and soon-market-sse-api excludes both from its copy of these
 * sources precisely because it has none of that machinery.
 *
 * A rule here is a pure function of its arguments. Callers look up the inputs however they
 * already do.
 */
public final class AtomicmarketRules {

  private AtomicmarketRules() {}

  /*-
   * the smallest bid atomicmarket will accept on a running auction.
   *
   * Mirrors, from atomicmarket.cpp:
   *
   *   check((double) bid.amount >= (double) current_bid.amount * (1.0 + minimum_bid_increase))
   *
   * which compares raw integer units as doubles. Two details are what make this correct rather
   * than merely close, and both were learned from implementations that got them wrong:
   *
   * - round into raw units, never truncate. bid * 10^precision lands just below the integer often
   *   enough to matter - 1.0049 * 10000 is 10048.999999999998 - and a current bid read one unit
   *   low makes every step after it too low as well. soon-market-api truncated, and was below the
   *   threshold in 5.86% of bids.
   *
   * - add one raw unit. (1 + increase) is almost never exactly representable, so the contract's
   *   own product carries a fractional part; returning the exact quotient leaves a value that
   *   rounds back below it. soon-market-sse-api returned the exact quotient, in decimal space,
   *   and was below the threshold in 45.6% of bids.
   *
   * Covered by BaseMapperTest#nextMinBidIsNeverBelowWhatTheChainAccepts in soon-market-api, which
   * asserts the check above directly over every current bid from 1 to 1000 XPR. The test cannot
   * live beside this file: these sources are copied into nine consumers and most have no test
   * dependencies at all.
   *
   * @param bid the current bid, in the token's own units
   * @param precision the token's precision
   * @param minBidIncrease atomicmarket's minimum_bid_increase, e.g. 0.05
   */
  public static Double nextMinBid(Double bid, int precision, Double minBidIncrease) {
    if (bid == null || minBidIncrease == null) {
      return null;
    }
    double multiplier = Math.pow(10, precision);
    long raw = Math.round(bid * multiplier);
    return (Math.floor(raw * (1.0 + minBidIncrease)) + 1) / multiplier;
  }
}
