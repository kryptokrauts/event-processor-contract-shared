package com.kryptokrauts.shared.contract.exception;

import java.util.Arrays;
import java.util.stream.Collectors;

public class StacktraceParser {

  public static String getRelevantLines(Exception ex) {

    String relevantStacktrace = null;

    if (ex.getStackTrace() != null) {
      relevantStacktrace =
          Arrays.asList(ex.getStackTrace()).stream()
              .filter(s -> s.getClassName().contains("kryptokrauts"))
              .map(
                  e ->
                      String.format(
                          "%s.%s:%s", e.getClassName(), e.getMethodName(), e.getLineNumber()))
              .collect(Collectors.joining("\n"));
    }
    return relevantStacktrace;
  }
}
