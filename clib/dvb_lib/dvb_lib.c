#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <ctype.h>
#include <fcntl.h>
#include <inttypes.h>
#include <signal.h>
#include <sys/time.h>
#include <sys/ioctl.h>
#include <sys/poll.h>
#include <sys/types.h>

#include "dvb_lib.h"


static void adapter_name(int adap, char *adapter_name, int len) ;
static void frontend_name(int frontend, char *frontend_name, int len, char *adapter_name) ;
static void dvr_name(int dvr, char *dvr_name, int len, char *adapter_name) ;
static void demux_name(int demux, char *demux_name, int len, char *adapter_name) ;


/* ----------------------------------------------------------------------- */
static void adapter_name(int adap, char *adapter_name, int len)
{
	snprintf(adapter_name,len,"/dev/dvb/adapter%d", adap);
}

/* ----------------------------------------------------------------------- */
static void frontend_name(int frontend, char *frontend_name, int len, char *adapter_name)
{
	snprintf(frontend_name,len,"%s/frontend%d", adapter_name, frontend);
}

/* ----------------------------------------------------------------------- */
static void dvr_name(int dvr, char *dvr_name, int len, char *adapter_name)
{
	snprintf(dvr_name,len,"%s/dvr%d", adapter_name, dvr);
}

/* ----------------------------------------------------------------------- */
static void demux_name(int demux, char *demux_name, int len, char *adapter_name)
{
	snprintf(demux_name,len,"%s/demux%d", adapter_name, demux);
}



/* ----------------------------------------------------------------------- */
struct list_head* dvb_probe(int debug)
{
static struct list_head list ;

struct dvb_frontend_info feinfo;
char adapter[32];
char device[32];
struct devinfo *info ;
int adap, fe, fd;

struct devinfo *entry ;
struct list_head *item;

	INIT_LIST_HEAD(&list);

    for (adap = 0; adap < MAX_ADAPTERS; adap++)
    {
		adapter_name(adap, adapter, sizeof(adapter));

        for (fe = 0; fe < MAX_FRONTENDS; fe++)
        {
			frontend_name(fe, device,sizeof(device), adapter) ;
			fd = open(device, O_RDONLY | O_NONBLOCK);
			if (-1 == fd)
				continue;

			if (-1 == ioctl(fd, FE_GET_INFO, &feinfo)) {
				if (debug)
					perror("ioctl FE_GET_INFO");
				close(fd);
				continue;
			}

		    info = (struct devinfo *)malloc(sizeof(struct devinfo));
		    memset(info,0,sizeof(struct devinfo));
			strcpy(info->device, adapter);
			strcpy(info->name, feinfo.name);
			info->adapter_num = adap ;
			info->frontend_num = fe ;
			info->flags = (int)feinfo.caps ;
		    list_add_tail(&info->next, &list);

			close(fd);

        }
    }

    return &list;
}

/*----------------------------------------------------------------------
 Portable function to set a socket into nonblocking mode.
 Calling this on a socket causes all future read() and write() calls on
 that socket to do only as much as they can immediately, and return
 without waiting.
 If no data can be read or written, they return -1 and set errno
 to EAGAIN (or EWOULDBLOCK).
 Thanks to Bjorn Reese for this code.
----------------------------------------------------------------------*/
int setNonblocking(int fd)
{
    int flags;

    /* If they have O_NONBLOCK, use the Posix way to do it */
#if defined(O_NONBLOCK)
    /* Fixme: O_NONBLOCK is defined but broken on SunOS 4.1.x and AIX 3.2.5. */
    if (-1 == (flags = fcntl(fd, F_GETFL, 0)))
        flags = 0;
    return fcntl(fd, F_SETFL, flags | O_NONBLOCK);
#else
    /* Otherwise, use the old way of doing it */
    flags = 1;
    return ioctl(fd, FIOBIO, &flags);
#endif
}

