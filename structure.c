/* Authors: Ashley, Christine, Melanie */
/* Allows LOOP block to loop through a file */

#include <stdio.h>
#include <string.h>

extern char *RS;
extern char *FS;

void setRS(char *newRS) {
  RS = newRS;
}

void setFS(char *newFS) {
  FS = newFS;
}

void loop(char *line);

void end();

int main(int argc, char **argv) {

  /* Error handling for if filename is not specified */
  if (argc < 2) {
    fprintf(stderr, "usage: ./bawk.sh [bawk file] [input file]\n");
  }
  else {
    char *filename = argv[1];
    FILE *fp = fopen(filename, "rw");
    char buffer[256];
    size_t n = sizeof(buffer);
    char *buf = buffer;
    
		while(getdelim(&buf, &n, *RS, fp) > 0){
			buffer[strcspn(buffer, RS)] = '\0';
      loop(buffer);
    }

    end();
  }
}
