/*
 * pbpack - pack one or more PlayStation discs into a single multi-disc
 *          EBOOT-style .pbp file.
 *
 * The output targets emulators, not a real PSP: it is the layout that
 * PCSX-ReARMed (libpcsxcore/cdriso.c: handlepbp), DuckStation/SwanStation
 * (cd_image_pbp.cpp) and Beetle PSX read.  No DATA.PSP is embedded.
 *
 *   PBP header (0x28)          "\0PBP", version, 8 section offsets
 *   PARAM.SFO                  BOOTABLE=1, CATEGORY="ME", DISC_ID, TITLE, ...
 *   DATA.PSAR (64 KiB aligned)
 *     1 disc : PSISOIMG0000 block
 *     2+ disc: "PSTITLEIMG000000", u32 offsets[5] at +0x200 (relative to
 *              DATA.PSAR, 0 terminated), then one PSISOIMG0000 per disc
 *   PSISOIMG0000 block
 *     +0x000   magic, +0x00c u32 end of data (relative to block)
 *     +0x400   "_SCUS_94163" style disc id
 *     +0x800   TOC, 10 byte entries: A0, A1, A2, track 1..n
 *     +0xbfc   u32 0x100000 (start of compressed data)
 *     +0x4000  index, 32 byte entries: u32 offset, u16 size, ... (0x100000)
 *     +0x100000 data: 16 raw sectors (37632 bytes) per block, each block a
 *              raw deflate stream (PCSX-ReARMed inflates every block)
 *
 * Inputs: .cue (single or multiple BINARY files), or raw 2352-byte sector
 * images (.bin/.img).  Compression runs on all CPU cores.
 */

#define _FILE_OFFSET_BITS 64
#define _LARGEFILE64_SOURCE

#include <ctype.h>
#include <errno.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

#ifdef _WIN32
#include <windows.h>
#define fseek64 _fseeki64
#define ftell64 _ftelli64
#define PATH_SEP_STR "\\"
#else
#include <dirent.h>
#include <unistd.h>
#define fseek64 fseeko
#define ftell64 ftello
#define PATH_SEP_STR "/"
#endif

#define PBPACK_VERSION "1.0"

#define SECTOR_RAW 2352
#define BLOCK_SECTORS 16
#define BLOCK_RAW (SECTOR_RAW * BLOCK_SECTORS) /* 0x9300 */
#define ISO_HDR_SIZE 0x100000
#define ISO_INDEX_OFF 0x4000
#define ISO_INDEX_MAX ((ISO_HDR_SIZE - ISO_INDEX_OFF) / 32)
#define MAX_DISCS 5
#define MAX_FILES 99
#define MAX_TRACKS 99
#define PSAR_ALIGN 0x10000
#define DISC_ALIGN 0x8000

typedef struct {
	int number;
	int audio;
	uint32_t file_lba; /* INDEX 01 position in the concatenated image */
} track_t;

typedef struct {
	char *path;
	int nfiles;
	char *files[MAX_FILES];
	uint64_t fsize[MAX_FILES];
	int ntracks;
	track_t tracks[MAX_TRACKS];
	uint32_t sectors;
	char id[16];   /* "SCUS94163" */
	char label[33];
	/* sequential reader state */
	FILE *fp;
	int cur_file;
} disc_t;

static int quiet;

static void die(const char *fmt, ...)
{
	va_list ap;
	va_start(ap, fmt);
	fprintf(stderr, "ERROR: ");
	vfprintf(stderr, fmt, ap);
	fprintf(stderr, "\n");
	va_end(ap);
	exit(1);
}

static void info(const char *fmt, ...)
{
	va_list ap;
	if (quiet)
		return;
	va_start(ap, fmt);
	vprintf(fmt, ap);
	va_end(ap);
	fflush(stdout);
}

static void *xcalloc(size_t n, size_t sz)
{
	void *p = calloc(n, sz);
	if (!p)
		die("sin memoria");
	return p;
}

static char *xstrdup(const char *s)
{
	char *p = strdup(s);
	if (!p)
		die("sin memoria");
	return p;
}

static void put_le32(uint8_t *p, uint32_t v)
{
	p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24;
}

static void put_le16(uint8_t *p, uint16_t v)
{
	p[0] = v; p[1] = v >> 8;
}

static uint32_t get_le32(const uint8_t *p)
{
	return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
}

static uint8_t bcd(unsigned v)
{
	return (uint8_t)(((v / 10) << 4) | (v % 10));
}

static void lba_to_bcd_msf(uint32_t lba, uint8_t *msf)
{
	msf[0] = bcd(lba / 75 / 60);
	msf[1] = bcd(lba / 75 % 60);
	msf[2] = bcd(lba % 75);
}

static const char *path_basename(const char *p)
{
	const char *b = p;
	for (; *p; p++)
		if (*p == '/' || *p == '\\')
			b = p + 1;
	return b;
}

static char *path_dirname(const char *p)
{
	const char *b = path_basename(p);
	size_t n = b - p;
	char *d = xcalloc(n + 2, 1);
	if (n == 0)
		strcpy(d, ".");
	else
		memcpy(d, p, n - 1);
	if (d[0] == '\0')
		strcpy(d, PATH_SEP_STR);
	return d;
}

static int has_ext(const char *p, const char *ext)
{
	size_t lp = strlen(p), le = strlen(ext);
	return lp >= le && strcasecmp(p + lp - le, ext) == 0;
}

static int file_size(const char *path, uint64_t *size)
{
	FILE *f = fopen(path, "rb");
	if (!f)
		return -1;
	fseek64(f, 0, SEEK_END);
	*size = (uint64_t)ftell64(f);
	fclose(f);
	return 0;
}

/* cue sheets often disagree with the real file name's case */
static char *resolve_file(const char *dir, const char *name)
{
	char *full = xcalloc(strlen(dir) + strlen(name) + 2, 1);
	uint64_t sz;

	sprintf(full, "%s" PATH_SEP_STR "%s", dir, name);
	if (file_size(full, &sz) == 0)
		return full;
#ifndef _WIN32
	{
		DIR *d = opendir(dir);
		struct dirent *de;
		if (d) {
			while ((de = readdir(d)) != NULL) {
				if (strcasecmp(de->d_name, path_basename(name)) == 0) {
					free(full);
					full = xcalloc(strlen(dir) + strlen(de->d_name) + 2, 1);
					sprintf(full, "%s/%s", dir, de->d_name);
					closedir(d);
					return full;
				}
			}
			closedir(d);
		}
	}
#endif
	return full;
}

static int parse_msf(const char *s, uint32_t *lba)
{
	unsigned m, sec, f;
	if (sscanf(s, "%u:%u:%u", &m, &sec, &f) != 3)
		return -1;
	*lba = (m * 60 + sec) * 75 + f;
	return 0;
}

static void parse_cue(disc_t *d)
{
	FILE *f = fopen(d->path, "r");
	char line[1024], *dir;
	uint64_t file_base = 0; /* sectors before the current FILE */
	int cur = -1;

	if (!f)
		die("no se pudo abrir %s: %s", d->path, strerror(errno));
	dir = path_dirname(d->path);

	while (fgets(line, sizeof(line), f)) {
		char *p = line, *q;
		while (isspace((unsigned char)*p))
			p++;
		if (strncasecmp(p, "FILE", 4) == 0 && isspace((unsigned char)p[4])) {
			char name[1024];
			p += 4;
			while (isspace((unsigned char)*p))
				p++;
			if (*p == '"') {
				q = strchr(++p, '"');
				if (!q)
					die("linea FILE invalida en %s", d->path);
			} else {
				q = p;
				while (*q && !isspace((unsigned char)*q))
					q++;
			}
			snprintf(name, sizeof(name), "%.*s", (int)(q - p), p);
			if (d->nfiles >= MAX_FILES)
				die("demasiados archivos en %s", d->path);
			if (cur >= 0)
				file_base += d->fsize[cur] / SECTOR_RAW;
			cur = d->nfiles++;
			d->files[cur] = resolve_file(dir, name);
			if (file_size(d->files[cur], &d->fsize[cur]) != 0)
				die("no se encuentra '%s' (referenciado en %s)", d->files[cur], d->path);
			if (d->fsize[cur] % SECTOR_RAW)
				info("  aviso: %s no es multiplo de 2352 bytes\n", d->files[cur]);
		} else if (strncasecmp(p, "TRACK", 5) == 0) {
			int num;
			char mode[32];
			if (sscanf(p + 5, "%d %31s", &num, mode) != 2)
				die("linea TRACK invalida en %s", d->path);
			if (cur < 0)
				die("TRACK antes de FILE en %s", d->path);
			if (d->ntracks >= MAX_TRACKS)
				die("demasiadas pistas en %s", d->path);
			if (strcasecmp(mode, "AUDIO") != 0 && !strstr(mode, "2352"))
				die("%s: pista %d es %s; solo se aceptan imagenes de 2352 bytes por sector "
				    "(BIN/CUE de un ripeo completo, no ISO de 2048)", d->path, num, mode);
			d->tracks[d->ntracks].number = num;
			d->tracks[d->ntracks].audio = strcasecmp(mode, "AUDIO") == 0;
			d->tracks[d->ntracks].file_lba = (uint32_t)-1;
			d->ntracks++;
		} else if (strncasecmp(p, "INDEX", 5) == 0) {
			int idx;
			char msf[32];
			uint32_t lba;
			if (sscanf(p + 5, "%d %31s", &idx, msf) != 2 || parse_msf(msf, &lba) != 0)
				die("linea INDEX invalida en %s", d->path);
			if (idx == 1 && d->ntracks > 0)
				d->tracks[d->ntracks - 1].file_lba = (uint32_t)(file_base + lba);
		} else if (strncasecmp(p, "PREGAP", 6) == 0) {
			info("  aviso: PREGAP no incluido en el BIN (%s); se ignora\n", d->path);
		}
	}
	fclose(f);
	free(dir);

	if (d->nfiles == 0 || d->ntracks == 0)
		die("%s no tiene pistas", d->path);
	for (int i = 0; i < d->ntracks; i++)
		if (d->tracks[i].file_lba == (uint32_t)-1)
			die("%s: la pista %d no tiene INDEX 01", d->path, d->tracks[i].number);
	if (d->tracks[0].audio)
		die("%s: la primera pista no es de datos; no parece un disco de PlayStation", d->path);
}

static void open_disc(disc_t *d, const char *path)
{
	uint64_t total = 0;

	memset(d, 0, sizeof(*d));
	d->path = xstrdup(path);
	if (has_ext(path, ".cue")) {
		parse_cue(d);
	} else if (has_ext(path, ".bin") || has_ext(path, ".img")) {
		d->nfiles = 1;
		d->files[0] = xstrdup(path);
		if (file_size(path, &d->fsize[0]) != 0)
			die("no se pudo abrir %s", path);
		d->ntracks = 1;
		d->tracks[0].number = 1;
		d->tracks[0].file_lba = 0;
	} else {
		die("%s: formato no soportado (usar .cue, .bin o .img)", path);
	}
	for (int i = 0; i < d->nfiles; i++)
		total += d->fsize[i] / SECTOR_RAW;
	if (total == 0 || total > (uint64_t)ISO_INDEX_MAX * BLOCK_SECTORS)
		die("%s: tamanio de imagen invalido", path);
	d->sectors = (uint32_t)total;
	d->cur_file = -1;
}

/* random access read of one raw sector, used for disc id detection */
static int read_sector_at(disc_t *d, uint32_t lba, uint8_t *buf)
{
	uint64_t base = 0;
	for (int i = 0; i < d->nfiles; i++) {
		uint64_t n = d->fsize[i] / SECTOR_RAW;
		if (lba < base + n) {
			FILE *f = fopen(d->files[i], "rb");
			int ok;
			if (!f)
				return -1;
			fseek64(f, (int64_t)(lba - base) * SECTOR_RAW, SEEK_SET);
			ok = fread(buf, 1, SECTOR_RAW, f) == SECTOR_RAW;
			fclose(f);
			return ok ? 0 : -1;
		}
		base += n;
	}
	return -1;
}

static void check_raw(disc_t *d)
{
	static const uint8_t sync[12] = { 0, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0 };
	uint8_t raw[SECTOR_RAW];

	if (read_sector_at(d, 16, raw) == 0 && memcmp(raw, sync, 12) == 0)
		return;
	if (d->fsize[0] % SECTOR_RAW != 0 && d->fsize[0] % 2048 == 0)
		die("%s parece una imagen ISO de 2048 bytes por sector; hace falta el BIN "
		    "crudo de 2352 bytes (el que sale con su .cue)", d->files[0]);
	die("%s no parece una imagen BIN cruda de PlayStation (2352 bytes por sector)", d->files[0]);
}

/* user data of a mode 1 or mode 2 form 1 sector */
static const uint8_t *user_data(const uint8_t *raw)
{
	return raw[15] == 2 ? raw + 24 : raw + 16;
}

static int iso_find_file(disc_t *d, uint32_t dir_lba, uint32_t dir_size, const char *want,
			 uint32_t *out_lba, uint32_t *out_size)
{
	uint8_t raw[SECTOR_RAW];
	uint32_t nsec = (dir_size + 2047) / 2048;

	for (uint32_t s = 0; s < nsec && s < 64; s++) {
		const uint8_t *ud;
		uint32_t pos = 0;
		if (read_sector_at(d, dir_lba + s, raw) != 0)
			return -1;
		ud = user_data(raw);
		while (pos < 2048) {
			uint8_t len = ud[pos], nlen;
			char name[256];
			if (len == 0)
				break;
			if (pos + len > 2048 || len < 34)
				break;
			nlen = ud[pos + 32];
			if (33 + nlen > len)
				break;
			memcpy(name, ud + pos + 33, nlen);
			name[nlen] = '\0';
			{
				char *semi = strchr(name, ';');
				if (semi)
					*semi = '\0';
			}
			if (strcasecmp(name, want) == 0) {
				*out_lba = get_le32(ud + pos + 2);
				*out_size = get_le32(ud + pos + 10);
				return 0;
			}
			pos += len;
		}
	}
	return -1;
}

/*
 * Walk the ISO9660 tree and return the first sector past the end of the
 * last file or directory.  An image shorter than that is cut off (or a
 * trimmed "rip"): the game reads past the end and hangs on a black screen.
 * Also returns the volume size the disc declares in its PVD.
 */
static uint32_t iso_needed_sectors(disc_t *d, uint32_t *vol_size)
{
	enum { MAX_DIRS = 4096 };
	static uint32_t q_lba[MAX_DIRS], q_size[MAX_DIRS];
	uint8_t raw[SECTOR_RAW];
	const uint8_t *ud;
	uint32_t need = 0, n = 0;

	*vol_size = 0;
	if (read_sector_at(d, 16, raw) != 0)
		return 0;
	ud = user_data(raw);
	if (ud[0] != 1 || memcmp(ud + 1, "CD001", 5) != 0)
		return 0;
	*vol_size = get_le32(ud + 80);
	q_lba[n] = get_le32(ud + 156 + 2);
	q_size[n++] = get_le32(ud + 156 + 10);

	for (uint32_t i = 0; i < n; i++) {
		uint32_t nsec = (q_size[i] + 2047) / 2048;
		if (q_lba[i] + nsec > need)
			need = q_lba[i] + nsec;
		for (uint32_t s = 0; s < nsec && s < 256; s++) {
			uint32_t pos = 0;
			if (read_sector_at(d, q_lba[i] + s, raw) != 0)
				break;
			ud = user_data(raw);
			while (pos + 34 <= 2048) {
				uint8_t len = ud[pos], nlen = ud[pos + 32];
				uint32_t lba, size, end;
				if (len < 34 || pos + len > 2048 || 33 + nlen > len)
					break;
				lba = get_le32(ud + pos + 2);
				size = get_le32(ud + pos + 10);
				end = lba + (size + 2047) / 2048;
				/* "." and ".." are 1-byte names 0x00 / 0x01 */
				if (!(nlen == 1 && ud[pos + 33] <= 1)) {
					if (end > need)
						need = end;
					if (ud[pos + 25] & 2) {
						uint32_t k;
						for (k = 0; k < n && q_lba[k] != lba; k++)
							;
						if (k == n && n < MAX_DIRS) {
							q_lba[n] = lba;
							q_size[n++] = size;
						}
					}
				}
				pos += len;
			}
		}
	}
	return need;
}

/* "BOOT = cdrom:\SCUS_941.63;1" -> "SCUS94163" */
static void detect_id(disc_t *d)
{
	uint8_t raw[SECTOR_RAW], cnf[2049];
	const uint8_t *pvd;
	uint32_t root_lba, root_size, lba, size;
	char *p;

	strcpy(d->id, "");
	if (read_sector_at(d, 16, raw) != 0)
		return;
	pvd = user_data(raw);
	if (pvd[0] != 1 || memcmp(pvd + 1, "CD001", 5) != 0)
		return;
	memcpy(d->label, pvd + 40, 32);
	for (int i = 31; i >= 0 && (d->label[i] == ' ' || d->label[i] == '\0'); i--)
		d->label[i] = '\0';
	root_lba = get_le32(pvd + 156 + 2);
	root_size = get_le32(pvd + 156 + 10);
	if (iso_find_file(d, root_lba, root_size, "SYSTEM.CNF", &lba, &size) != 0)
		return;
	if (read_sector_at(d, lba, raw) != 0)
		return;
	memcpy(cnf, user_data(raw), 2048);
	cnf[size < 2048 ? size : 2048] = '\0';
	for (p = (char *)cnf; *p; p++)
		*p = (char)toupper((unsigned char)*p);
	p = strstr((char *)cnf, "BOOT");
	if (!p)
		return;
	p = strchr(p, '=');
	if (!p)
		return;
	{
		char path[256], *b, *e;
		int n = 0;
		p++;
		while (*p == ' ' || *p == '\t')
			p++;
		snprintf(path, sizeof(path), "%s", p);
		e = path + strcspn(path, ";\r\n \t");
		*e = '\0';
		b = path;
		for (char *s = path; *s; s++)
			if (*s == '\\' || *s == ':' || *s == '/')
				b = s + 1;
		for (char *s = b; *s && n < 9; s++)
			if (isalnum((unsigned char)*s))
				d->id[n++] = *s;
		d->id[n] = '\0';
	}
}

/* sequential reader over all files of a disc; pads the tail with zeros */
static size_t read_seq(disc_t *d, uint8_t *buf, size_t sectors)
{
	size_t done = 0;
	while (done < sectors) {
		size_t got;
		if (!d->fp) {
			if (d->cur_file + 1 >= d->nfiles)
				break;
			d->cur_file++;
			d->fp = fopen(d->files[d->cur_file], "rb");
			if (!d->fp)
				die("no se pudo abrir %s", d->files[d->cur_file]);
		}
		got = fread(buf + done * SECTOR_RAW, SECTOR_RAW, sectors - done, d->fp);
		done += got;
		if (got == 0 || done < sectors) {
			if (ferror(d->fp))
				die("error leyendo %s", d->files[d->cur_file]);
			fclose(d->fp);
			d->fp = NULL;
		}
	}
	return done;
}

/* ---- parallel deflate ---- */

typedef struct {
	const uint8_t *in;  /* nblocks * BLOCK_RAW */
	uint8_t *out;       /* nblocks * out_stride */
	uint32_t *out_len;
	int first, step, nblocks, level;
	size_t out_stride;
} job_t;

static void *compress_worker(void *arg)
{
	job_t *j = arg;
	z_stream z;

	memset(&z, 0, sizeof(z));
	if (deflateInit2(&z, j->level, Z_DEFLATED, -15, 9, Z_DEFAULT_STRATEGY) != Z_OK)
		die("deflateInit2 fallo");
	for (int b = j->first; b < j->nblocks; b += j->step) {
		deflateReset(&z);
		z.next_in = (uint8_t *)j->in + (size_t)b * BLOCK_RAW;
		z.avail_in = BLOCK_RAW;
		z.next_out = j->out + (size_t)b * j->out_stride;
		z.avail_out = (uInt)j->out_stride;
		if (deflate(&z, Z_FINISH) != Z_STREAM_END)
			die("deflate fallo");
		j->out_len[b] = (uint32_t)(j->out_stride - z.avail_out);
	}
	deflateEnd(&z);
	return NULL;
}

static int cpu_count(void)
{
#ifdef _WIN32
	SYSTEM_INFO si;
	GetSystemInfo(&si);
	return si.dwNumberOfProcessors > 0 ? (int)si.dwNumberOfProcessors : 1;
#else
	long n = sysconf(_SC_NPROCESSORS_ONLN);
	return n > 0 ? (int)n : 1;
#endif
}

/* ---- output ---- */

static void xwrite(FILE *f, const void *p, size_t n)
{
	if (n && fwrite(p, 1, n, f) != n)
		die("error escribiendo la salida (¿disco lleno?)");
}

static void write_zeros(FILE *f, uint64_t n)
{
	static const uint8_t z[4096];
	while (n) {
		size_t c = n > sizeof(z) ? sizeof(z) : (size_t)n;
		xwrite(f, z, c);
		n -= c;
	}
}

static void pad_to(FILE *f, uint64_t align)
{
	uint64_t pos = (uint64_t)ftell64(f);
	if (pos % align)
		write_zeros(f, align - pos % align);
}

typedef struct {
	const char *key;
	int is_int;
	const char *str;
	uint32_t val;
	uint32_t max;
} sfo_entry_t;

static size_t build_sfo(uint8_t *out, const char *title, const char *id)
{
	sfo_entry_t e[] = {
		{ "BOOTABLE", 1, NULL, 1, 4 },
		{ "CATEGORY", 0, "ME", 0, 4 },
		{ "DISC_ID", 0, id, 0, 16 },
		{ "DISC_VERSION", 0, "1.00", 0, 8 },
		{ "LICENSE", 0, "Written by pbpack", 0, 512 },
		{ "PARENTAL_LEVEL", 1, NULL, 1, 4 },
		{ "PSP_SYSTEM_VER", 0, "3.01", 0, 8 },
		{ "REGION", 1, NULL, 0x8000, 4 },
		{ "TITLE", 0, title, 0, 128 },
	};
	const int n = sizeof(e) / sizeof(e[0]);
	uint32_t key_off = 0x14 + 0x10 * n, keys_len = 0, data_off, data_len = 0;
	uint8_t *p;

	for (int i = 0; i < n; i++)
		keys_len += (uint32_t)strlen(e[i].key) + 1;
	data_off = key_off + ((keys_len + 3) & ~3u);

	memcpy(out, "\0PSF", 4);
	put_le32(out + 4, 0x101);
	put_le32(out + 8, key_off);
	put_le32(out + 12, data_off);
	put_le32(out + 16, n);

	keys_len = 0;
	for (int i = 0; i < n; i++) {
		p = out + 0x14 + 0x10 * i;
		put_le16(p, (uint16_t)keys_len);
		put_le16(p + 2, e[i].is_int ? 0x0404 : 0x0204);
		if (e[i].is_int) {
			put_le32(p + 4, 4);
			put_le32(out + data_off + data_len, e[i].val);
		} else {
			size_t l = strlen(e[i].str) + 1;
			if (l > e[i].max)
				l = e[i].max;
			put_le32(p + 4, (uint32_t)l);
			memcpy(out + data_off + data_len, e[i].str, l - 1);
		}
		put_le32(p + 8, e[i].max);
		put_le32(p + 12, data_len);
		strcpy((char *)out + key_off + keys_len, e[i].key);
		keys_len += (uint32_t)strlen(e[i].key) + 1;
		data_len += e[i].max;
	}
	return data_off + data_len;
}

static void build_toc(const disc_t *d, uint8_t *toc)
{
	uint8_t *t = toc;

	/* A0: first track, disc type CD-XA */
	t[0] = 0x41; t[2] = 0xA0; t[7] = 0x01; t[8] = 0x20; t += 10;
	/* A1: last track */
	t[0] = 0x41; t[2] = 0xA1; t[7] = bcd(d->ntracks); t += 10;
	/* A2: sectors in the image (what both readers compute track lengths from) */
	t[0] = 0x41; t[2] = 0xA2; lba_to_bcd_msf(d->sectors, t + 7); t += 10;
	for (int i = 0; i < d->ntracks; i++) {
		t[0] = d->tracks[i].audio ? 0x01 : 0x41;
		t[2] = bcd(i + 1);
		/* first MSF: position inside the image, second: absolute (2 s lead-in) */
		lba_to_bcd_msf(d->tracks[i].file_lba, t + 3);
		lba_to_bcd_msf(d->tracks[i].file_lba + 150, t + 7);
		t += 10;
	}
}

static uint32_t pack_disc(FILE *out, disc_t *d, int dnum, int ndiscs, int level, int threads,
			  uint32_t *crc_out)
{
	const int batch = threads * 16;
	const size_t stride = BLOCK_RAW + 1024;
	uint8_t *hdr = xcalloc(ISO_HDR_SIZE, 1);
	uint8_t *in = xcalloc((size_t)batch, BLOCK_RAW);
	uint8_t *cbuf = xcalloc((size_t)batch, stride);
	uint32_t *clen = xcalloc((size_t)batch, sizeof(uint32_t));
	uint32_t nblocks = (d->sectors + BLOCK_SECTORS - 1) / BLOCK_SECTORS;
	uint32_t blk = 0, data_len = 0, crc = crc32(0, NULL, 0), left = d->sectors;
	int64_t start = ftell64(out);
	int last_pct = -1;
	pthread_t *tid = xcalloc((size_t)threads, sizeof(pthread_t));
	job_t *jobs = xcalloc((size_t)threads, sizeof(job_t));

	memcpy(hdr, "PSISOIMG0000", 12);
	hdr[0x400] = '_';
	memcpy(hdr + 0x401, d->id, 4);
	hdr[0x405] = '_';
	memcpy(hdr + 0x406, d->id + 4, strlen(d->id) > 4 ? strlen(d->id) - 4 : 0);
	build_toc(d, hdr + 0x800);
	put_le32(hdr + 0xBFC, ISO_HDR_SIZE);
	xwrite(out, hdr, ISO_HDR_SIZE); /* rewritten with the index at the end */

	d->cur_file = -1;
	d->fp = NULL;
	while (blk < nblocks) {
		int nb = (int)(nblocks - blk < (uint32_t)batch ? nblocks - blk : (uint32_t)batch);
		size_t want = (size_t)nb * BLOCK_SECTORS, got;
		int nt = threads < nb ? threads : nb;

		memset(in, 0, (size_t)nb * BLOCK_RAW);
		got = read_seq(d, in, want > left ? left : want);
		if (got != (want > left ? left : want))
			die("%s: lectura incompleta", d->path);
		crc = crc32(crc, in, (uInt)(got * SECTOR_RAW));
		left -= (uint32_t)got;

		for (int t = 0; t < nt; t++) {
			jobs[t] = (job_t){ in, cbuf, clen, t, nt, nb, level, stride };
			if (nt == 1)
				compress_worker(&jobs[t]);
			else if (pthread_create(&tid[t], NULL, compress_worker, &jobs[t]) != 0)
				die("no se pudo crear un hilo");
		}
		if (nt > 1)
			for (int t = 0; t < nt; t++)
				pthread_join(tid[t], NULL);

		for (int b = 0; b < nb; b++) {
			uint8_t *e = hdr + ISO_INDEX_OFF + (size_t)(blk + b) * 32;
			if (clen[b] > 0xFFFF)
				die("bloque comprimido demasiado grande");
			put_le32(e, data_len);
			put_le16(e + 4, (uint16_t)clen[b]);
			xwrite(out, cbuf + (size_t)b * stride, clen[b]);
			if ((uint64_t)data_len + clen[b] > 0xF0000000u)
				die("la salida supera el limite de 4 GB del formato");
			data_len += clen[b];
		}
		blk += nb;

		{
			int pct = (int)((uint64_t)blk * 100 / nblocks);
			if (pct / 5 != last_pct / 5 || blk == nblocks) {
				info("  Disco %d/%d: %3d%%\n", dnum, ndiscs, pct);
				last_pct = pct;
			}
		}
	}
	if (d->fp)
		fclose(d->fp);
	d->fp = NULL;

	/* terminator: size 0, offset = end of data (PCSX-ReARMed derives the
	 * length of the last block from this entry's offset) */
	if (nblocks < ISO_INDEX_MAX)
		put_le32(hdr + ISO_INDEX_OFF + (size_t)nblocks * 32, data_len);
	put_le32(hdr + 0x0C, ISO_HDR_SIZE + data_len);

	fseek64(out, start, SEEK_SET);
	xwrite(out, hdr, ISO_HDR_SIZE);
	fseek64(out, 0, SEEK_END);

	free(hdr); free(in); free(cbuf); free(clen); free(tid); free(jobs);
	*crc_out = crc;
	return ISO_HDR_SIZE + data_len;
}

/* ---- verification: re-read the output the way PCSX-ReARMed does ---- */

static int verify(const char *path, disc_t *discs, int ndiscs, const uint32_t *crcs)
{
	FILE *f = fopen(path, "rb");
	uint8_t hdr[0x28], sig[16], *idx = xcalloc(ISO_HDR_SIZE, 1);
	uint8_t *cb = xcalloc(BLOCK_RAW + 1024, 1), *raw = xcalloc(BLOCK_RAW, 1);
	uint32_t psar, offs[MAX_DISCS] = { 0 };
	int count = 1, ok = 1;
	z_stream z;

	if (!f || fread(hdr, 1, sizeof(hdr), f) != sizeof(hdr) || memcmp(hdr, "\0PBP", 4) != 0)
		die("verificacion: cabecera PBP invalida");
	psar = get_le32(hdr + 0x24);
	fseek64(f, psar, SEEK_SET);
	if (fread(sig, 1, 16, f) != 16)
		die("verificacion: no se pudo leer DATA.PSAR");
	if (memcmp(sig, "PSTITLEIMG", 10) == 0) {
		uint8_t t[4 * MAX_DISCS];
		fseek64(f, psar + 0x200, SEEK_SET);
		if (fread(t, 1, sizeof(t), f) != sizeof(t))
			die("verificacion: tabla de discos ilegible");
		for (count = 0; count < MAX_DISCS && get_le32(t + 4 * count); count++)
			offs[count] = get_le32(t + 4 * count);
	} else if (memcmp(sig, "PSISOIMG00", 10) != 0) {
		die("verificacion: DATA.PSAR invalido");
	}
	if (count != ndiscs)
		die("verificacion: %d discos en el archivo, se esperaban %d", count, ndiscs);

	memset(&z, 0, sizeof(z));
	inflateInit2(&z, -15);
	for (int i = 0; i < count; i++) {
		int64_t base = (int64_t)psar + offs[i];
		uint32_t crc = crc32(0, NULL, 0), left = discs[i].sectors;
		uint32_t nblocks = (left + BLOCK_SECTORS - 1) / BLOCK_SECTORS;

		fseek64(f, base, SEEK_SET);
		if (fread(idx, 1, ISO_HDR_SIZE, f) != ISO_HDR_SIZE || memcmp(idx, "PSISOIMG00", 10) != 0)
			die("verificacion: disco %d sin cabecera PSISOIMG", i + 1);
		for (uint32_t b = 0; b < nblocks; b++) {
			const uint8_t *e = idx + ISO_INDEX_OFF + (size_t)b * 32;
			const uint8_t *n = e + 32;
			uint32_t off = get_le32(e), size = get_le32(n) - off;
			uint32_t take = left < BLOCK_SECTORS ? left : BLOCK_SECTORS;
			if ((uint32_t)(e[4] | (e[5] << 8)) != size || size > BLOCK_RAW + 100)
				die("verificacion: indice inconsistente en disco %d bloque %u", i + 1, b);
			fseek64(f, base + ISO_HDR_SIZE + off, SEEK_SET);
			if (fread(cb, 1, size, f) != size)
				die("verificacion: lectura corta en disco %d", i + 1);
			inflateReset(&z);
			z.next_in = cb; z.avail_in = size;
			z.next_out = raw; z.avail_out = BLOCK_RAW;
			if (inflate(&z, Z_NO_FLUSH) != Z_STREAM_END || z.avail_out != 0)
				die("verificacion: bloque %u del disco %d no descomprime", b, i + 1);
			crc = crc32(crc, raw, take * SECTOR_RAW);
			left -= take;
		}
		if (crc != crcs[i]) {
			fprintf(stderr, "ERROR: disco %d: CRC distinto (%08x != %08x)\n", i + 1, crc, crcs[i]);
			ok = 0;
		} else {
			info("  Disco %d verificado (CRC32 %08x)\n", i + 1, crc);
		}
	}
	inflateEnd(&z);
	fclose(f);
	free(idx); free(cb); free(raw);
	return ok;
}

static void usage(void)
{
	printf("pbpack " PBPACK_VERSION " - junta varios discos de PlayStation en un solo .pbp\n\n"
	       "uso: pbpack [opciones] -o salida.pbp disco1.cue [disco2.cue ...]\n\n"
	       "  -o ARCHIVO   archivo .pbp de salida\n"
	       "  -t TITULO    titulo (por defecto: nombre del archivo de salida)\n"
	       "  -i ID        codigo del juego, ej. SCUS94163 (por defecto: se lee del disco 1)\n"
	       "  -l NIVEL     compresion 1-9 (por defecto 6)\n"
	       "  -j HILOS     hilos de compresion (por defecto: todos los nucleos)\n"
	       "  -n           solo mostrar informacion de los discos, no escribir nada\n"
	       "  -V           verificar el .pbp al terminar (relee y compara CRC32)\n"
	       "  -s           ordenar los discos por su codigo (SCUS94163 < SCUS94164 ...)\n"
	       "  -f           empaquetar aunque un disco este incompleto (no recomendado)\n"
	       "  -q           silencioso\n\n"
	       "Entradas: .cue (con sus .bin) o imagenes crudas .bin/.img de 2352 bytes/sector.\n"
	       "Maximo %d discos.\n", MAX_DISCS);
}

int main(int argc, char **argv)
{
	const char *outp = NULL, *title = NULL, *id = NULL;
	int level = 6, threads = 0, dry = 0, do_verify = 0, sort_id = 0, force = 0, ndiscs = 0;
	int incomplete = 0;
	disc_t discs[MAX_DISCS];
	uint32_t crcs[MAX_DISCS], disc_off[MAX_DISCS];
	char *tmp, *deftitle = NULL;
	FILE *out;
	uint8_t pbphdr[0x28] = { 0 }, sfo[2048] = { 0 };
	size_t sfo_len;
	int64_t psar;

	for (int i = 1; i < argc; i++) {
		const char *a = argv[i];
		if (a[0] == '-' && a[1] && !a[2]) {
			const char *v = (strchr("otilj", a[1]) && i + 1 < argc) ? argv[i + 1] : NULL;
			switch (a[1]) {
			case 'o': outp = v; i++; break;
			case 't': title = v; i++; break;
			case 'i': id = v; i++; break;
			case 'l': level = v ? atoi(v) : 0; i++; break;
			case 'j': threads = v ? atoi(v) : 0; i++; break;
			case 'n': dry = 1; break;
			case 'V': do_verify = 1; break;
			case 's': sort_id = 1; break;
			case 'f': force = 1; break;
			case 'q': quiet = 1; break;
			case 'h': usage(); return 0;
			default: usage(); return 1;
			}
			if (strchr("otilj", a[1]) && !v)
				die("falta el valor de -%c", a[1]);
		} else if (strcmp(a, "--help") == 0 || strcmp(a, "--version") == 0) {
			usage();
			return 0;
		} else {
			if (ndiscs >= MAX_DISCS)
				die("maximo %d discos", MAX_DISCS);
			open_disc(&discs[ndiscs++], a);
		}
	}
	if (ndiscs == 0 || (!outp && !dry)) {
		usage();
		return 1;
	}
	if (level < 1 || level > 9)
		die("nivel de compresion invalido (1-9)");
	if (threads <= 0)
		threads = cpu_count();
	if (threads > 64)
		threads = 64;

	for (int i = 0; i < ndiscs; i++) {
		check_raw(&discs[i]);
		detect_id(&discs[i]);
	}
	if (sort_id) {
		/* stable insertion sort; discs without an id keep their place at the end */
		for (int i = 1; i < ndiscs; i++) {
			disc_t t = discs[i];
			int j = i - 1;
			while (j >= 0 && t.id[0] && (!discs[j].id[0] || strcmp(discs[j].id, t.id) > 0)) {
				discs[j + 1] = discs[j];
				j--;
			}
			discs[j + 1] = t;
		}
	}
	for (int i = 0; i < ndiscs; i++) {
		uint32_t vol, need = iso_needed_sectors(&discs[i], &vol);
		info("Disco %d: %s\n  ID %s, etiqueta '%s', %u sectores, %d pista(s), %d archivo(s)\n",
		     i + 1, discs[i].path, discs[i].id[0] ? discs[i].id : "(desconocido)",
		     discs[i].label, discs[i].sectors, discs[i].ntracks, discs[i].nfiles);
		if (need > discs[i].sectors) {
			fprintf(stderr,
				"%s: el disco %d (%s) esta INCOMPLETO.\n"
				"  El archivo tiene %u sectores (%u MB) y los datos del disco llegan\n"
				"  hasta el sector %u (%u MB). El .bin esta cortado o es una version\n"
				"  recortada: con el, el juego se queda en pantalla negra.\n"
				"  Hace falta la imagen completa del disco.\n",
				force ? "AVISO" : "ERROR", i + 1, path_basename(discs[i].path), discs[i].sectors,
				(unsigned)((uint64_t)discs[i].sectors * SECTOR_RAW >> 20), need,
				(unsigned)((uint64_t)need * SECTOR_RAW >> 20));
			incomplete = 1;
		} else if (vol > discs[i].sectors) {
			info("  aviso: el disco declara %u sectores y la imagen tiene %u\n", vol,
			     discs[i].sectors);
		}
	}
	if (incomplete && !force && !dry)
		die("no se crea el .pbp porque falta parte de los discos (usar -f para forzar)");
	if (dry)
		return 0;

	if (!id)
		id = discs[0].id[0] ? discs[0].id : "SLUS00000";
	if (strlen(id) > 9)
		die("ID demasiado largo: %s", id);
	if (!title) {
		const char *b = path_basename(outp);
		deftitle = xstrdup(b);
		tmp = strrchr(deftitle, '.');
		if (tmp)
			*tmp = '\0';
		title = deftitle;
	}
	for (int i = 0; i < ndiscs; i++)
		if (!discs[i].id[0])
			snprintf(discs[i].id, sizeof(discs[i].id), "%s", id);

	out = fopen(outp, "wb");
	if (!out)
		die("no se pudo crear %s: %s", outp, strerror(errno));

	info("Creando %s (%d disco(s), titulo '%s', ID %s, nivel %d, %d hilo(s))\n",
	     outp, ndiscs, title, id, level, threads);

	sfo_len = build_sfo(sfo, title, id);
	memcpy(pbphdr, "\0PBP", 4);
	put_le32(pbphdr + 4, 0x10000);
	put_le32(pbphdr + 8, 0x28);
	for (int s = 1; s < 7; s++) /* ICON0 .. DATA.PSP: empty */
		put_le32(pbphdr + 8 + 4 * s, (uint32_t)(0x28 + sfo_len));
	psar = (0x28 + (int64_t)sfo_len + PSAR_ALIGN - 1) / PSAR_ALIGN * PSAR_ALIGN;
	put_le32(pbphdr + 0x24, (uint32_t)psar);
	xwrite(out, pbphdr, sizeof(pbphdr));
	xwrite(out, sfo, sfo_len);
	pad_to(out, PSAR_ALIGN);

	if (ndiscs > 1) {
		uint8_t th[DISC_ALIGN] = { 0 };
		memcpy(th, "PSTITLEIMG000000", 16);
		th[0x400] = '_';
		memcpy(th + 0x401, id, 4);
		th[0x405] = '_';
		memcpy(th + 0x406, id + 4, strlen(id) > 4 ? strlen(id) - 4 : 0);
		xwrite(out, th, sizeof(th)); /* disc table filled in below */
	}

	for (int i = 0; i < ndiscs; i++) {
		int64_t pos;
		pad_to(out, DISC_ALIGN);
		pos = ftell64(out) - psar;
		if (pos > 0xF0000000LL)
			die("la salida supera el limite de 4 GB del formato");
		disc_off[i] = (uint32_t)pos;
		info("Comprimiendo disco %d/%d (%s)...\n", i + 1, ndiscs, discs[i].id);
		pack_disc(out, &discs[i], i + 1, ndiscs, level, threads, &crcs[i]);
	}

	if (ndiscs > 1) {
		uint8_t t[4 * MAX_DISCS] = { 0 };
		for (int i = 0; i < ndiscs; i++)
			put_le32(t + 4 * i, disc_off[i]);
		fseek64(out, psar + 0x200, SEEK_SET);
		xwrite(out, t, sizeof(t));
	}
	if (fclose(out) != 0)
		die("error cerrando %s (¿disco lleno?)", outp);
	{
		uint64_t sz = 0;
		if (file_size(outp, &sz) == 0 && sz >= 0x80000000ull)
			info("aviso: el archivo supera 2 GB; usar un emulador de 64 bits "
			     "(RetroArch 64 bits / PCSX-ReARMed reciente)\n");
	}

	if (do_verify) {
		info("Verificando...\n");
		if (!verify(outp, discs, ndiscs, crcs)) {
			fprintf(stderr, "ERROR: la verificacion fallo; borrando %s\n", outp);
			remove(outp);
			return 2;
		}
	}
	info("Listo: %s\n", outp);
	free(deftitle);
	return 0;
}
