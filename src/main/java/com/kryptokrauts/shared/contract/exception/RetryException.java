package com.kryptokrauts.shared.contract.exception;

public class RetryException extends RuntimeException {

  public RetryException(String msg, Exception e) {
    super(msg, e);
  }

  public RetryException(Exception e) {
    super(e);
  }
}
