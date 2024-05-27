package com.kryptokrauts.shared.model.common;

import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import com.kryptokrauts.shared.model._BaseModel;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@JsonPropertyOrder(alphabetic = true)
@Getter
@Setter
@RegisterForReflection
@SuperBuilder
public class _Collection extends _BaseModel {
  private String collectionId;

  private String collectionName;

  private String collectionImage;

  // private String category;

  private _Account creator;

  private Double royalty;

  // private Boolean hasKYC;

  private Boolean shielded;

  private Boolean blacklisted;

  public Double getRoyalty() {
    if (this.royalty != null) {
      return this.royalty * 100;
    }
    return null;
  }
}
