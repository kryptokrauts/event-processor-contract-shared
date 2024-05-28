package com.kryptokrauts.shared.dao.realtime;

import com.kryptokrauts.shared.enums.TaskType;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "soonmarket_open_task_v")
public class TaskEntity extends PanacheEntityBase {

  @Id private String id;

  private String account;

  private Long blockTimestamp;

  private Long actionId;

  private String taskType;

  private Boolean bundle;

  private Integer bundleSize;

  private Double price;

  private String token;

  /** asset info */
  private Long assetId;

  private String assetName;

  private String assetMediaType;

  private String assetMedia;

  private String assetMediaPreview;

  private Long editionSize;

  private Long serial;

  /** collection info */
  private String collectionId;

  private String collectionName;

  private String collectionImage;

  private Boolean shielded;

  private Boolean blacklisted;

  public static TaskEntity findById(Long actionId, TaskType actionType, String account) {
    return TaskEntity.find(
            "actionId = ?1 AND taskType = ?2 AND account =?3",
            actionId,
            actionType.toString(),
            account)
        .firstResult();
  }
}
