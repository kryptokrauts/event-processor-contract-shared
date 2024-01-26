package com.kryptokrauts.shared.entity;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "atomicassets_event_log")
public class EventLogEntity extends PanacheEntityBase {

  @Id private long id;

  private long blocknum;

  private String type;

  private String data;
}
