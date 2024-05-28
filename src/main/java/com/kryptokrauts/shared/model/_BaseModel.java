package com.kryptokrauts.shared.model;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.kryptokrauts.shared.RandomNumberHolder;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;

@Getter
@SuperBuilder
@AllArgsConstructor
@NoArgsConstructor
@RegisterForReflection
public class _BaseModel {

  public static final ObjectMapper objectMapper = new ObjectMapper();

  private Long uiid;

  public Long getUiid() {
    return Math.abs(RandomNumberHolder.randomNumberGenerator.nextLong());
  }
}
