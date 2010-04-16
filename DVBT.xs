#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "ppport.h"

/*---------------------------------------------------------------------------------------------------*/
#include "xs/DVBT-common.h"

#define DVBT_VERSION		"1.11"

MODULE = Linux::DVB::DVBT		PACKAGE = Linux::DVB::DVBT

PROTOTYPES: ENABLE

 # /*---------------------------------------------------------------------------------------------------*/

INCLUDE: xs/DVBT-init.c
INCLUDE: xs/DVBT-scan.c
INCLUDE: xs/DVBT-tuning.c
INCLUDE: xs/DVBT-epg.c
INCLUDE: xs/DVBT-record.c


 # /*---------------------------------------------------------------------------------------------------*/


