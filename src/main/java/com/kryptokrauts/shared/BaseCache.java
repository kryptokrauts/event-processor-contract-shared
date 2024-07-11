package com.kryptokrauts.shared;

import com.kryptokrauts.shared.dao.common.CollectionAuditEntity;
import com.kryptokrauts.shared.dao.common.ExchangeRateEntity;
import com.kryptokrauts.shared.dao.common.MarketConfigEntity;
import com.kryptokrauts.shared.dao.common.ProfileBaseView;
import com.kryptokrauts.shared.dao.common.SupportedAssetsEntity;
import com.kryptokrauts.shared.model.common._Account;
import com.kryptokrauts.shared.model.common._BlacklistMetadata;
import com.kryptokrauts.shared.model.common._MarketConfig;
import io.quarkus.panache.common.Sort;
import io.quarkus.scheduler.Scheduled;
import jakarta.inject.Singleton;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
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
    return supportedAssetsCache.get(token);
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

  private void refreshExchangeRateCache() {
    long start = System.currentTimeMillis();

    List<ExchangeRateEntity> exchangeRateList = ExchangeRateEntity.listAll();
    Map<String, Double> tempCache =
        exchangeRateList.stream()
            .collect(
                Collectors.toMap(ExchangeRateEntity::getTokenSymbol, ExchangeRateEntity::getUsd));
    exchangeRateCache = tempCache;

    logger.infof(
        "Refresh of exchange rates cache took %s ms", (System.currentTimeMillis() - start));
  }

  private void refreshMarketConfigCache() {
    long start = System.currentTimeMillis();

    marketConfigCache =
        ((MarketConfigEntity) MarketConfigEntity.findAll(Sort.descending("id")).firstResult())
            .toModel();

    logger.infof("Refresh of market config cache took %s ms", (System.currentTimeMillis() - start));
  }

  private void refreshProfileCache() {
    long start = System.currentTimeMillis();

    List<ProfileBaseView> profileList = ProfileBaseView.listAll();
    Map<String, _Account> tempCache =
        profileList.stream()
            .collect(Collectors.toMap(ProfileBaseView::getAccount, ProfileBaseView::toModel));
    profileCache = tempCache;

    logger.infof("Refresh of profile cache took %s ms", (System.currentTimeMillis() - start));
  }

  private void refreshShieldedCollectionsCache() {
    long start = System.currentTimeMillis();

    List<CollectionAuditEntity> collectionList = CollectionAuditEntity.getShieldedCollections();
    Map<String, Boolean> tmpCollectionShieldedCache = new HashMap<>();
    collectionList.forEach(c -> tmpCollectionShieldedCache.put(c.getCollectionId(), true));
    collectionShieldedCache = tmpCollectionShieldedCache;

    logger.infof(
        "Refresh of shielded collections took %s ms", (System.currentTimeMillis() - start));
  }

  private void refreshBlacklistedCollectionsCache() {
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

  private void refreshSupportedAssetsCache() {
    long start = System.currentTimeMillis();

    List<SupportedAssetsEntity> supportedAssets = SupportedAssetsEntity.listAll();
    Map<String, Integer> tempCache =
        supportedAssets.stream()
            .collect(
                Collectors.toMap(
                    SupportedAssetsEntity::getToken, SupportedAssetsEntity::getPrecision));
    supportedAssetsCache = tempCache;

    logger.infof("Refresh of supported assets took %s ms", (System.currentTimeMillis() - start));
  }
}
