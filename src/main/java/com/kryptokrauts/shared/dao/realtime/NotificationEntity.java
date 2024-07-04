package com.kryptokrauts.shared.dao.realtime;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
@Table(name = "soonmarket_notification")
public class NotificationEntity extends PanacheEntityBase {

  @Id
  @GeneratedValue(strategy = GenerationType.IDENTITY)
  private Long id;

  private Long globalSequence;

  private String actionType;

  private String account;

  private Long blockTimestamp;

  private Long blocknum;

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

  public static NotificationEntity findOrGetNew(
      Long globalSequence, String actionType, String account) {
    NotificationEntity entity = NotificationEntity.findById(globalSequence, actionType, account);
    if (entity == null) {
      entity = new NotificationEntity();
    }
    return entity;
  }
}
