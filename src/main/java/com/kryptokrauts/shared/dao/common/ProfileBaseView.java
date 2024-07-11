package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._Account;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import lombok.Getter;

@Getter
@Entity(name = "soonmarket_profile_base_v")
public class ProfileBaseView extends PanacheEntityBase {
  @Id private String account;

  private Boolean hasKyc;

  public _Account toModel() {
    if (this.account != null) {
      return _Account.builder().name(this.account).hasKYC(this.hasKyc).build();
    }
    return null;
  }
}
