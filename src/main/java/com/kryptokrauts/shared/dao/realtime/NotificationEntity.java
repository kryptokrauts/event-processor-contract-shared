package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;

@Getter
@Entity
@Table(name = "soonmarket_notification")
public class NotificationEntity extends PanacheEntityBase {

  @Id private Long globalSequence;

  @Id private String actionType;

  @Id private String account;

  private Long id;

  private Long blockTimestamp;

  private Long actionId;

  private Boolean acknowledged;

  private Long acknowledgedDate;

  public static NotificationEntity findById(
      Long globalSequence, String actionType, String account) {
    return NotificationEntity.find(
            "globalSequence = ?1 AND actionType = ?2 AND account =?3",
            globalSequence,
            actionType,
            account)
        .firstResult();
  }
}
