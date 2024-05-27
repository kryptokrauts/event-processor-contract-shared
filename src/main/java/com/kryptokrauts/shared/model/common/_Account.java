package com.kryptokrauts.shared.model.common;

import com.kryptokrauts.shared.model._BaseModel;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@Getter
@Setter
@RegisterForReflection
@SuperBuilder
public class _Account extends _BaseModel {

  private String name;

  private Boolean image;

  private Boolean hasKYC;

  public String getImage() {
    if (this.image == null || this.image == false) {
      return "https://media.soon.market/images/profile_placeholder.png";
    }
    return "https://media.soon.market/images/" + this.name;
  }
}
