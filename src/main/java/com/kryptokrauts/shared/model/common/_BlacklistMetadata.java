package com.kryptokrauts.shared.model.common;

import com.kryptokrauts.shared.model._BaseModel;
import io.quarkus.runtime.annotations.RegisterForReflection;
import java.util.Date;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;

@Getter
@Setter
@SuperBuilder
@RegisterForReflection
public class _BlacklistMetadata extends _BaseModel {

  private Date blacklistDate;

  private String reason;

  private String actor;
}
