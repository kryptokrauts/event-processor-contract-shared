package com.kryptokrauts.shared.contract.types;

import io.quarkus.runtime.annotations.RegisterForReflection;
import java.io.Serializable;
import lombok.Data;

@RegisterForReflection
@Data
public class NodeSyncStatusEvent implements Serializable {

  private static final long serialVersionUID = 1L;

  private long timestamp;

  private String processor;

  private long head_block;

  private long current_block;

  private long diff;

  private Boolean in_sync;

  private String current_sync_date;
}
