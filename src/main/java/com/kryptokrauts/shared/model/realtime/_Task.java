package com.kryptokrauts.shared.model.realtime;

import com.kryptokrauts.shared.model._BaseModel;
import com.kryptokrauts.shared.model.common._Asset;
import com.kryptokrauts.shared.model.common._Collection;
import com.kryptokrauts.soonmarket.api.common.Enums.MarketType;
import io.quarkus.runtime.annotations.RegisterForReflection;
import lombok.Getter;
import lombok.Setter;
import lombok.experimental.SuperBuilder;
import org.eclipse.microprofile.openapi.annotations.media.Schema;

@Schema(description = "represents an open user task")
@Getter
@Setter
@SuperBuilder
@RegisterForReflection
public abstract class _Task extends _BaseModel {

  private _Collection collection;

  private _Asset asset;

  private Boolean bundle;

  private Integer bundleSize;

  private String type;

  public abstract MarketType getMarketType();
}
