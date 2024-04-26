package com.kryptokrauts.shared.contract.exception;

public class EntityNotYetAvailableException extends RuntimeException {
  public EntityNotYetAvailableException(String msg) {
    super(msg);
  }
}
