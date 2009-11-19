/*
 * handle dvb devices
 * import vdr channels.conf files
 */

#include <features.h>

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>
#include <sys/time.h>

#include "dvb_tune.h"
#include "dvb_stream.h"
#include "dvb_debug.h"

#define BUFFSIZE	4096

// If large file support is not included, then make the value do nothing
#ifndef O_LARGEFILE
#define O_LARGEFILE	0
#endif

/* ----------------------------------------------------------------------- */
int write_stream(struct dvb_state *h, char *filename, int sec)
{
    time_t start, now;
    char buffer[BUFFSIZE];
    int file;
    int count;
    int rc;

    
    if (-1 == h->dvro)
    {
		fprintf(stderr,"dvr device not open\n");
		exit(1);
    }
    
    file = open(filename, O_WRONLY | O_TRUNC | O_CREAT | O_LARGEFILE, 0666);
    if (-1 == file) {
		fprintf(stderr,"open %s: %s\n",filename,strerror(errno));
		exit(1);
    }

    count = 0;
    start = time(NULL);
	for (;;)
	{
		rc = read(h->dvro, buffer, sizeof(buffer));
		switch (rc) {
		case -1:
			perror("read");
			exit(1);
		case 0:
			fprintf(stderr,"EOF\n");
			exit(1);
		default:
			write(file, buffer, rc);
			count += rc;
			break;
		}
		now = time(NULL);

		if (-1 != sec && now - start >= sec)
			break;
	}
    
    close(file);

    return 0;
}

