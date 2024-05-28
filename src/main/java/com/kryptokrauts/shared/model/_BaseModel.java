package com.kryptokrauts.shared.model;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.kryptokrauts.shared.RandomNumberHolder;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.experimental.SuperBuilder;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Getter
@SuperBuilder
@AllArgsConstructor
@NoArgsConstructor
@RegisterForReflection
public class _BaseModel {

  public static final ObjectMapper objectMapper = new ObjectMapper();

  @Schema(description = "unique ui identifier")
  private Long uiid;

  public Long getUiid() {
    return Math.abs(RandomNumberHolder.randomNumberGenerator.nextLong());
  }
}
