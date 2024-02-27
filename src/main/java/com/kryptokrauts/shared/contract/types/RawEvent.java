package com.kryptokrauts.shared.contract.types;

import io.quarkus.runtime.annotations.RegisterForReflection;
import java.io.Serializable;
import lombok.Data;

@RegisterForReflection
@Data
public class RawEvent implements Serializable {

  private static final long serialVersionUID = 1L;

  private long blocknum;

  private long timestamp;

  private String type;

  private String transaction_id;

  private Object data;

  private Long global_sequence;
}
