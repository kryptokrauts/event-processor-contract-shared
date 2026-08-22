package com.kryptokrauts.shared;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.common._PriceInfo;
import java.math.BigDecimal;
import java.math.RoundingMode;
import java.time.Instant;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import org.apache.commons.lang3.StringUtils;

public class BaseMapper {

  public static final List<String> ACCOUNT_IDENTIFIER =
      List.of(
          "owner", "seller", "creator", "buyer", "from", "to", "burnedBy", "bidder", "receiver");

  public static ObjectMapper objectMapper = new ObjectMapper();

  public static _Account mapAccount(String name) {
    if (StringUtils.isNotBlank(name)) {
      _Account account = BaseCache.getAccountFromCache(name);
      if (account != null) {
        return account;
      } else {
        return _Account.builder().name(name).build();
      }
    }
    return null;
  }

  public static Date mapDate(Long date) {
    if (date != null) {
      return Date.from(Instant.ofEpochMilli(date));
    }
    return null;
  }

  public static _PriceInfo buildPriceInfo(String token, Double price, Double royalty) {
    return buildPriceInfo(token, price, royalty, null, null);
  }

  public static _PriceInfo buildPriceInfo(
      String token, Double price, Double royalty, Double makerMarketFee, Double takerMarketFee) {
    return buildPriceInfo(token, price, null, royalty, makerMarketFee, takerMarketFee);
  }

  public static _PriceInfo buildPriceInfo(
      String token,
      Double price,
      Double priceUSD,
      Double royalty,
      Double makerMarketFee,
      Double takerMarketFee) {
    if (StringUtils.isNotBlank(token) && price != null) {

      Double mmf =
          makerMarketFee != null ? makerMarketFee : BaseCache.getMarketConfigCache().getMaker_fee();
      Double tmf =
          takerMarketFee != null ? takerMarketFee : BaseCache.getMarketConfigCache().getTaker_fee();
      Double marketFee = mmf + tmf;

      String rawPrice = null;
      Integer precision = BaseCache.getTokenPrecision(token);
      if (precision != null) {
        BigDecimal bd = BigDecimal.valueOf(price);
        bd = bd.setScale(precision, RoundingMode.HALF_UP);
        rawPrice = String.format(Locale.US, "%." + precision + "f %s", bd, token);
      }

      Double royaltyPrice = royalty != null ? royalty * price : null;
      Double marketFeePrice = marketFee != null ? marketFee * price : null;

      // an unknown exchange rate is unknown, not zero. Falling back to zero published a confident
      // $0.00 for every price in a token we have no rate for, which is indistinguishable from a
      // genuinely free item. _PriceInfo consumers already render a null usd as "n/a", see
      // BaseTransformer, so null is the value this should produce
      if (priceUSD == null) {
        Double rate = BaseCache.getExchangeRateCache().get(token);
        priceUSD = rate != null ? price * rate : null;
      }
      // roundTo unboxes its argument, so every derived value below has to be guarded rather than
      // computed blindly once priceUSD can be null
      priceUSD = priceUSD != null ? roundTo(priceUSD) : null;

      Double royaltyUSD = priceUSD != null && royalty != null ? roundTo(priceUSD * royalty) : null;
      Double marketFeeUSD =
          priceUSD != null && marketFee != null ? roundTo(priceUSD * marketFee) : null;

      // seller receives info
      Double sellerReceivedPrice =
          roundTo(
              price * (1 - (royalty != null ? royalty : 0) - (marketFee != null ? marketFee : 0)));
      Double sellerReceivedPriceUSD =
          priceUSD != null
              ? roundTo(
                  priceUSD
                      - (royaltyUSD != null ? royaltyUSD : 0)
                      - (marketFeeUSD != null ? marketFeeUSD : 0))
              : null;

      return _PriceInfo.builder()
          .paymentAsset(token)
          .price(price)
          .royalty(royalty)
          .priceUSD(priceUSD)
          .royaltyUSD(royaltyUSD)
          .makerMarketFee(mmf)
          .takerMarketFee(tmf)
          .rawPrice(rawPrice)
          .marketFeeUSD(marketFeeUSD)
          .sellerReceivedPrice(sellerReceivedPrice)
          .sellerReceivedPriceUSD(sellerReceivedPriceUSD)
          .royaltyPrice(royaltyPrice)
          .marketFeePrice(marketFeePrice)
          .build();
    }
    return null;
  }

  public static Double roundTo(Double value, int decimals) {
    return Math.round(value * Math.pow(10, decimals)) / Double.valueOf(Math.pow(10, decimals));
  }

  public static Double roundTo(Double value) {
    return roundTo(value, 2);
  }

  public static Integer toZero(Integer value) {
    return value != null ? value : 0;
  }
}
