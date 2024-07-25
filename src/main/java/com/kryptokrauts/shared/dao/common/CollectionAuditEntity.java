package com.kryptokrauts.shared.dao.common;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.quarkus.panache.common.Sort;
import io.quarkus.panache.common.Sort.Direction;
import io.quarkus.panache.common.Sort.NullPrecedence;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import java.util.List;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_collection_audit_info_v")
public class CollectionAuditEntity extends PanacheEntityBase {

  @Id private String collectionId;

  private Boolean shielded;

  private Long shieldingDate;

  private Boolean blacklisted;

  private Long blacklistDate;

  private String blacklistReason;

  private String blacklistActor;

  public static List<CollectionAuditEntity> getShieldedCollections() {
    return CollectionAuditEntity.find(
            "shielded", Sort.by("shieldingDate", Direction.Descending, NullPrecedence.NULLS_LAST))
        .list();
  }

  public static List<CollectionAuditEntity> getBlacklistedCollections() {
    return CollectionAuditEntity.find(
            "blacklisted",
            Sort.by("blacklistDate", Direction.Descending, NullPrecedence.NULLS_LAST))
        .list();
  }
}
