package com.kryptokrauts.shared.dao.common;

import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "atomicmarket_token")
public class SupportedAssetsEntity extends PanacheEntityBase {

  @Id private String contract;

  @Id private String token;

  private Integer precision;
}
