#include <regex.h>
#include <stdlib.h>
#include <stdio.h>


// this function returns true if a matches the rgx b, false otherwise
int equals(char *a, char *b) {
  regex_t regex;
  int comp = regcomp(&regex, b, REG_EXTENDED|REG_NOSUB);
  if (comp) {
    printf("Regex expression could not be compiled");
    return 0;
  }
  comp = regexec(&regex, a, 0, NULL, 0);
  if (!comp) {
    return 1;
  }
  return 0;
}
