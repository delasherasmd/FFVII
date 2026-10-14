/*
 * Minimal headless libretro frontend: loads a content file into a core,
 * lists the discs the core exposes through the disk control interface,
 * then boots each disc in turn (eject, select, close, reset) the way
 * RetroArch's Disc Control menu does.  Core log lines go to stdout.
 *
 * With a 4th argument the game is started directly on that disc (0 based),
 * like RetroArch does when content is reopened after a disc change.
 *
 * build: cc -o lrtest lrtest.c -ldl -I<libretro-common>/include
 * usage: lrtest core.so game.pbp [frames [initial_disc]]
 */
#include <dlfcn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libretro.h"

static struct retro_disk_control_callback dc;
static struct retro_disk_control_ext_callback dcx;
static int have_dc, have_dcx;
static const char *sysdir = ".";

static void log_cb(enum retro_log_level level, const char *fmt, ...)
{
	va_list ap;
	(void)level;
	va_start(ap, fmt);
	printf("[core] ");
	vprintf(fmt, ap);
	va_end(ap);
	fflush(stdout);
}

static bool env_cb(unsigned cmd, void *data)
{
	switch (cmd) {
	case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
		((struct retro_log_callback *)data)->log = log_cb;
		return true;
	case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
	case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY:
		*(const char **)data = sysdir;
		return true;
	case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
	case RETRO_ENVIRONMENT_GET_CAN_DUPE:
		return true;
	case RETRO_ENVIRONMENT_GET_DISK_CONTROL_INTERFACE_VERSION:
		*(unsigned *)data = 1;
		return true;
	case RETRO_ENVIRONMENT_SET_DISK_CONTROL_INTERFACE:
		dc = *(struct retro_disk_control_callback *)data;
		have_dc = 1;
		return true;
	case RETRO_ENVIRONMENT_SET_DISK_CONTROL_EXT_INTERFACE:
		dcx = *(struct retro_disk_control_ext_callback *)data;
		have_dcx = 1;
		return true;
	default:
		return false;
	}
}

static void video_cb(const void *d, unsigned w, unsigned h, size_t p) { (void)d; (void)w; (void)h; (void)p; }
static void audio_cb(int16_t l, int16_t r) { (void)l; (void)r; }
static size_t audio_batch_cb(const int16_t *d, size_t f) { (void)d; return f; }
static void input_poll_cb(void) {}
static int16_t input_state_cb(unsigned p, unsigned d, unsigned i, unsigned id) { (void)p; (void)d; (void)i; (void)id; return 0; }

#define SYM(name) do { *(void **)&p_##name = dlsym(h, #name); if (!p_##name) { fprintf(stderr, "missing %s\n", #name); return 1; } } while (0)

int main(int argc, char **argv)
{
	void *h;
	void (*p_retro_set_environment)(retro_environment_t);
	void (*p_retro_set_video_refresh)(retro_video_refresh_t);
	void (*p_retro_set_audio_sample)(retro_audio_sample_t);
	void (*p_retro_set_audio_sample_batch)(retro_audio_sample_batch_t);
	void (*p_retro_set_input_poll)(retro_input_poll_t);
	void (*p_retro_set_input_state)(retro_input_state_t);
	void (*p_retro_init)(void);
	bool (*p_retro_load_game)(const struct retro_game_info *);
	void (*p_retro_run)(void);
	void (*p_retro_reset)(void);
	void (*p_retro_unload_game)(void);
	void (*p_retro_deinit)(void);
	struct retro_game_info gi = { 0 };
	int frames = argc > 3 ? atoi(argv[3]) : 120;
	unsigned n;

	if (argc < 3) {
		fprintf(stderr, "usage: %s core.so game [frames]\n", argv[0]);
		return 1;
	}
	if (getenv("LRTEST_SYSDIR"))
		sysdir = getenv("LRTEST_SYSDIR");
	h = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
	if (!h) {
		fprintf(stderr, "dlopen: %s\n", dlerror());
		return 1;
	}
	SYM(retro_set_environment); SYM(retro_set_video_refresh); SYM(retro_set_audio_sample);
	SYM(retro_set_audio_sample_batch); SYM(retro_set_input_poll); SYM(retro_set_input_state);
	SYM(retro_init); SYM(retro_load_game); SYM(retro_run); SYM(retro_reset);
	SYM(retro_unload_game); SYM(retro_deinit);

	p_retro_set_environment(env_cb);
	p_retro_set_video_refresh(video_cb);
	p_retro_set_audio_sample(audio_cb);
	p_retro_set_audio_sample_batch(audio_batch_cb);
	p_retro_set_input_poll(input_poll_cb);
	p_retro_set_input_state(input_state_cb);
	p_retro_init();

	gi.path = argv[2];
	if (argc > 4) {
		if (!have_dcx || !dcx.set_initial_image) {
			printf("RESULT no set_initial_image\n");
			return 3;
		}
		dcx.set_initial_image((unsigned)atoi(argv[4]), argv[2]);
		printf("RESULT initial disc %d\n", atoi(argv[4]) + 1);
	}
	if (!p_retro_load_game(&gi)) {
		printf("RESULT load_game FAILED\n");
		return 2;
	}
	printf("RESULT load_game OK\n");
	if (!have_dc && !have_dcx) {
		printf("RESULT no disk control interface\n");
		return 3;
	}
	if (have_dcx)
		memcpy(&dc, &dcx, sizeof(dc)); /* ext starts with the same members */

	n = dc.get_num_images();
	printf("RESULT discs %u\n", n);
	for (unsigned i = 0; i < n; i++) {
		char label[256] = "";
		if (have_dcx && dcx.get_image_label)
			dcx.get_image_label(i, label, sizeof(label));
		printf("RESULT disc %u label '%s'\n", i + 1, label);
	}

	for (int f = 0; f < frames; f++)
		p_retro_run();
	printf("RESULT game ran %d frames\n", frames);

	printf("RESULT current index %u\n", dc.get_image_index());
	for (unsigned i = 1; i < n && argc <= 4; i++) {
		bool ok = dc.set_eject_state(true) && dc.set_image_index(i) && dc.set_eject_state(false);
		printf("RESULT swap to disc %u %s, current index %u\n", i + 1, ok ? "OK" : "FAILED",
		       dc.get_image_index());
		p_retro_reset();
		for (int f = 0; f < frames; f++)
			p_retro_run();
		printf("RESULT disc %u ran %d frames\n", i + 1, frames);
	}

	p_retro_unload_game();
	p_retro_deinit();
	return 0;
}
