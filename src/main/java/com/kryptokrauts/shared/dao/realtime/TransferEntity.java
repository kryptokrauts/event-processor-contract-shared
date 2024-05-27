package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "atomicassets_transfer")
public class TransferEntity extends PanacheEntityBase {

  @Id private Long transferId;

  private Long primaryAssetId;

  private String sender;

  private String receiver;

  private String collectionId;

  private Boolean bundle;

  public static TransferEntity findByTransferId(Long transferId) {
    return TransferEntity.find("transferId = ?1", transferId).firstResult();
  }
}
