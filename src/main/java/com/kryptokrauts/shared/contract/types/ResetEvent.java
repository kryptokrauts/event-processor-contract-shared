package com.kryptokrauts.shared.contract.types;

import io.quarkus.runtime.annotations.RegisterForReflection;
import java.io.Serializable;
import lombok.Data;

@RegisterForReflection
@Data
public class ResetEvent implements Serializable {

  private static final long serialVersionUID = 1L;

  private String reset_type;

  private long timestamp;

  private String details;

  private Boolean clean_database;

  private long reset_blocknum;

  private long restart_at_block;
}
