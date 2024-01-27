package com.kryptokrauts.shared.entity;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Id;
import jakarta.persistence.MappedSuperclass;
import lombok.Getter;

@Getter
@MappedSuperclass
public class EventLogEntity extends PanacheEntityBase {

  @Id private long id;

  private long blocknum;

  private String type;

  private String data;
}
