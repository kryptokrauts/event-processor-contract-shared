package com.kryptokrauts.shared.entity;

import jakarta.persistence.MappedSuperclass;
import lombok.Getter;

@Getter
@MappedSuperclass
public class EventLogEntity extends PanacheEntityBase {

  private String type;

  private String data;
}
