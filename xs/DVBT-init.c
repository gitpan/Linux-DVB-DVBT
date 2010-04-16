
 # /*---------------------------------------------------------------------------------------------------*/

SV *
dvb_device()
	INIT:
  AV * results;

	struct devinfo *entry ;
	struct list_head *info ;
	struct list_head *item, *safe;

  results = (AV *)sv_2mortal((SV *)newAV());

	CODE:

  /* get info */
  info = dvb_probe(0) ;

  /* TODO: return the device names too */

  /* Create Perl data */
  list_for_each(item, info)
  {
  HV * rh;
  HV * ch;
  int flags ;

		entry = list_entry(item, struct devinfo, next);

		/* Convert structure fields into hash elements */
		rh = (HV *)sv_2mortal((SV *)newHV());

      /*  char  device[32];
          int adapter_num ;
          int frontend_num ;
          char  name[32];
          char  bus[32];
          int   flags;
		*/

		HVS_S(rh, entry, device) ;
		HVS_S(rh, entry, name) ;
		HVS_I(rh, entry, adapter_num) ;
		HVS_I(rh, entry, frontend_num) ;
		HVS_I(rh, entry, flags) ;

		flags = entry->flags ;

		// Convert flags into capabilities HASH
		//	typedef enum fe_caps {
		//		FE_IS_STUPID			= 0,
		//		FE_CAN_INVERSION_AUTO		= 0x1,
		//		FE_CAN_FEC_1_2			= 0x2,
		//		FE_CAN_FEC_2_3			= 0x4,
		//		FE_CAN_FEC_3_4			= 0x8,
		//		FE_CAN_FEC_4_5			= 0x10,
		//		FE_CAN_FEC_5_6			= 0x20,
		//		FE_CAN_FEC_6_7			= 0x40,
		//		FE_CAN_FEC_7_8			= 0x80,
		//		FE_CAN_FEC_8_9			= 0x100,
		//		FE_CAN_FEC_AUTO			= 0x200,
		//		FE_CAN_QPSK			= 0x400,
		//		FE_CAN_QAM_16			= 0x800,
		//		FE_CAN_QAM_32			= 0x1000,
		//		FE_CAN_QAM_64			= 0x2000,
		//		FE_CAN_QAM_128			= 0x4000,
		//		FE_CAN_QAM_256			= 0x8000,
		//		FE_CAN_QAM_AUTO			= 0x10000,
		//		FE_CAN_TRANSMISSION_MODE_AUTO	= 0x20000,
		//		FE_CAN_BANDWIDTH_AUTO		= 0x40000,
		//		FE_CAN_GUARD_INTERVAL_AUTO	= 0x80000,
		//		FE_CAN_HIERARCHY_AUTO		= 0x100000,
		//		FE_CAN_8VSB			= 0x200000,
		//		FE_CAN_16VSB			= 0x400000,
		//		FE_NEEDS_BENDING		= 0x20000000, // not supported anymore, don't use (frontend requires frequency bending)
		//		FE_CAN_RECOVER			= 0x40000000, // frontend can recover from a cable unplug automatically
		//		FE_CAN_MUTE_TS			= 0x80000000  // frontend can stop spurious TS data output
		//	} fe_caps_t;

		ch = (HV *)sv_2mortal((SV *)newHV());
		HVS_BIT(ch, flags, FE_CAN_INVERSION_AUTO) ;

		HVS_BIT(ch, flags, FE_CAN_FEC_1_2) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_2_3) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_3_4) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_4_5) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_5_6) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_6_7) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_7_8) ;
		HVS_BIT(ch, flags, FE_CAN_FEC_AUTO) ;

		HVS_BIT(ch, flags, FE_CAN_QPSK) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_16) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_32) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_64) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_128) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_256) ;
		HVS_BIT(ch, flags, FE_CAN_QAM_AUTO) ;

		HVS_BIT(ch, flags, FE_CAN_TRANSMISSION_MODE_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_BANDWIDTH_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_GUARD_INTERVAL_AUTO) ;
		HVS_BIT(ch, flags, FE_CAN_HIERARCHY_AUTO) ;

		HVS_BIT(ch, flags, FE_CAN_8VSB) ;
		HVS_BIT(ch, flags, FE_CAN_16VSB) ;

		HVS_BIT(ch, flags, FE_CAN_RECOVER) ;
		HVS_BIT(ch, flags, FE_CAN_MUTE_TS) ;

		HVS(ch, FE_IS_STUPID, newSViv(flags==0 ? 1 : 0)) ;

		HVS(rh, capabilities, newRV((SV *)ch)) ;

		av_push(results, newRV((SV *)rh));

  }


	/* Free up results */
  /* TODO: Provide C call to do this */
  list_for_each_safe(item,safe,info)
  {
		entry = list_entry(item, struct devinfo, next);
		list_del(&entry->next);
		free(entry);
  };


  RETVAL = newRV((SV *)results);
	OUTPUT:
  RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

SV *
dvb_device_names(DVB *dvb)
	INIT:
        HV * results;

	CODE:
		results = (HV *)sv_2mortal((SV *)newHV());

		/* get device names from dvb struct */
		HVS(results, fe_name, newSVpv(dvb->frontend, 0)) ;
		HVS(results, demux_name, newSVpv(dvb->demux, 0)) ;
		HVS(results, dvr_name, newSVpv(dvb->dvr, 0)) ;

	    RETVAL = newRV((SV *)results);
	  OUTPUT:
	    RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

DVB *
dvb_init(char *adapter, int frontend)
	CODE:
	 RETVAL = dvb_init(adapter, frontend) ;
	OUTPUT:
	 RETVAL


 # /*---------------------------------------------------------------------------------------------------*/

DVB *
dvb_init_nr(int adapter_num, int frontend_num)
	CODE:
	 RETVAL = dvb_init_nr(adapter_num, frontend_num) ;
	OUTPUT:
	 RETVAL

 # /*---------------------------------------------------------------------------------------------------*/

void
dvb_fini(DVB *dvb);
	CODE:
	 dvb_fini(dvb) ;


 # /*---------------------------------------------------------------------------------------------------*/

void
dvb_set_debug(int debug);
	CODE:
	 dvb_debug = debug ;
	 DVBT_DEBUG = debug ;


