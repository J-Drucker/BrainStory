#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <v4/eep.h>

static cntfile_t current_handle = -1;
static float *current_samples = NULL;

static void close_current(void) {
  if (current_samples != NULL) {
    libeep_free_samples(current_samples);
    current_samples = NULL;
  }
  if (current_handle >= 0) {
    libeep_close(current_handle);
    current_handle = -1;
    libeep_exit();
  }
}

int bs_cnt_open(const char *path) {
  close_current();
  libeep_init();
  current_handle = libeep_read_with_external_triggers(path);
  if (current_handle < 0) {
    libeep_exit();
    return 0;
  }
  int64_t sample_count = libeep_get_sample_count(current_handle);
  if (sample_count <= 0) {
    close_current();
    return 0;
  }
  current_samples = libeep_get_samples(current_handle, 0, sample_count);
  if (current_samples == NULL) {
    close_current();
    return 0;
  }
  return 1;
}

void bs_cnt_close(void) { close_current(); }
int bs_cnt_channel_count(void) { return libeep_get_channel_count(current_handle); }
int bs_cnt_sample_rate(void) { return libeep_get_sample_frequency(current_handle); }
int64_t bs_cnt_sample_count(void) { return libeep_get_sample_count(current_handle); }
const char *bs_cnt_channel_label(int index) {
  return libeep_get_channel_label(current_handle, index);
}
float *bs_cnt_samples(void) { return current_samples; }
int bs_cnt_trigger_count(void) { return libeep_get_trigger_count(current_handle); }

const char *bs_cnt_trigger(int index, uint64_t *sample,
                           struct libeep_trigger_extension *extension) {
  return libeep_get_trigger_with_extensions(
      current_handle, index, sample, extension);
}
