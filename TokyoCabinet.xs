/*************************************************************************************************
 * Perl binding of Tokyo Cabinet
 *                                                               Copyright (C) 2006-2010 FAL Labs
 * This file is part of Tokyo Cabinet.
 * Tokyo Cabinet is free software; you can redistribute it and/or modify it under the terms of
 * the GNU Lesser General Public License as published by the Free Software Foundation; either
 * version 2.1 of the License or any later version.  Tokyo Cabinet is distributed in the hope
 * that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 * You should have received a copy of the GNU Lesser General Public License along with Tokyo
 * Cabinet; if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330,
 * Boston, MA 02111-1307 USA.
 *************************************************************************************************/


#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include <tcutil.h>
#include <tchdb.h>
#include <tcbdb.h>
#include <tcfdb.h>
#include <tctdb.h>
#include <tcadb.h>
#include <stdlib.h>
#include <time.h>
#include <stdbool.h>
#include <stdint.h>
#include <math.h>


static int bdb_cmp(const char *aptr, int asiz, const char *bptr, int bsiz, SV *cmp){
  int rv;
  dSP;
  ENTER;
  SAVETMPS;
  PUSHMARK(SP);
  XPUSHs(sv_2mortal(newSVpvn(aptr, asiz)));
  XPUSHs(sv_2mortal(newSVpvn(bptr, bsiz)));
  PUTBACK;
  rv = call_sv(cmp, G_SCALAR);
  SPAGAIN;
  rv = (rv == 1) ? POPi : 0;
  PUTBACK;
  FREETMPS;
  LEAVE;
  return rv;
}


static int tdbqry_proc(const void *pkbuf, int pksiz, TCMAP *tcols, SV *proc){
  HV *cols;
  SV *sv;
  const char *kbuf, *vbuf;
  char *rkbuf, *rvbuf;
  int ksiz, vsiz, rv;
  STRLEN rvsiz;
  I32 rksiz;
  cols = newHV();
  tcmapiterinit(tcols);
  while((kbuf = tcmapiternext(tcols, &ksiz)) != NULL){
    vbuf = tcmapiterval(kbuf, &vsiz);
    hv_store(cols, kbuf, ksiz, newSVpvn(vbuf, vsiz), 0);
  }
  dSP;
  ENTER;
  SAVETMPS;
  PUSHMARK(SP);
  XPUSHs(sv_2mortal(newSVpvn(pkbuf, pksiz)));
  XPUSHs(sv_2mortal(newRV_inc((SV *)cols)));
  PUTBACK;
  rv = call_sv(proc, G_SCALAR);
  SPAGAIN;
  rv = (rv == 1) ? POPi : 0;
  PUTBACK;
  FREETMPS;
  LEAVE;
  if(rv & TDBQPPUT){
    tcmapclear(tcols);
    hv_iterinit(cols);
    while((sv = hv_iternextsv(cols, &rkbuf, &rksiz)) != NULL){
      rvbuf = SvPV(sv, rvsiz);
      tcmapput(tcols, rkbuf, rksiz, rvbuf, rvsiz);
    }
  }
  SvREFCNT_dec(cols);
  return rv;
}


MODULE = TokyoCabinet		PACKAGE = TokyoCabinet
PROTOTYPES: DISABLE



##----------------------------------------------------------------
## common functions
##----------------------------------------------------------------


const char *
tc_version()
CODE:
	RETVAL = tcversion;
OUTPUT:
	RETVAL


double
tc_atoi(str)
	char *	str
CODE:
	RETVAL = tcatoi(str);
OUTPUT:
	RETVAL


double
tc_atof(str)
	char *	str
CODE:
	RETVAL = tcatof(str);
OUTPUT:
	RETVAL


SV *
tc_bercompress(sv)
	SV *	sv
PREINIT:
	AV *av;
	unsigned char *buf, *wp;
	int i, len;
	unsigned int num;
CODE:
	av = (AV *)SvRV(sv);
	len = av_len(av) + 1;
	buf = tcmalloc(len * 5 + 1);
	wp = buf;
	for(i = 0; i < len; i++){
	  num = SvIV(*av_fetch(av, i, 0));
	  if(num < (1 << 7)){
	    *(wp++) = num;
	  } else if(num < (1 << 14)){
	    *(wp++) = (num >> 7) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else if(num < (1 << 21)){
	    *(wp++) = (num >> 14) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else if(num < (1 << 28)){
	    *(wp++) = (num >> 21) | 0x80;
	    *(wp++) = ((num >> 14) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else {
	    *(wp++) = (num >> 28) | 0x80;
	    *(wp++) = ((num >> 21) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 14) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  }
	}
	RETVAL = newRV_noinc(newSVpvn((char *)buf, wp - buf));
	tcfree(buf);
OUTPUT:
	RETVAL


AV *
tc_beruncompress(sv)
	SV *	sv
PREINIT:
	AV *av;
	const unsigned char *ptr;
	STRLEN size;
	unsigned int left, c, num;
CODE:
	av = newAV();
	sv = SvRV(sv);
	ptr = (unsigned char *)SvPV(sv, size);
	left = size;
	while(left > 0){
	  num = 0;
	  do {
	    c = *ptr;
	    num = num * 0x80 + (c & 0x7f);
	    ptr++;
	    left--;
	  } while(c >= 0x80);
	  av_push(av, newSViv(num));
	}
	RETVAL = (AV *)sv_2mortal((SV *)av);
OUTPUT:
	RETVAL


SV *
tc_diffcompress(sv)
	SV *	sv
PREINIT:
	AV *av;
	unsigned char *buf, *wp;
	int i, len;
	unsigned int lnum, num, tnum;
CODE:
	av = (AV *)SvRV(sv);
	len = av_len(av) + 1;
	lnum = 0;
	buf = tcmalloc(len * 5 + 1);
	wp = buf;
	for(i = 0; i < len; i++){
	  num = SvIV(*av_fetch(av, i, 0));
	  tnum = num;
	  num -= lnum;
	  if(num < (1 << 7)){
	    *(wp++) = num;
	  } else if(num < (1 << 14)){
	    *(wp++) = (num >> 7) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else if(num < (1 << 21)){
	    *(wp++) = (num >> 14) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else if(num < (1 << 28)){
	    *(wp++) = (num >> 21) | 0x80;
	    *(wp++) = ((num >> 14) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  } else {
	    *(wp++) = (num >> 28) | 0x80;
	    *(wp++) = ((num >> 21) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 14) & 0x7f) | 0x80;
	    *(wp++) = ((num >> 7) & 0x7f) | 0x80;
	    *(wp++) = num & 0x7f;
	  }
	  lnum = tnum;
	}
	RETVAL = newRV_noinc(newSVpvn((char *)buf, wp - buf));
	tcfree(buf);
OUTPUT:
	RETVAL


AV *
tc_diffuncompress(sv)
	SV *	sv
PREINIT:
	AV *av;
	const unsigned char *ptr;
	STRLEN size;
	unsigned int left, c, num, sum;
CODE:
	av = newAV();
	sv = SvRV(sv);
	ptr = (unsigned char *)SvPV(sv, size);
	left = size;
	sum = 0;
	while(left > 0){
	  num = 0;
	  do {
	    c = *ptr;
	    num = num * 0x80 + (c & 0x7f);
	    ptr++;
	    left--;
	  } while(c >= 0x80);
	  sum += num;
	  av_push(av, newSViv(sum));
	}
	RETVAL = (AV *)sv_2mortal((SV *)av);
OUTPUT:
	RETVAL


int
tc_strdistance(asv, bsv, isutf)
	SV *	asv
	SV *	bsv
	int	isutf
PREINIT:
	const char *astr, *bstr;
CODE:
	asv = SvRV(asv);
	astr = SvPV_nolen(asv);
	bsv = SvRV(bsv);
	bstr = SvPV_nolen(bsv);
	RETVAL = isutf ? tcstrdistutf(astr, bstr) : tcstrdist(astr, bstr);
OUTPUT:
	RETVAL



##----------------------------------------------------------------
## the hash database API
##----------------------------------------------------------------


void *
hdb_new()
PREINIT:
	TCHDB *hdb;
CODE:
	hdb = tchdbnew();
	tchdbsetmutex(hdb);
	RETVAL = hdb;
OUTPUT:
	RETVAL


void
hdb_del(hdb)
	void *	hdb
CODE:
	tchdbdel(hdb);


const char *
hdb_errmsg(ecode)
	int	ecode
CODE:
	RETVAL = tchdberrmsg(ecode);
OUTPUT:
	RETVAL


int
hdb_ecode(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbecode(hdb);
OUTPUT:
	RETVAL


int
hdb_tune(hdb, bnum, apow, fpow, opts)
	void *	hdb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tchdbtune(hdb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
hdb_setcache(hdb, rcnum)
	void *	hdb
	int	rcnum
CODE:
	RETVAL = tchdbsetcache(hdb, rcnum);
OUTPUT:
	RETVAL


int
hdb_setxmsiz(hdb, xmsiz)
	void *	hdb
	double	xmsiz
CODE:
	RETVAL = tchdbsetxmsiz(hdb, xmsiz);
OUTPUT:
	RETVAL


int
hdb_setdfunit(hdb, dfunit)
	void *	hdb
	int	dfunit
CODE:
	RETVAL = tchdbsetdfunit(hdb, dfunit);
OUTPUT:
	RETVAL


int
hdb_open(hdb, path, omode)
	void *	hdb
	char *	path
	int	omode
CODE:
	RETVAL = tchdbopen(hdb, path, omode);
OUTPUT:
	RETVAL


int
hdb_close(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbclose(hdb);
OUTPUT:
	RETVAL


int
hdb_put(hdb, key, val)
	void *	hdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tchdbput(hdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
hdb_putkeep(hdb, key, val)
	void *	hdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tchdbputkeep(hdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
hdb_putcat(hdb, key, val)
	void *	hdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tchdbputcat(hdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
hdb_putasync(hdb, key, val)
	void *	hdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tchdbputasync(hdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
hdb_out(hdb, key)
	void *	hdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tchdbout(hdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


void
hdb_get(hdb, key)
	void *	hdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
	char *vbuf;
	int vsiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	vbuf = tchdbget(hdb, kbuf, (int)ksiz, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


int
hdb_vsiz(hdb, key)
	void *	hdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tchdbvsiz(hdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
hdb_iterinit(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbiterinit(hdb);
OUTPUT:
	RETVAL


void
hdb_iternext(hdb)
	void *	hdb
PREINIT:
	char *vbuf;
	int vsiz;
PPCODE:
	vbuf = tchdbiternext(hdb, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
hdb_fwmkeys(hdb, prefix, max)
	void *	hdb
	SV *	prefix
	int	max
PREINIT:
	AV *av;
	STRLEN psiz;
	TCLIST *keys;
	const char *pbuf, *kbuf;
	int i, ksiz;
PPCODE:
	pbuf = SvPV(prefix, psiz);
	keys = tchdbfwmkeys(hdb, pbuf, (int)psiz, max);
	av = newAV();
	for(i = 0; i < tclistnum(keys); i++){
	  kbuf = tclistval(keys, i, &ksiz);
	  av_push(av, newSVpvn(kbuf, ksiz));
	}
	tclistdel(keys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
hdb_addint(hdb, key, num)
	void *	hdb
	SV *	key
	int	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tchdbaddint(hdb, kbuf, (int)ksiz, num);
	if(num == INT_MIN){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSViv(num)));
	}
	XSRETURN(1);


void
hdb_adddouble(hdb, key, num)
	void *	hdb
	SV *	key
	double	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tchdbadddouble(hdb, kbuf, (int)ksiz, num);
	if(isnan(num)){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSVnv(num)));
	}
	XSRETURN(1);


int
hdb_sync(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbsync(hdb);
OUTPUT:
	RETVAL


int
hdb_optimize(hdb, bnum, apow, fpow, opts)
	void *	hdb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tchdboptimize(hdb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
hdb_vanish(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbvanish(hdb);
OUTPUT:
	RETVAL


int
hdb_copy(hdb, path)
	void *	hdb
	char *	path
CODE:
	RETVAL = tchdbcopy(hdb, path);
OUTPUT:
	RETVAL


int
hdb_tranbegin(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbtranbegin(hdb);
OUTPUT:
	RETVAL


int
hdb_trancommit(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbtrancommit(hdb);
OUTPUT:
	RETVAL


int
hdb_tranabort(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbtranabort(hdb);
OUTPUT:
	RETVAL


void
hdb_path(hdb)
	void *	hdb
PREINIT:
	const char *path;
PPCODE:
	path = tchdbpath(hdb);
	if(path){
	  XPUSHs(sv_2mortal(newSVpv(path, 0)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


double
hdb_rnum(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbrnum(hdb);
OUTPUT:
	RETVAL


double
hdb_fsiz(hdb)
	void *	hdb
CODE:
	RETVAL = tchdbfsiz(hdb);
OUTPUT:
	RETVAL



##----------------------------------------------------------------
## functions for B+ tree database
##----------------------------------------------------------------


void *
bdb_new()
PREINIT:
	TCBDB *bdb;
CODE:
	bdb = tcbdbnew();
	tcbdbsetmutex(bdb);
	RETVAL = bdb;
OUTPUT:
	RETVAL


void
bdb_del(bdb)
	void *	bdb
PREINIT:
	SV *cmp;
CODE:
	cmp = tcbdbcmpop(bdb);
	if(cmp) SvREFCNT_dec(cmp);
	tcbdbdel(bdb);


const char *
bdb_errmsg(ecode)
	int	ecode
CODE:
	RETVAL = tcbdberrmsg(ecode);
OUTPUT:
	RETVAL


int
bdb_ecode(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbecode(bdb);
OUTPUT:
	RETVAL


int
bdb_setcmpfunc(bdb, num)
	void *	bdb
	int	num
PREINIT:
	SV *ocmp;
CODE:
	ocmp = tcbdbcmpop(bdb);
	if(ocmp) SvREFCNT_dec(ocmp);
	switch(num){
	case 1: RETVAL = tcbdbsetcmpfunc(bdb, tccmpdecimal, NULL); break;
	case 2: RETVAL = tcbdbsetcmpfunc(bdb, tccmpint32, NULL); break;
	case 3: RETVAL = tcbdbsetcmpfunc(bdb, tccmpint64, NULL); break;
	default: RETVAL = tcbdbsetcmpfunc(bdb, tccmplexical, NULL); break;
	}
OUTPUT:
	RETVAL


int
bdb_setcmpfuncex(bdb, cmp)
	void *	bdb
	SV *	cmp
PREINIT:
	SV *ocmp;
CODE:
	ocmp = tcbdbcmpop(bdb);
	if(ocmp) SvREFCNT_dec(ocmp);
	RETVAL = tcbdbsetcmpfunc(bdb, (TCCMP)bdb_cmp, newSVsv(cmp));
OUTPUT:
	RETVAL


int
bdb_tune(bdb, lmemb, nmemb, bnum, apow, fpow, opts)
	void *	bdb
	int	lmemb
	int	nmemb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tcbdbtune(bdb, lmemb, nmemb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
bdb_setcache(bdb, lcnum, ncnum)
	void *	bdb
	int	lcnum
	int	ncnum
CODE:
	RETVAL = tcbdbsetcache(bdb, lcnum, ncnum);
OUTPUT:
	RETVAL


int
bdb_setxmsiz(bdb, xmsiz)
	void *	bdb
	double	xmsiz
CODE:
	RETVAL = tcbdbsetxmsiz(bdb, xmsiz);
OUTPUT:
	RETVAL


int
bdb_setdfunit(bdb, dfunit)
	void *	bdb
	int	dfunit
CODE:
	RETVAL = tcbdbsetdfunit(bdb, dfunit);
OUTPUT:
	RETVAL


int
bdb_open(bdb, path, omode)
	void *	bdb
	char *	path
	int	omode
CODE:
	RETVAL = tcbdbopen(bdb, path, omode);
OUTPUT:
	RETVAL


int
bdb_close(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbclose(bdb);
OUTPUT:
	RETVAL


int
bdb_put(bdb, key, val)
	void *	bdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcbdbput(bdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
bdb_putkeep(bdb, key, val)
	void *	bdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcbdbputkeep(bdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
bdb_putcat(bdb, key, val)
	void *	bdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcbdbputcat(bdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
bdb_putdup(bdb, key, val)
	void *	bdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcbdbputdup(bdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
bdb_putlist(bdb, key, vals)
	void *	bdb
	SV *	key
	AV *	vals
PREINIT:
	SV *val;
	TCLIST *tvals;
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
	int i, num;
CODE:
	kbuf = SvPV(key, ksiz);
	tvals = tclistnew();
	num = av_len(vals) + 1;
	for(i = 0; i < num; i++){
	  val = *av_fetch(vals, i, 0);
	  vbuf = SvPV(val, vsiz);
	  tclistpush(tvals, vbuf, (int)vsiz);
	}
	RETVAL = tcbdbputdup3(bdb, kbuf, (int)ksiz, tvals);
	tclistdel(tvals);
OUTPUT:
	RETVAL


int
bdb_out(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcbdbout(bdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
bdb_outlist(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcbdbout3(bdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


void
bdb_get(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
	char *vbuf;
	int vsiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	vbuf = tcbdbget(bdb, kbuf, (int)ksiz, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
bdb_getlist(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	AV *av;
	TCLIST *vals;
	const char *kbuf, *vbuf;
	STRLEN ksiz;
	int i, vsiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	vals = tcbdbget4(bdb, kbuf, (int)ksiz);
	if(vals){
	  av = newAV();
	  for(i = 0; i < tclistnum(vals); i++){
	    vbuf = tclistval(vals, i, &vsiz);
	    av_push(av, newSVpvn(vbuf, vsiz));
	  }
	  tclistdel(vals);
	  XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


int
bdb_vnum(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcbdbvnum(bdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
bdb_vsiz(bdb, key)
	void *	bdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcbdbvsiz(bdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


void
bdb_range(bdb, bkey, binc, ekey, einc, max)
	void *	bdb
	SV *	bkey
	int	binc
	SV *	ekey
	int	einc
	int	max
PREINIT:
	AV *av;
	TCLIST *keys;
	const char *bkbuf, *ekbuf, *kbuf;
	STRLEN bksiz, eksiz;
	int i, ksiz;
PPCODE:
	if(bkey){
	  bkbuf = SvPV(bkey, bksiz);
	} else {
	  bkbuf = NULL;
	  bksiz = -1;
	}
	if(ekey){
	  ekbuf = SvPV(ekey, eksiz);
	} else {
	  ekbuf = NULL;
	  eksiz = -1;
	}
	keys = tcbdbrange(bdb, bkbuf, (int)bksiz, binc, ekbuf, (int)eksiz, einc, max);
	av = newAV();
	for(i = 0; i < tclistnum(keys); i++){
	  kbuf = tclistval(keys, i, &ksiz);
	  av_push(av, newSVpvn(kbuf, ksiz));
	}
	tclistdel(keys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
bdb_fwmkeys(bdb, prefix, max)
	void *	bdb
	SV *	prefix
	int	max
PREINIT:
	AV *av;
	STRLEN psiz;
	TCLIST *keys;
	const char *pbuf, *kbuf;
	int i, ksiz;
PPCODE:
	pbuf = SvPV(prefix, psiz);
	keys = tcbdbfwmkeys(bdb, pbuf, (int)psiz, max);
	av = newAV();
	for(i = 0; i < tclistnum(keys); i++){
	  kbuf = tclistval(keys, i, &ksiz);
	  av_push(av, newSVpvn(kbuf, ksiz));
	}
	tclistdel(keys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
bdb_addint(bdb, key, num)
	void *	bdb
	SV *	key
	int	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcbdbaddint(bdb, kbuf, (int)ksiz, num);
	if(num == INT_MIN){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSViv(num)));
	}
	XSRETURN(1);


void
bdb_adddouble(bdb, key, num)
	void *	bdb
	SV *	key
	double	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcbdbadddouble(bdb, kbuf, (int)ksiz, num);
	if(isnan(num)){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSVnv(num)));
	}
	XSRETURN(1);


int
bdb_sync(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbsync(bdb);
OUTPUT:
	RETVAL


int
bdb_optimize(bdb, lmemb, nmemb, bnum, apow, fpow, opts)
	void *	bdb
	int	lmemb
	int	nmemb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tcbdboptimize(bdb, lmemb, nmemb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
bdb_vanish(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbvanish(bdb);
OUTPUT:
	RETVAL


int
bdb_copy(bdb, path)
	void *	bdb
	char *	path
CODE:
	RETVAL = tcbdbcopy(bdb, path);
OUTPUT:
	RETVAL


int
bdb_tranbegin(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbtranbegin(bdb);
OUTPUT:
	RETVAL


int
bdb_trancommit(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbtrancommit(bdb);
OUTPUT:
	RETVAL


int
bdb_tranabort(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbtranabort(bdb);
OUTPUT:
	RETVAL


void
bdb_path(bdb)
	void *	bdb
PREINIT:
	const char *path;
PPCODE:
	path = tcbdbpath(bdb);
	if(path){
	  XPUSHs(sv_2mortal(newSVpv(path, 0)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


double
bdb_rnum(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbrnum(bdb);
OUTPUT:
	RETVAL


double
bdb_fsiz(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbfsiz(bdb);
OUTPUT:
	RETVAL


void *
bdbcur_new(bdb)
	void *	bdb
CODE:
	RETVAL = tcbdbcurnew(bdb);
OUTPUT:
	RETVAL


void
bdbcur_del(cur)
	void *	cur
CODE:
	tcbdbcurdel(cur);


int
bdbcur_first(cur)
	void *	cur
CODE:
	RETVAL = tcbdbcurfirst(cur);
OUTPUT:
	RETVAL


int
bdbcur_last(cur)
	void *	cur
CODE:
	RETVAL = tcbdbcurlast(cur);
OUTPUT:
	RETVAL


int
bdbcur_jump(cur, key)
	void *	cur
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcbdbcurjump(cur, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
bdbcur_prev(cur)
	void *	cur
CODE:
	RETVAL = tcbdbcurprev(cur);
OUTPUT:
	RETVAL


int
bdbcur_next(cur)
	void *	cur
CODE:
	RETVAL = tcbdbcurnext(cur);
OUTPUT:
	RETVAL


int
bdbcur_put(cur, val, cpmode)
	void *	cur
	SV *	val
	int	cpmode
PREINIT:
	const char *vbuf;
	STRLEN vsiz;
CODE:
	vbuf = SvPV(val, vsiz);
	RETVAL = tcbdbcurput(cur, vbuf, (int)vsiz, cpmode);
OUTPUT:
	RETVAL


int
bdbcur_out(cur)
	void *	cur
CODE:
	RETVAL = tcbdbcurout(cur);
OUTPUT:
	RETVAL


void
bdbcur_key(cur)
	void *	cur
PREINIT:
	char *kbuf;
	int ksiz;
PPCODE:
	kbuf = tcbdbcurkey(cur, &ksiz);
	if(kbuf){
	  XPUSHs(sv_2mortal(newSVpvn(kbuf, ksiz)));
	  tcfree(kbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
bdbcur_val(cur)
	void *	cur
PREINIT:
	char *vbuf;
	int vsiz;
PPCODE:
	vbuf = tcbdbcurval(cur, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);



##----------------------------------------------------------------
## the fixed-length database API
##----------------------------------------------------------------


void *
fdb_new()
PREINIT:
	TCFDB *fdb;
CODE:
	fdb = tcfdbnew();
	tcfdbsetmutex(fdb);
	RETVAL = fdb;
OUTPUT:
	RETVAL


void
fdb_del(fdb)
	void *	fdb
CODE:
	tcfdbdel(fdb);


const char *
fdb_errmsg(ecode)
	int	ecode
CODE:
	RETVAL = tcfdberrmsg(ecode);
OUTPUT:
	RETVAL


int
fdb_ecode(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbecode(fdb);
OUTPUT:
	RETVAL


int
fdb_tune(fdb, width, limsiz)
	void *	fdb
	int	width
	double	limsiz
CODE:
	RETVAL = tcfdbtune(fdb, width, limsiz);
OUTPUT:
	RETVAL


int
fdb_open(fdb, path, omode)
	void *	fdb
	char *	path
	int	omode
CODE:
	RETVAL = tcfdbopen(fdb, path, omode);
OUTPUT:
	RETVAL


int
fdb_close(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbclose(fdb);
OUTPUT:
	RETVAL


int
fdb_put(fdb, key, val)
	void *	fdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcfdbput2(fdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
fdb_putkeep(fdb, key, val)
	void *	fdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcfdbputkeep2(fdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
fdb_putcat(fdb, key, val)
	void *	fdb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcfdbputcat2(fdb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
fdb_out(fdb, key)
	void *	fdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcfdbout2(fdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


void
fdb_get(fdb, key)
	void *	fdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
	char *vbuf;
	int vsiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	vbuf = tcfdbget2(fdb, kbuf, (int)ksiz, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


int
fdb_vsiz(fdb, key)
	void *	fdb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcfdbvsiz2(fdb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
fdb_iterinit(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbiterinit(fdb);
OUTPUT:
	RETVAL


void
fdb_iternext(fdb)
	void *	fdb
PREINIT:
	char *vbuf;
	int vsiz;
PPCODE:
	vbuf = tcfdbiternext2(fdb, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
fdb_range(fdb, interval, max)
	void *	fdb
	SV *	interval
	int	max
PREINIT:
	AV *av;
	STRLEN isiz;
	TCLIST *keys;
	const char *ibuf, *kbuf;
	int i, ksiz;
PPCODE:
	ibuf = SvPV(interval, isiz);
	keys = tcfdbrange4(fdb, ibuf, (int)isiz, max);
	av = newAV();
	for(i = 0; i < tclistnum(keys); i++){
	  kbuf = tclistval(keys, i, &ksiz);
	  av_push(av, newSVpvn(kbuf, ksiz));
	}
	tclistdel(keys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
fdb_addint(fdb, key, num)
	void *	fdb
	SV *	key
	int	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcfdbaddint(fdb, tcfdbkeytoid(kbuf, (int)ksiz), num);
	if(num == INT_MIN){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSViv(num)));
	}
	XSRETURN(1);


void
fdb_adddouble(fdb, key, num)
	void *	fdb
	SV *	key
	double	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcfdbadddouble(fdb, tcfdbkeytoid(kbuf, (int)ksiz), num);
	if(isnan(num)){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSVnv(num)));
	}
	XSRETURN(1);


int
fdb_sync(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbsync(fdb);
OUTPUT:
	RETVAL


int
fdb_optimize(fdb, width, limsiz)
	void *	fdb
	int	width
	double	limsiz
CODE:
	RETVAL = tcfdboptimize(fdb, width, limsiz);
OUTPUT:
	RETVAL


int
fdb_vanish(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbvanish(fdb);
OUTPUT:
	RETVAL


int
fdb_copy(fdb, path)
	void *	fdb
	char *	path
CODE:
	RETVAL = tcfdbcopy(fdb, path);
OUTPUT:
	RETVAL


int
fdb_tranbegin(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbtranbegin(fdb);
OUTPUT:
	RETVAL


int
fdb_trancommit(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbtrancommit(fdb);
OUTPUT:
	RETVAL


int
fdb_tranabort(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbtranabort(fdb);
OUTPUT:
	RETVAL


void
fdb_path(fdb)
	void *	fdb
PREINIT:
	const char *path;
PPCODE:
	path = tcfdbpath(fdb);
	if(path){
	  XPUSHs(sv_2mortal(newSVpv(path, 0)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


double
fdb_rnum(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbrnum(fdb);
OUTPUT:
	RETVAL


double
fdb_fsiz(fdb)
	void *	fdb
CODE:
	RETVAL = tcfdbfsiz(fdb);
OUTPUT:
	RETVAL



##----------------------------------------------------------------
## the table database API
##----------------------------------------------------------------


void *
tdb_new()
PREINIT:
	TCTDB *tdb;
CODE:
	tdb = tctdbnew();
	tctdbsetmutex(tdb);
	RETVAL = tdb;
OUTPUT:
	RETVAL


void
tdb_del(tdb)
	void *	tdb
CODE:
	tctdbdel(tdb);


const char *
tdb_errmsg(ecode)
	int	ecode
CODE:
	RETVAL = tctdberrmsg(ecode);
OUTPUT:
	RETVAL


int
tdb_ecode(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbecode(tdb);
OUTPUT:
	RETVAL


int
tdb_tune(tdb, bnum, apow, fpow, opts)
	void *	tdb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tctdbtune(tdb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
tdb_setcache(tdb, rcnum, lcnum, ncnum)
	void *	tdb
	int	rcnum
	int	lcnum
	int	ncnum
CODE:
	RETVAL = tctdbsetcache(tdb, rcnum, lcnum, ncnum);
OUTPUT:
	RETVAL


int
tdb_setxmsiz(tdb, xmsiz)
	void *	tdb
	double	xmsiz
CODE:
	RETVAL = tctdbsetxmsiz(tdb, xmsiz);
OUTPUT:
	RETVAL


int
tdb_setdfunit(tdb, dfunit)
	void *	tdb
	int	dfunit
CODE:
	RETVAL = tctdbsetdfunit(tdb, dfunit);
OUTPUT:
	RETVAL


int
tdb_open(tdb, path, omode)
	void *	tdb
	char *	path
	int	omode
CODE:
	RETVAL = tctdbopen(tdb, path, omode);
OUTPUT:
	RETVAL


int
tdb_close(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbclose(tdb);
OUTPUT:
	RETVAL


int
tdb_put(tdb, pkey, cols)
	void *	tdb
	SV *	pkey
	HV *	cols
PREINIT:
	SV *sv;
	const char *pkbuf;
	char *kbuf, *vbuf;
	STRLEN pksiz, vsiz;
	I32 ksiz;
	TCMAP *tcols;
CODE:
	pkbuf = SvPV(pkey, pksiz);
	tcols = tcmapnew2(31);
	hv_iterinit(cols);
	while((sv = hv_iternextsv(cols, &kbuf, &ksiz)) != NULL){
	  vbuf = SvPV(sv, vsiz);
	  tcmapput(tcols, kbuf, ksiz, vbuf, vsiz);
	}
	RETVAL = tctdbput(tdb, pkbuf, pksiz, tcols);
	tcmapdel(tcols);
OUTPUT:
	RETVAL


int
tdb_putkeep(tdb, pkey, cols)
	void *	tdb
	SV *	pkey
	HV *	cols
PREINIT:
	SV *sv;
	const char *pkbuf;
	char *kbuf, *vbuf;
	STRLEN pksiz, vsiz;
	I32 ksiz;
	TCMAP *tcols;
CODE:
	pkbuf = SvPV(pkey, pksiz);
	tcols = tcmapnew2(31);
	hv_iterinit(cols);
	while((sv = hv_iternextsv(cols, &kbuf, &ksiz)) != NULL){
	  vbuf = SvPV(sv, vsiz);
	  tcmapput(tcols, kbuf, ksiz, vbuf, vsiz);
	}
	RETVAL = tctdbputkeep(tdb, pkbuf, pksiz, tcols);
	tcmapdel(tcols);
OUTPUT:
	RETVAL


int
tdb_putcat(tdb, pkey, cols)
	void *	tdb
	SV *	pkey
	HV *	cols
PREINIT:
	SV *sv;
	const char *pkbuf;
	char *kbuf, *vbuf;
	STRLEN pksiz, vsiz;
	I32 ksiz;
	TCMAP *tcols;
CODE:
	pkbuf = SvPV(pkey, pksiz);
	tcols = tcmapnew2(31);
	hv_iterinit(cols);
	while((sv = hv_iternextsv(cols, &kbuf, &ksiz)) != NULL){
	  vbuf = SvPV(sv, vsiz);
	  tcmapput(tcols, kbuf, ksiz, vbuf, vsiz);
	}
	RETVAL = tctdbputcat(tdb, pkbuf, pksiz, tcols);
	tcmapdel(tcols);
OUTPUT:
	RETVAL


int
tdb_out(tdb, pkey)
	void *	tdb
	SV *	pkey
PREINIT:
	const char *pkbuf;
	STRLEN pksiz;
CODE:
	pkbuf = SvPV(pkey, pksiz);
	RETVAL = tctdbout(tdb, pkbuf, (int)pksiz);
OUTPUT:
	RETVAL


void
tdb_get(tdb, pkey)
	void *	tdb
	SV *	pkey
PREINIT:
	const char *pkbuf, *kbuf, *vbuf;
	STRLEN pksiz;
	int ksiz, vsiz;
	TCMAP *tcols;
	HV *cols;
PPCODE:
	pkbuf = SvPV(pkey, pksiz);
	tcols = tctdbget(tdb, pkbuf, (int)pksiz);
	if(tcols){
	  cols = newHV();
	  tcmapiterinit(tcols);
	  while((kbuf = tcmapiternext(tcols, &ksiz)) != NULL){
	    vbuf = tcmapiterval(kbuf, &vsiz);
	    hv_store(cols, kbuf, ksiz, newSVpvn(vbuf, vsiz), 0);
	  }
	  tcmapdel(tcols);
	  XPUSHs(sv_2mortal(newRV_noinc((SV *)cols)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


int
tdb_vsiz(tdb, pkey)
	void *	tdb
	SV *	pkey
PREINIT:
	const char *pkbuf;
	STRLEN pksiz;
CODE:
	pkbuf = SvPV(pkey, pksiz);
	RETVAL = tctdbvsiz(tdb, pkbuf, (int)pksiz);
OUTPUT:
	RETVAL


int
tdb_iterinit(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbiterinit(tdb);
OUTPUT:
	RETVAL


void
tdb_iternext(tdb)
	void *	tdb
PREINIT:
	char *vbuf;
	int vsiz;
PPCODE:
	vbuf = tctdbiternext(tdb, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
tdb_fwmkeys(tdb, prefix, max)
	void *	tdb
	SV *	prefix
	int	max
PREINIT:
	AV *av;
	STRLEN psiz;
	TCLIST *pkeys;
	const char *pbuf, *pkbuf;
	int i, pksiz;
PPCODE:
	pbuf = SvPV(prefix, psiz);
	pkeys = tctdbfwmkeys(tdb, pbuf, (int)psiz, max);
	av = newAV();
	for(i = 0; i < tclistnum(pkeys); i++){
	  pkbuf = tclistval(pkeys, i, &pksiz);
	  av_push(av, newSVpvn(pkbuf, pksiz));
	}
	tclistdel(pkeys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
tdb_addint(tdb, pkey, num)
	void *	tdb
	SV *	pkey
	int	num
PREINIT:
	const char *pkbuf;
	STRLEN pksiz;
PPCODE:
	pkbuf = SvPV(pkey, pksiz);
	num = tctdbaddint(tdb, pkbuf, (int)pksiz, num);
	if(num == INT_MIN){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSViv(num)));
	}
	XSRETURN(1);


void
tdb_adddouble(tdb, pkey, num)
	void *	tdb
	SV *	pkey
	double	num
PREINIT:
	const char *pkbuf;
	STRLEN pksiz;
PPCODE:
	pkbuf = SvPV(pkey, pksiz);
	num = tctdbadddouble(tdb, pkbuf, (int)pksiz, num);
	if(isnan(num)){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSVnv(num)));
	}
	XSRETURN(1);


int
tdb_sync(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbsync(tdb);
OUTPUT:
	RETVAL


int
tdb_optimize(tdb, bnum, apow, fpow, opts)
	void *	tdb
	double	bnum
	int	apow
	int	fpow
	int	opts
CODE:
	RETVAL = tctdboptimize(tdb, bnum, apow, fpow, opts);
OUTPUT:
	RETVAL


int
tdb_vanish(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbvanish(tdb);
OUTPUT:
	RETVAL


int
tdb_copy(tdb, path)
	void *	tdb
	char *	path
CODE:
	RETVAL = tctdbcopy(tdb, path);
OUTPUT:
	RETVAL


int
tdb_tranbegin(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbtranbegin(tdb);
OUTPUT:
	RETVAL


int
tdb_trancommit(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbtrancommit(tdb);
OUTPUT:
	RETVAL


int
tdb_tranabort(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbtranabort(tdb);
OUTPUT:
	RETVAL


void
tdb_path(tdb)
	void *	tdb
PREINIT:
	const char *path;
PPCODE:
	path = tctdbpath(tdb);
	if(path){
	  XPUSHs(sv_2mortal(newSVpv(path, 0)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


double
tdb_rnum(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbrnum(tdb);
OUTPUT:
	RETVAL


double
tdb_fsiz(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbfsiz(tdb);
OUTPUT:
	RETVAL


int
tdb_setindex(tdb, name, type)
	void *	tdb
	char *	name
	int	type
CODE:
	RETVAL = tctdbsetindex(tdb, name, type);
OUTPUT:
	RETVAL


double
tdb_genuid(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbgenuid(tdb);
OUTPUT:
	RETVAL


void *
tdbqry_new(tdb)
	void *	tdb
CODE:
	RETVAL = tctdbqrynew(tdb);
OUTPUT:
	RETVAL


void
tdbqry_del(qry)
	void *	qry
CODE:
	tctdbqrydel(qry);


void
tdbqry_addcond(qry, name, op, expr)
	void *	qry
	char *	name
	int	op
	char *	expr
CODE:
	tctdbqryaddcond(qry, name, op, expr);


void
tdbqry_setorder(qry, name, type)
	void *	qry
	char *	name
	int	type
CODE:
	tctdbqrysetorder(qry, name, type);


void
tdbqry_setlimit(qry, max, skip)
	void *	qry
	int	max
	int	skip
CODE:
	tctdbqrysetlimit(qry, max, skip);


AV *
tdbqry_search(qry)
	void *	qry
PREINIT:
	AV *av;
	TCLIST *pkeys;
	const char *pkbuf;
	int i, pksiz;
CODE:
	pkeys = tctdbqrysearch(qry);
	av = newAV();
	for(i = 0; i < tclistnum(pkeys); i++){
	  pkbuf = tclistval(pkeys, i, &pksiz);
	  av_push(av, newSVpvn(pkbuf, pksiz));
	}
	tclistdel(pkeys);
	RETVAL = (AV *)sv_2mortal((SV *)av);
OUTPUT:
	RETVAL


int
tdbqry_searchout(qry)
	void *	qry
CODE:
	RETVAL = tctdbqrysearchout(qry);
OUTPUT:
	RETVAL


int
tdbqry_proc(qry, proc)
	void *	qry
	SV *	proc
CODE:
	RETVAL = tctdbqryproc(qry, (TDBQRYPROC)tdbqry_proc, proc);
OUTPUT:
	RETVAL


char *
tdbqry_hint(qry)
	void *	qry
PREINIT:
	const char *hint;
CODE:
	RETVAL = (char *)tctdbqryhint(qry);
OUTPUT:
	RETVAL


AV *
tdbqry_metasearch(qry, others, type)
	void *	qry
	AV *	others
	int	type
PREINIT:
	SV *rqry;
	AV *av;
	TDBQRY **qrys, *tqry;
	TCLIST *pkeys;
	const char *pkbuf;
	int i, num, qnum, pksiz;
CODE:
	num = av_len(others) + 1;
	qrys = tcmalloc(sizeof(*qrys) * (num + 1));
	qnum = 0;
	qrys[qnum++] = qry;
	for(i = 0; i < num; i++){
	  rqry = *av_fetch(others, i, 0);
	  if(sv_isobject(rqry) && sv_isa(rqry, "TokyoCabinet::TDBQRY")){
	    qrys[qnum++] = (TDBQRY *)SvIV(*av_fetch((AV *)SvRV(rqry), 0, 0));
	  }
	}
	pkeys = tctdbmetasearch(qrys, qnum, type);
	tcfree(qrys);
	av = newAV();
	for(i = 0; i < tclistnum(pkeys); i++){
	  pkbuf = tclistval(pkeys, i, &pksiz);
	  av_push(av, newSVpvn(pkbuf, pksiz));
	}
	tclistdel(pkeys);
	RETVAL = (AV *)sv_2mortal((SV *)av);
OUTPUT:
	RETVAL


AV *
tdbqry_kwic(qry, cols, name, width, opts)
	void *	qry
	HV *	cols
	char *	name
	int	width
	int	opts
PREINIT:
	SV *sv, **svp;
	AV *av;
	char *kbuf, *vbuf;
	const char *tbuf;
	STRLEN pksiz, vsiz;
	I32 ksiz;
	int i, tsiz;
	TCMAP *tcols;
	TCLIST *texts;
CODE:
	tcols = tcmapnew2(31);
	if(!strcmp(name, "[[undef]]")){
	  hv_iterinit(cols);
	  while((sv = hv_iternextsv(cols, &kbuf, &ksiz)) != NULL){
	    vbuf = SvPV(sv, vsiz);
	    tcmapput(tcols, kbuf, ksiz, vbuf, vsiz);
	  }
	  name = NULL;
	} else {
	  svp = hv_fetch(cols, name, strlen(name), 0);
	  if(svp){
	    vbuf = SvPV(*svp, vsiz);
	    tcmapput(tcols, name, strlen(name), vbuf, vsiz);
	  }
	}
	texts = tctdbqrykwic(qry, tcols, name, width, opts);
	av = newAV();
	for(i = 0; i < tclistnum(texts); i++){
	  tbuf = tclistval(texts, i, &tsiz);
	  av_push(av, newSVpvn(tbuf, tsiz));
	}
	tclistdel(texts);
	tcmapdel(tcols);
	RETVAL = (AV *)sv_2mortal((SV *)av);
OUTPUT:
	RETVAL



##----------------------------------------------------------------
## the abstract database API
##----------------------------------------------------------------


void *
adb_new()
PREINIT:
	TCADB *adb;
CODE:
	adb = tcadbnew();
	RETVAL = adb;
OUTPUT:
	RETVAL


void
adb_del(adb)
	void *	adb
CODE:
	tcadbdel(adb);


int
adb_open(adb, name)
	void *	adb
	char *	name
CODE:
	RETVAL = tcadbopen(adb, name);
OUTPUT:
	RETVAL


int
adb_close(adb)
	void *	adb
CODE:
	RETVAL = tcadbclose(adb);
OUTPUT:
	RETVAL


int
adb_put(adb, key, val)
	void *	adb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcadbput(adb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
adb_putkeep(adb, key, val)
	void *	adb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcadbputkeep(adb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
adb_putcat(adb, key, val)
	void *	adb
	SV *	key
	SV *	val
PREINIT:
	const char *kbuf, *vbuf;
	STRLEN ksiz, vsiz;
CODE:
	kbuf = SvPV(key, ksiz);
	vbuf = SvPV(val, vsiz);
	RETVAL = tcadbputcat(adb, kbuf, (int)ksiz, vbuf, (int)vsiz);
OUTPUT:
	RETVAL


int
adb_out(adb, key)
	void *	adb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcadbout(adb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


void
adb_get(adb, key)
	void *	adb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
	char *vbuf;
	int vsiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	vbuf = tcadbget(adb, kbuf, (int)ksiz, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


int
adb_vsiz(adb, key)
	void *	adb
	SV *	key
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
CODE:
	kbuf = SvPV(key, ksiz);
	RETVAL = tcadbvsiz(adb, kbuf, (int)ksiz);
OUTPUT:
	RETVAL


int
adb_iterinit(adb)
	void *	adb
CODE:
	RETVAL = tcadbiterinit(adb);
OUTPUT:
	RETVAL


void
adb_iternext(adb)
	void *	adb
PREINIT:
	char *vbuf;
	int vsiz;
PPCODE:
	vbuf = tcadbiternext(adb, &vsiz);
	if(vbuf){
	  XPUSHs(sv_2mortal(newSVpvn(vbuf, vsiz)));
	  tcfree(vbuf);
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


void
adb_fwmkeys(adb, prefix, max)
	void *	adb
	SV *	prefix
	int	max
PREINIT:
	AV *av;
	STRLEN psiz;
	TCLIST *keys;
	const char *pbuf, *kbuf;
	int i, ksiz;
PPCODE:
	pbuf = SvPV(prefix, psiz);
	keys = tcadbfwmkeys(adb, pbuf, (int)psiz, max);
	av = newAV();
	for(i = 0; i < tclistnum(keys); i++){
	  kbuf = tclistval(keys, i, &ksiz);
	  av_push(av, newSVpvn(kbuf, ksiz));
	}
	tclistdel(keys);
	XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	XSRETURN(1);


void
adb_addint(adb, key, num)
	void *	adb
	SV *	key
	int	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcadbaddint(adb, kbuf, (int)ksiz, num);
	if(num == INT_MIN){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSViv(num)));
	}
	XSRETURN(1);


void
adb_adddouble(adb, key, num)
	void *	adb
	SV *	key
	double	num
PREINIT:
	const char *kbuf;
	STRLEN ksiz;
PPCODE:
	kbuf = SvPV(key, ksiz);
	num = tcadbadddouble(adb, kbuf, (int)ksiz, num);
	if(isnan(num)){
	  XPUSHs((SV *)&PL_sv_undef);
	} else {
	  XPUSHs(sv_2mortal(newSVnv(num)));
	}
	XSRETURN(1);


int
adb_sync(adb)
	void *	adb
CODE:
	RETVAL = tcadbsync(adb);
OUTPUT:
	RETVAL


int
adb_optimize(adb, params)
	void *	adb
	char *	params
CODE:
	RETVAL = tcadboptimize(adb, params);
OUTPUT:
	RETVAL


int
adb_vanish(adb)
	void *	adb
CODE:
	RETVAL = tcadbvanish(adb);
OUTPUT:
	RETVAL


int
adb_copy(adb, path)
	void *	adb
	char *	path
CODE:
	RETVAL = tcadbcopy(adb, path);
OUTPUT:
	RETVAL


int
adb_tranbegin(adb)
	void *	adb
CODE:
	RETVAL = tcadbtranbegin(adb);
OUTPUT:
	RETVAL


int
adb_trancommit(adb)
	void *	adb
CODE:
	RETVAL = tcadbtrancommit(adb);
OUTPUT:
	RETVAL


int
adb_tranabort(adb)
	void *	adb
CODE:
	RETVAL = tcadbtranabort(adb);
OUTPUT:
	RETVAL


void
adb_path(adb)
	void *	adb
PREINIT:
	const char *path;
PPCODE:
	path = tcadbpath(adb);
	if(path){
	  XPUSHs(sv_2mortal(newSVpv(path, 0)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);


double
adb_rnum(adb)
	void *	adb
CODE:
	RETVAL = tcadbrnum(adb);
OUTPUT:
	RETVAL


double
adb_size(adb)
	void *	adb
CODE:
	RETVAL = tcadbsize(adb);
OUTPUT:
	RETVAL


void
adb_misc(adb, name, args)
	void *	adb
	char *	name
	AV *	args
PREINIT:
	SV *arg;
	AV *av;
	TCLIST *targs, *res;
	const char *abuf, *rbuf;
	STRLEN asiz;
	int i, num, rsiz;
PPCODE:
	targs = tclistnew();
	num = av_len(args) + 1;
	for(i = 0; i < num; i++){
	  arg = *av_fetch(args, i, 0);
	  abuf = SvPV(arg, asiz);
	  tclistpush(targs, abuf, (int)asiz);
	}
	res = tcadbmisc(adb, name, targs);
	tclistdel(targs);
	if(res){
	  av = newAV();
	  for(i = 0; i < tclistnum(res); i++){
	    rbuf = tclistval(res, i, &rsiz);
	    av_push(av, newSVpvn(rbuf, rsiz));
	  }
	  tclistdel(res);
	  XPUSHs(sv_2mortal(newRV_noinc((SV *)av)));
	} else {
	  XPUSHs((SV *)&PL_sv_undef);
	}
	XSRETURN(1);



## END OF FILE
