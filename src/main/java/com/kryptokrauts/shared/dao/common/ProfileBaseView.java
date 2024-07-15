package com.kryptokrauts.shared.dao.common;

import com.kryptokrauts.shared.model.common._Account;
import io.quarkus.hibernate.orm.panache.PanacheEntityBase;
import io.quarkus.panache.common.Parameters;
import jakarta.persistence.Entity;
import jakarta.persistence.Id;
import jakarta.persistence.Table;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
@Entity
@Table(name = "soonmarket_profile_base_v")
public class ProfileBaseView extends PanacheEntityBase {

  @Id private String account;

  private Boolean hasKyc;

  public _Account toModel() {
    if (this.account != null) {
      return _Account.builder().name(this.account).hasKYC(this.hasKyc).build();
    }
    return null;
  }

  public static ProfileBaseView findByAccount(String account) {
    return ProfileBaseView.find("account = :account", Parameters.with("account", account))
        .firstResult();
  }
}
