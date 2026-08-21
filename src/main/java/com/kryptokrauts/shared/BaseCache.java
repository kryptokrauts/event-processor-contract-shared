package com.kryptokrauts.shared;

import com.kryptokrauts.shared.dao.common.CollectionAuditEntity;
import com.kryptokrauts.shared.dao.common.ExchangeRateEntity;
import com.kryptokrauts.shared.dao.common.MarketConfigEntity;
import com.kryptokrauts.shared.dao.common.ProfileBaseView;
import com.kryptokrauts.shared.dao.common.SupportedAssetsEntity;
import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.common._BlacklistMetadata;
import com.kryptokrauts.shared.model.common._MarketConfig;
import io.quarkus.runtime.StartupEvent;
import io.quarkus.scheduler.Scheduled;
import jakarta.enterprise.context.control.ActivateRequestContext;
import jakarta.enterprise.event.Observes;
import jakarta.inject.Singleton;
import jakarta.transaction.Transactional;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.function.BinaryOperator;
import java.util.function.Function;
import java.util.stream.Collector;
import java.util.stream.Collectors;
import org.jboss.logging.Logger;

@Singleton
public class BaseCache {

  protected static final Logger logger = Logger.getLogger(BaseCache.class);

  private static Map<String, _Account> profileCache = new HashMap<>();

  private static Map<String, Double> exchangeRateCache;

  private static _MarketConfig marketConfigCache;

  private static Map<String, Boolean> collectionShieldedCache = new HashMap<>();

  private static Map<String, _BlacklistMetadata> collectionBlacklistedCache = new HashMap<>();

  private static Map<String, Integer> supportedAssetsCache = new HashMap<>();

  public static _MarketConfig getMarketConfigCache() {
    return marketConfigCache;
  }

  public static Map<String, Double> getExchangeRateCache() {
    return exchangeRateCache;
  }

  public static Boolean isShielded(String collectionId) {
    return collectionShieldedCache.containsKey(collectionId);
  }

  public static Boolean isBlacklisted(String collectionId) {
    return collectionBlacklistedCache.containsKey(collectionId);
  }

  public static _Account getAccountFromCache(String account) {
    return profileCache.containsKey(account) ? profileCache.get(account) : null;
  }

  public static Integer getTokenPrecision(String token) {
    if (!supportedAssetsCache.containsKey(token)) {
      SupportedAssetsEntity supportedAssets =
          SupportedAssetsEntity.find("token = ?1", token).firstResult();
      supportedAssetsCache.put(token, supportedAssets.getPrecision());
    }
    return supportedAssetsCache.get(token);
  }

  /*-
   * fill every cache once at startup.
   *
   * @Scheduled(every = ...) does not fire at boot, it fires one interval later, so without this
   * every cache is empty for that first interval after each deploy. What that costs depends on the
   * cache, and the two groups below are treated differently for that reason.
   *
   * The market config and the exchange rates are dereferenced without a null check in
   * BaseMapper.buildPriceInfo, and both start as null rather than empty. So until they are filled,
   * every response carrying a price fails with a NullPointerException - for ten minutes in the case
   * of the exchange rates and, with cache.refresh.market_config = P1d, for up to a day in the case
   * of the market config. Those two are required: failing to start is better than starting a
   * service that reports itself healthy and answers every priced request with a 500.
   *
   * The rest degrade instead of failing - a missing profile costs a KYC badge, see
   * kryptokrauts/event-processor-contract#11, a missing shielded list costs an icon - and the
   * scheduled refresh retries within the hour. Those are filled best effort, so a database that is
   * briefly unreachable at boot does not take the service down over a badge.
   *
   * The request context is activated for the same reason the scheduled methods have one - the reads
   * below need a Hibernate session.
   */
  @ActivateRequestContext
  public void populateCachesAtStartup(@Observes StartupEvent event) {
    long start = System.currentTimeMillis();
    logger.info("Populating caches at startup");

    // required, see above: their absence is a NullPointerException and not a degraded value
    this.refreshMarketConfigCache();
    this.refreshExchangeRateCache();

    // best effort: a miss degrades and the scheduled refresh will retry
    this.fillSafely("profiles", this::refreshProfileCache);
    this.fillSafely("shielded collections", this::refreshShieldedCollectionsCache);
    this.fillSafely("blacklisted collections", this::refreshBlacklistedCollectionsCache);
    this.fillSafely("supported assets", this::refreshSupportedAssetsCache);

    logger.infof("Populating caches at startup took %s ms", System.currentTimeMillis() - start);
  }

  protected void fillSafely(String name, Runnable refresh) {
    try {
      refresh.run();
    } catch (Exception e) {
      logger.errorf(
          e, "Could not populate the %s cache at startup, the scheduled refresh will retry", name);
    }
  }

  @Scheduled(every = "{cache.refresh.exchange_rates}")
  public void refreshExchangeRate() {
    this.refreshExchangeRateCache();
  }

  @Scheduled(every = "{cache.refresh.profiles}")
  public void refreshProfiles() {
    this.refreshProfileCache();
  }

  @Scheduled(every = "{cache.refresh.shielded_collections}")
  public void refreshShieldedCollections() {
    this.refreshShieldedCollectionsCache();
  }

  @Scheduled(every = "{cache.refresh.blacklisted_collections}")
  public void refreshBlacklistedCollections() {
    this.refreshBlacklistedCollectionsCache();
  }

  @Scheduled(every = "{cache.refresh.market_config}")
  public void refreshMarketConfig() {
    this.refreshMarketConfigCache();
  }

  @Scheduled(every = "{cache.refresh.supported_assets}")
  public void refreshSupportedAssets() {
    this.refreshSupportedAssetsCache();
  }

  @Transactional
  protected void refreshExchangeRateCache() {
    long start = System.currentTimeMillis();

    List<ExchangeRateEntity> exchangeRateList = ExchangeRateEntity.listAll();
    Map<String, Double> tempCache =
        exchangeRateList.stream()
            .collect(
                keepFirst(
                    "exchange rates",
                    ExchangeRateEntity::getTokenSymbol,
                    ExchangeRateEntity::getUsd));
    exchangeRateCache = tempCache;

    logger.infof(
        "Refresh of exchange rates cache took %s ms", (System.currentTimeMillis() - start));
  }

  @Transactional
  protected void refreshMarketConfigCache() {
    long start = System.currentTimeMillis();

    marketConfigCache = MarketConfigEntity.findLatest().toModel();

    logger.infof("Refresh of market config cache took %s ms", (System.currentTimeMillis() - start));
  }

  @Transactional
  protected void refreshProfileCache() {
    long start = System.currentTimeMillis();

    List<ProfileBaseView> profileList = ProfileBaseView.listAll();
    Map<String, _Account> tempCache =
        profileList.stream()
            .collect(
                Collectors.toMap(
                    ProfileBaseView::getAccount,
                    ProfileBaseView::toModel,
                    // an account with several rows means the source view returns more than one,
                    // which is a data problem to fix at the source - see #11. Until then the
                    // conflict is resolved towards not verified: one of those rows can be a
                    // revocation, and a kyc badge is a claim about a real person, so showing one
                    // that is not true is worse than showing none. Either way the whole cache must
                    // not be lost over a single row
                    (first, second) -> {
                      _Account kept = Boolean.TRUE.equals(first.getHasKYC()) ? second : first;
                      logger.warnf(
                          "Profile cache: account %s has several rows in"
                              + " soonmarket_profile_base_v, resolving to hasKYC = %s",
                          kept.getName(), kept.getHasKYC());
                      return kept;
                    }));
    profileCache = tempCache;

    logger.infof("Refresh of profile cache took %s ms", (System.currentTimeMillis() - start));
  }

  @Transactional
  protected void refreshShieldedCollectionsCache() {
    long start = System.currentTimeMillis();

    List<CollectionAuditEntity> collectionList = CollectionAuditEntity.getShieldedCollections();
    Map<String, Boolean> tmpCollectionShieldedCache = new HashMap<>();
    collectionList.forEach(c -> tmpCollectionShieldedCache.put(c.getCollectionId(), true));
    collectionShieldedCache = tmpCollectionShieldedCache;

    logger.infof(
        "Refresh of shielded collections took %s ms", (System.currentTimeMillis() - start));
  }

  @Transactional
  protected void refreshBlacklistedCollectionsCache() {
    long start = System.currentTimeMillis();

    List<CollectionAuditEntity> collectionList = CollectionAuditEntity.getBlacklistedCollections();
    Map<String, _BlacklistMetadata> tmpCollectionBlacklistCache = new HashMap<>();
    collectionList.forEach(
        c ->
            tmpCollectionBlacklistCache.put(
                c.getCollectionId(),
                _BlacklistMetadata.builder()
                    .blacklistDate(BaseMapper.mapDate(c.getBlacklistDate()))
                    .reason(c.getBlacklistReason())
                    .actor(c.getBlacklistActor())
                    .build()));
    collectionBlacklistedCache = tmpCollectionBlacklistCache;

    logger.infof(
        "Refresh of blacklisted collections took %s ms", (System.currentTimeMillis() - start));
  }

  @Transactional
  protected void refreshSupportedAssetsCache() {
    long start = System.currentTimeMillis();

    List<SupportedAssetsEntity> supportedAssets = SupportedAssetsEntity.listAll();
    Map<String, Integer> tempCache =
        supportedAssets.stream()
            .collect(
                keepFirst(
                    "supported assets",
                    SupportedAssetsEntity::getToken,
                    SupportedAssetsEntity::getPrecision));
    supportedAssetsCache = tempCache;

    logger.infof("Refresh of supported assets took %s ms", (System.currentTimeMillis() - start));
  }

  /*-
   * toMap that survives a duplicate key instead of throwing.
   *
   * The two argument Collectors.toMap throws IllegalStateException on a duplicate, which fails the
   * whole refresh - and since the cache is only assigned on success, the previous contents stay,
   * or nothing at all if it never succeeded once. A single duplicated row then costs the entire
   * cache rather than one entry. Keeping the first value and warning about it is the better trade:
   * one entry may be wrong, the rest keeps working, and the data problem stays visible in the log.
   */
  private static <T, K, V> Collector<T, ?, Map<K, V>> keepFirst(
      String cacheName, Function<T, K> key, Function<T, V> value) {
    BinaryOperator<V> keepFirstAndWarn =
        (first, second) -> {
          logger.warnf(
              "%s cache: duplicate entry, keeping %s and ignoring %s", cacheName, first, second);
          return first;
        };
    return Collectors.toMap(key, value, keepFirstAndWarn);
  }
}
