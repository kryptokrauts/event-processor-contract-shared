package com.kryptokrauts.shared.dao.embeddables;

import com.kryptokrauts.shared.BaseMapper;
import com.kryptokrauts.shared.model.common._PriceInfo;
import io.quarkus.runtime.annotations.RegisterForReflection;
import jakarta.persistence.Column;
import jakarta.persistence.Embeddable;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@Builder
@AllArgsConstructor
@NoArgsConstructor
@Embeddable
@RegisterForReflection
public class Price {

  private String token;

  private Double price;

  @Column(insertable = false, updatable = false)
  private Double royalty;

  public _PriceInfo toModel() {
    if (this.token != null) {
      return BaseMapper.buildPriceInfo(this.token, this.price, this.royalty);
    }
    return null;
  }
}
