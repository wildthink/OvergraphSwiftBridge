#ifndef OVERGRAPH_SWIFT_BRIDGE_H
#define OVERGRAPH_SWIFT_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void *og_db_handle_ref;

og_db_handle_ref og_db_open(const char *path_utf8, const char *options_json_utf8, char **error_utf8);
bool og_db_close(og_db_handle_ref handle, bool force, char **error_utf8);
char *og_db_call(og_db_handle_ref handle, const char *request_json_utf8, char **error_utf8);
void og_db_destroy(og_db_handle_ref handle);
void og_string_free(char *value);

#ifdef __cplusplus
}
#endif

#endif
